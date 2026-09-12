import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../models/private_study.dart';
import 'database_service.dart';

/// 「我的研讀」private personal-data repository。
///
/// - Local-first：沿用既有 [DatabaseService] 的同一 SQLite / IndexedDB。
/// - Cloud backup：只寫 `users/{uid}/private_study_*`，由既有 users/** rules 限本人。
/// - LWW：以 updated_at 合併；empty cloud 不會覆蓋有效 local。
/// - 刪除：先 soft delete；永久刪除沿用既有 tombstones table，同步後刪 cloud doc。
/// - 完全獨立於 study_content / Admin workflow / Church audience / Q&A AnswerSource。
class PrivateStudyRepository {
  PrivateStudyRepository(this.db);

  final DatabaseService db;
  bool _initialized = false;

  static const _bookTable = 'private_study_books';
  static const _noteTable = 'private_study_notes';
  static const _metaTable = 'private_study_meta';
  static const _bookKind = 'private_study_book';
  static const _noteKind = 'private_study_note';
  static const _retentionMs = 30 * 24 * 60 * 60 * 1000;
  bool _syncing = false; // sync 重入/序列化守衛（§八G/§八J）

  String newBookId() => 'psb_${DateTime.now().microsecondsSinceEpoch}';
  String newNoteId() => 'psn_${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _ready() async {
    if (_initialized) return;
    final sql = await db.database;
    await sql.execute('''
      CREATE TABLE IF NOT EXISTS $_bookTable (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        author TEXT NOT NULL DEFAULT '',
        deleted_at INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        last_studied_at INTEGER NOT NULL
      )
    ''');
    await sql.execute('''
      CREATE TABLE IF NOT EXISTS $_noteTable (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        quote TEXT NOT NULL DEFAULT '',
        topics TEXT NOT NULL DEFAULT '[]',
        reflection TEXT NOT NULL DEFAULT '',
        scripture_refs TEXT NOT NULL DEFAULT '[]',
        source_location TEXT NOT NULL DEFAULT '',
        practice TEXT NOT NULL DEFAULT '',
        deleted_at INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await sql.execute(
        'CREATE INDEX IF NOT EXISTS idx_private_study_notes_book ON $_noteTable(book_id)');
    await sql.execute(
        'CREATE INDEX IF NOT EXISTS idx_private_study_notes_deleted ON $_noteTable(deleted_at)');
    // 這些表在 repository 內以 CREATE IF NOT EXISTS 建立（不在 DatabaseService migration 框架）。
    // 既有使用者的表可能缺新欄位，故以 idempotent ALTER 補（重複欄位錯誤忽略）。行動雙平台適用。
    await _ensureColumn(sql, _noteTable, 'book_deleted_at',
        'INTEGER NOT NULL DEFAULT 0');
    // 帳號歸屬 marker：private personal data 不可跨帳號 sync（§八I）。
    await sql.execute('''
      CREATE TABLE IF NOT EXISTS $_metaTable (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    _initialized = true;
    await _purgeExpired();
  }

  Future<void> _ensureColumn(
      dynamic sql, String table, String column, String decl) async {
    try {
      final info = await sql.rawQuery('PRAGMA table_info($table)');
      final has = info.any((r) => r['name']?.toString() == column);
      if (!has) {
        await sql.execute('ALTER TABLE $table ADD COLUMN $column $decl');
      }
    } catch (_) {
      // 已存在或不支援 PRAGMA 時，嘗試直接 ALTER 並吞掉「duplicate column」錯誤。
      try {
        await sql.execute('ALTER TABLE $table ADD COLUMN $column $decl');
      } catch (_) {}
    }
  }

  // ---- 純決策函式（可測、無 IO；sync/cascade 正確性核心）----

  /// tombstone（永久刪除標記）是否應擋下一筆較舊的 remote live doc（防復活，§八A/D）。
  /// tombstone 較新或同時 → 擋；remote 較新（合法 restore/edit）→ 不擋（且呼叫端應清舊 tombstone）。
  static bool tombstoneBlocksResurrection(
          int tombstoneDeletedAt, int remoteUpdatedAt) =>
      tombstoneDeletedAt >= remoteUpdatedAt;

  /// Book restore 時，某 note 是否應隨之復活（§八C）：
  /// 只有「因該次 Book 級聯刪除」的 note（bookDeletedAt == 被還原 Book 的 deletedAt 且 >0）才復活；
  /// 在 Book 刪除前就被個別刪除的 note（bookDeletedAt==0）**不得**復活。
  static bool shouldRestoreCascadedNote(
          int noteBookDeletedAt, int bookDeletedAt) =>
      bookDeletedAt > 0 && noteBookDeletedAt == bookDeletedAt;

  /// 帳號歸屬決策（§八I）：
  /// - 'adopt'：本機資料尚無歸屬（guest 或全新）→ 收養為目前 uid，正常 merge/upload（Guest→Login）。
  /// - 'same'：歸屬 == 目前 uid → 正常 sync。
  /// - 'switch'：歸屬 != 目前 uid → 換帳號，**不得把上一使用者本機資料上傳到目前帳號**。
  static String ownerAction(String? storedOwner, String currentUid) {
    if (storedOwner == null || storedOwner.isEmpty) return 'adopt';
    if (storedOwner == currentUid) return 'same';
    return 'switch';
  }

  List<String> _strings(Object? raw) {
    if (raw is List) return raw.map((e) => e.toString()).toList();
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded.map((e) => e.toString()).toList();
      } catch (_) {}
    }
    return const [];
  }

  PrivateStudyBook _bookFromLocal(Map<String, Object?> m) =>
      PrivateStudyBook.fromMap(m.cast<String, dynamic>());

  PrivateStudyNote _noteFromLocal(Map<String, Object?> m) => PrivateStudyNote(
        id: m['id']?.toString() ?? '',
        bookId: m['book_id']?.toString() ?? '',
        quote: m['quote']?.toString() ?? '',
        topics: _strings(m['topics']),
        reflection: m['reflection']?.toString() ?? '',
        scriptureRefs: _strings(m['scripture_refs']),
        sourceLocation: m['source_location']?.toString() ?? '',
        practice: m['practice']?.toString() ?? '',
        deletedAt: (m['deleted_at'] as num?)?.toInt() ?? 0,
        bookDeletedAt: (m['book_deleted_at'] as num?)?.toInt() ?? 0,
        createdAt: (m['created_at'] as num?)?.toInt() ?? 0,
        updatedAt: (m['updated_at'] as num?)?.toInt() ?? 0,
      );

  PrivateStudyNote _noteFromCloud(String id, Map<String, dynamic> m) =>
      PrivateStudyNote(
        id: id,
        bookId: m['book_id']?.toString() ?? '',
        quote: m['quote']?.toString() ?? '',
        topics: _strings(m['topics']),
        reflection: m['reflection']?.toString() ?? '',
        scriptureRefs: _strings(m['scripture_refs']),
        sourceLocation: m['source_location']?.toString() ?? '',
        practice: m['practice']?.toString() ?? '',
        deletedAt: (m['deleted_at'] as num?)?.toInt() ?? 0,
        bookDeletedAt: (m['book_deleted_at'] as num?)?.toInt() ?? 0,
        createdAt: (m['created_at'] as num?)?.toInt() ?? 0,
        updatedAt: (m['updated_at'] as num?)?.toInt() ?? 0,
      );

  Map<String, Object?> _bookLocal(PrivateStudyBook b) => {
        'id': b.id,
        'title': b.title,
        'author': b.author,
        'deleted_at': b.deletedAt,
        'created_at': b.createdAt,
        'updated_at': b.updatedAt,
        'last_studied_at': b.lastStudiedAt,
      };

  Map<String, Object?> _noteLocal(PrivateStudyNote n) => {
        'id': n.id,
        'book_id': n.bookId,
        'quote': n.quote,
        'topics': jsonEncode(n.topics),
        'reflection': n.reflection,
        'scripture_refs': jsonEncode(n.scriptureRefs),
        'source_location': n.sourceLocation,
        'practice': n.practice,
        'deleted_at': n.deletedAt,
        'book_deleted_at': n.bookDeletedAt,
        'created_at': n.createdAt,
        'updated_at': n.updatedAt,
      };

  Future<String?> _getMeta(String key) async {
    final sql = await db.database;
    final rows = await sql.query(_metaTable,
        columns: ['value'], where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value']?.toString();
  }

  Future<void> _setMeta(String key, String value) async {
    final sql = await db.database;
    await sql.insert(_metaTable, {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<PrivateStudyBook>> getBooks({bool includeDeleted = false}) async {
    await _ready();
    await syncCurrentUser();
    final sql = await db.database;
    final rows = await sql.query(_bookTable,
        where: includeDeleted ? null : 'deleted_at = 0',
        orderBy: includeDeleted
            ? 'deleted_at DESC, updated_at DESC'
            : 'last_studied_at DESC, updated_at DESC');
    return rows.map(_bookFromLocal).toList();
  }

  Future<PrivateStudyBook?> getBook(String id) async {
    await _ready();
    final sql = await db.database;
    final rows = await sql.query(_bookTable, where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _bookFromLocal(rows.first);
  }

  Future<void> saveBook(PrivateStudyBook book) async {
    await _ready();
    final sql = await db.database;
    await sql.insert(_bookTable, _bookLocal(book),
        conflictAlgorithm: ConflictAlgorithm.replace);
    await _clearTombstone(_bookKind, book.id);
    db.onMutate?.call();
    await _tryPushBook(book);
  }

  Future<void> touchBook(String id) async {
    await _ready();
    final now = DateTime.now().millisecondsSinceEpoch;
    final sql = await db.database;
    await sql.update(_bookTable,
        {'last_studied_at': now, 'updated_at': now},
        where: 'id = ? AND deleted_at = 0', whereArgs: [id]);
    db.onMutate?.call();
  }

  Future<List<PrivateStudyNote>> getNotes({
    String? bookId,
    String? topic,
    bool includeDeleted = false,
  }) async {
    await _ready();
    await syncCurrentUser();
    final sql = await db.database;
    final clauses = <String>[];
    final args = <Object?>[];
    if (!includeDeleted) clauses.add('deleted_at = 0');
    if (bookId != null) {
      clauses.add('book_id = ?');
      args.add(bookId);
    }
    final rows = await sql.query(_noteTable,
        where: clauses.isEmpty ? null : clauses.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: includeDeleted
            ? 'deleted_at DESC, updated_at DESC'
            : 'updated_at DESC');
    var notes = rows.map(_noteFromLocal).toList();
    if (topic != null) {
      notes = topic == '未分類'
          ? notes.where((n) => n.topics.isEmpty).toList()
          : notes.where((n) => n.topics.contains(topic)).toList();
    }
    return notes;
  }

  Future<PrivateStudyNote?> getNote(String id) async {
    await _ready();
    final sql = await db.database;
    final rows = await sql.query(_noteTable, where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _noteFromLocal(rows.first);
  }

  /// 回 true 代表這次已同步到 cloud；false 代表已安全存在本機、等待之後同步。
  Future<bool> saveNote(PrivateStudyNote note) async {
    await _ready();
    final sql = await db.database;
    await sql.insert(_noteTable, _noteLocal(note),
        conflictAlgorithm: ConflictAlgorithm.replace);
    await _clearTombstone(_noteKind, note.id);
    final now = DateTime.now().millisecondsSinceEpoch;
    await sql.update(_bookTable,
        {'last_studied_at': now, 'updated_at': now},
        where: 'id = ? AND deleted_at = 0', whereArgs: [note.bookId]);
    db.onMutate?.call();
    return _tryPushNote(note);
  }

  Future<void> softDeleteNote(String id) async {
    await _ready();
    final now = DateTime.now().millisecondsSinceEpoch;
    final sql = await db.database;
    await sql.update(_noteTable, {'deleted_at': now, 'updated_at': now},
        where: 'id = ?', whereArgs: [id]);
    db.onMutate?.call();
    final n = await getNote(id);
    if (n != null) await _tryPushNote(n);
  }

  Future<void> restoreNote(String id) async {
    await _ready();
    final now = DateTime.now().millisecondsSinceEpoch;
    final sql = await db.database;
    await sql.update(_noteTable, {'deleted_at': 0, 'updated_at': now},
        where: 'id = ?', whereArgs: [id]);
    db.onMutate?.call();
    final n = await getNote(id);
    if (n != null) await _tryPushNote(n);
  }

  Future<void> softDeleteBook(String id) async {
    await _ready();
    final now = DateTime.now().millisecondsSinceEpoch;
    final sql = await db.database;
    await sql.transaction((txn) async {
      await txn.update(_bookTable, {'deleted_at': now, 'updated_at': now},
          where: 'id = ?', whereArgs: [id]);
      // **只級聯刪除目前仍 live 的 notes**，並以 book_deleted_at=now 標記「屬於這次級聯」。
      // 已被個別刪除的 notes（deleted_at>0）保持原狀、book_deleted_at 維持 0 → Book restore 不復活。
      await txn.update(
          _noteTable,
          {'deleted_at': now, 'book_deleted_at': now, 'updated_at': now},
          where: 'book_id = ? AND deleted_at = 0', whereArgs: [id]);
    });
    db.onMutate?.call();
    await syncCurrentUser();
  }

  Future<void> restoreBook(String id) async {
    await _ready();
    final now = DateTime.now().millisecondsSinceEpoch;
    final sql = await db.database;
    // 讀取還原前的 Book.deletedAt，作為「這次級聯批次」的識別鍵。
    final bookRows = await sql
        .query(_bookTable, columns: ['deleted_at'], where: 'id = ?', whereArgs: [id]);
    final bookDeletedAt =
        bookRows.isEmpty ? 0 : ((bookRows.first['deleted_at'] as num?)?.toInt() ?? 0);
    await sql.transaction((txn) async {
      await txn.update(_bookTable,
          {'deleted_at': 0, 'updated_at': now, 'last_studied_at': now},
          where: 'id = ?', whereArgs: [id]);
      // **只復活隨這次 Book 級聯刪除的 notes**（book_deleted_at == 還原前 Book.deletedAt）。
      // 個別刪除者（book_deleted_at==0 或其它批次）維持刪除。
      if (bookDeletedAt > 0) {
        await txn.update(
            _noteTable,
            {'deleted_at': 0, 'book_deleted_at': 0, 'updated_at': now},
            where: 'book_id = ? AND book_deleted_at = ?',
            whereArgs: [id, bookDeletedAt]);
      }
    });
    db.onMutate?.call();
    await syncCurrentUser();
  }

  Future<void> purgeNote(String id) async {
    await _ready();
    final sql = await db.database;
    await sql.delete(_noteTable, where: 'id = ?', whereArgs: [id]);
    await _writeTombstone(_noteKind, id);
    db.onMutate?.call();
    await syncCurrentUser();
  }

  Future<void> purgeBook(String id) async {
    await _ready();
    final sql = await db.database;
    final notes = await sql.query(_noteTable,
        columns: ['id'], where: 'book_id = ?', whereArgs: [id]);
    await sql.transaction((txn) async {
      await txn.delete(_noteTable, where: 'book_id = ?', whereArgs: [id]);
      await txn.delete(_bookTable, where: 'id = ?', whereArgs: [id]);
    });
    for (final row in notes) {
      await _writeTombstone(_noteKind, row['id'].toString());
    }
    await _writeTombstone(_bookKind, id);
    db.onMutate?.call();
    await syncCurrentUser();
  }

  Future<List<PrivateStudyNote>> search({
    String query = '',
    String? bookId,
    String? topic,
    bool? hasScripture,
  }) async {
    final books = {for (final b in await getBooks()) b.id: b};
    final notes = await getNotes(bookId: bookId, topic: topic);
    final q = query.trim().toLowerCase();
    return notes.where((n) {
      if (hasScripture != null && n.scriptureRefs.isNotEmpty != hasScripture) {
        return false;
      }
      if (q.isEmpty) return true;
      final b = books[n.bookId];
      final hay = [
        n.quote,
        n.reflection,
        n.practice,
        n.sourceLocation,
        b?.title ?? '',
        b?.author ?? '',
      ].join('\n').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  Future<void> _purgeExpired() async {
    final sql = await db.database;
    final cutoff = DateTime.now().millisecondsSinceEpoch - _retentionMs;
    final oldBooks = await sql.query(_bookTable,
        columns: ['id'], where: 'deleted_at > 0 AND deleted_at < ?', whereArgs: [cutoff]);
    for (final row in oldBooks) {
      await purgeBook(row['id'].toString());
    }
    final oldNotes = await sql.query(_noteTable,
        columns: ['id'], where: 'deleted_at > 0 AND deleted_at < ?', whereArgs: [cutoff]);
    for (final row in oldNotes) {
      await purgeNote(row['id'].toString());
    }
  }

  Future<void> _writeTombstone(String kind, String ref) async {
    final sql = await db.database;
    await sql.insert(
        'tombstones',
        {
          'kind': kind,
          'ref': ref,
          'deleted_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _clearTombstone(String kind, String ref) async {
    final sql = await db.database;
    await sql.delete('tombstones',
        where: 'kind = ? AND ref = ?', whereArgs: [kind, ref]);
  }

  Future<String?> _uid() async {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  CollectionReference<Map<String, dynamic>> _col(
          String uid, String collection) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection(collection);

  Future<bool> _tryPushBook(PrivateStudyBook book) async {
    final uid = await _uid();
    if (uid == null) return false;
    try {
      await _col(uid, 'private_study_books').doc(book.id).set(book.toCloudMap());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _tryPushNote(PrivateStudyNote note) async {
    final uid = await _uid();
    if (uid == null) return false;
    try {
      await _col(uid, 'private_study_notes').doc(note.id).set(note.toCloudMap());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 目前本機 private-study 那筆 ref 的 tombstone deleted_at（無則 null）。
  Future<int?> _localTombstone(dynamic sql, String kind, String ref) async {
    final rows = await sql.query('tombstones',
        columns: ['deleted_at'],
        where: 'kind = ? AND ref = ?',
        whereArgs: [kind, ref]);
    return rows.isEmpty ? null : ((rows.first['deleted_at'] as num?)?.toInt() ?? 0);
  }

  /// 換帳號時清掉本機 private-study 資料（上一使用者資料已安全存在其 cloud）。
  /// 只清 private-study 相關 rows，不動其他表；§八I 防跨帳號上傳。
  Future<void> _clearLocalData(dynamic sql) async {
    await sql.delete(_noteTable);
    await sql.delete(_bookTable);
    await sql.delete('tombstones',
        where: 'kind IN (?, ?)', whereArgs: [_bookKind, _noteKind]);
  }

  /// Opportunistic LWW sync。Guest / Firebase unavailable 時安全 no-op。
  /// 重入守衛（§八G/§八J）：同時多次呼叫只跑一次，重複 reconnect idempotent。
  Future<void> syncCurrentUser() async {
    await _ready();
    final uid = await _uid();
    if (uid == null) return; // guest：資料留本機、不上傳
    if (_syncing) return;
    _syncing = true;
    try {
      final sql = await db.database;

      // §八I 帳號歸屬守衛：換帳號不得把上一使用者本機資料上傳到目前帳號。
      final action = ownerAction(await _getMeta('owner_uid'), uid);
      if (action == 'switch') {
        await _clearLocalData(sql);
      }
      await _setMeta('owner_uid', uid);

      final bookCol = _col(uid, 'private_study_books');
      final noteCol = _col(uid, 'private_study_notes');
      final tombCol = _col(uid, 'tombstones');

      // 1) 下載 cloud tombstones：套用刪除（deletedAt>=local.updatedAt 才刪）＋落地 marker。
      final cloudTombs = await tombCol.get();
      for (final d in cloudTombs.docs) {
        final m = d.data();
        final kind = m['kind']?.toString();
        if (kind != _bookKind && kind != _noteKind) continue;
        final ref = m['ref']?.toString() ?? '';
        final deletedAt = (m['deleted_at'] as num?)?.toInt() ?? 0;
        if (kind == _bookKind) {
          final local = await getBook(ref);
          if (local != null && deletedAt >= local.updatedAt) {
            await sql.delete(_noteTable, where: 'book_id = ?', whereArgs: [ref]);
            await sql.delete(_bookTable, where: 'id = ?', whereArgs: [ref]);
          }
        } else {
          final local = await getNote(ref);
          if (local != null && deletedAt >= local.updatedAt) {
            await sql.delete(_noteTable, where: 'id = ?', whereArgs: [ref]);
          }
        }
        // 落地 marker，但**保留較新的本機 marker**（避免舊 cloud tomb 壓過新的）。
        final localTomb = await _localTombstone(sql, kind!, ref);
        if (localTomb == null || deletedAt > localTomb) {
          await sql.insert('tombstones',
              {'kind': kind, 'ref': ref, 'deleted_at': deletedAt},
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      // 2) 下載 books（**防復活**：較新/同時的 tombstone 擋下；較舊 tombstone 則被合法 restore 清掉）。
      final cloudBooks = await bookCol.get();
      for (final d in cloudBooks.docs) {
        final remote = PrivateStudyBook.fromMap({'id': d.id, ...d.data()});
        final tomb = await _localTombstone(sql, _bookKind, d.id);
        if (tomb != null && tombstoneBlocksResurrection(tomb, remote.updatedAt)) {
          continue; // 永久刪除較新 → 不復活
        }
        if (tomb != null) await _clearTombstone(_bookKind, d.id); // 合法較新 → 清舊 marker，止 flip-flop
        final local = await getBook(d.id);
        if (local == null || remote.updatedAt > local.updatedAt) {
          await sql.insert(_bookTable, _bookLocal(remote),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      // 3) 下載 notes（同樣防復活 + 止 flip-flop）。
      final cloudNotes = await noteCol.get();
      for (final d in cloudNotes.docs) {
        final remote = _noteFromCloud(d.id, d.data());
        final tomb = await _localTombstone(sql, _noteKind, d.id);
        if (tomb != null && tombstoneBlocksResurrection(tomb, remote.updatedAt)) {
          continue;
        }
        if (tomb != null) await _clearTombstone(_noteKind, d.id);
        final local = await getNote(d.id);
        if (local == null || remote.updatedAt > local.updatedAt) {
          await sql.insert(_noteTable, _noteLocal(remote),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      // 4) 上傳本機（含 soft-deleted：deleted_at 隨 doc 同步，靠 updatedAt LWW）。
      final localBooks = await sql.query(_bookTable);
      for (final row in localBooks) {
        await bookCol.doc(_bookFromLocal(row).id).set(_bookFromLocal(row).toCloudMap());
      }
      final localNotes = await sql.query(_noteTable);
      for (final row in localNotes) {
        await noteCol.doc(_noteFromLocal(row).id).set(_noteFromLocal(row).toCloudMap());
      }

      // 5) 上傳永久刪除 tombstones，並刪對應 cloud doc（永久刪除防復活的必要 marker，§八D/E）。
      final tombs = await sql.query('tombstones',
          where: 'kind IN (?, ?)', whereArgs: [_bookKind, _noteKind]);
      for (final t in tombs) {
        final kind = t['kind'].toString();
        final ref = t['ref'].toString();
        final deletedAt = (t['deleted_at'] as num?)?.toInt() ?? 0;
        await tombCol.doc('${kind}_$ref').set(
            {'kind': kind, 'ref': ref, 'deleted_at': deletedAt});
        if (kind == _bookKind) {
          await bookCol.doc(ref).delete();
        } else {
          await noteCol.doc(ref).delete();
        }
      }
    } catch (_) {
      // Local-first：雲端不可用時不影響本地讀寫；下次進入/操作再同步。
    } finally {
      _syncing = false;
    }
  }
}
