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
  static const _bookKind = 'private_study_book';
  static const _noteKind = 'private_study_note';
  static const _retentionMs = 30 * 24 * 60 * 60 * 1000;

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
    _initialized = true;
    await _purgeExpired();
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
        'created_at': n.createdAt,
        'updated_at': n.updatedAt,
      };

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
      await txn.update(_noteTable, {'deleted_at': now, 'updated_at': now},
          where: 'book_id = ?', whereArgs: [id]);
    });
    db.onMutate?.call();
    await syncCurrentUser();
  }

  Future<void> restoreBook(String id) async {
    await _ready();
    final now = DateTime.now().millisecondsSinceEpoch;
    final sql = await db.database;
    await sql.transaction((txn) async {
      await txn.update(_bookTable,
          {'deleted_at': 0, 'updated_at': now, 'last_studied_at': now},
          where: 'id = ?', whereArgs: [id]);
      await txn.update(_noteTable, {'deleted_at': 0, 'updated_at': now},
          where: 'book_id = ?', whereArgs: [id]);
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

  /// Opportunistic LWW sync。Guest / Firebase unavailable 時安全 no-op。
  Future<void> syncCurrentUser() async {
    await _ready();
    final uid = await _uid();
    if (uid == null) return;
    try {
      final sql = await db.database;
      final bookCol = _col(uid, 'private_study_books');
      final noteCol = _col(uid, 'private_study_notes');
      final tombCol = _col(uid, 'tombstones');

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
        await sql.insert('tombstones',
            {'kind': kind, 'ref': ref, 'deleted_at': deletedAt},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }

      final cloudBooks = await bookCol.get();
      for (final d in cloudBooks.docs) {
        final remote = PrivateStudyBook.fromMap({'id': d.id, ...d.data()});
        final local = await getBook(d.id);
        if (local == null || remote.updatedAt > local.updatedAt) {
          await sql.insert(_bookTable, _bookLocal(remote),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      final cloudNotes = await noteCol.get();
      for (final d in cloudNotes.docs) {
        final remote = _noteFromCloud(d.id, d.data());
        final local = await getNote(d.id);
        if (local == null || remote.updatedAt > local.updatedAt) {
          await sql.insert(_noteTable, _noteLocal(remote),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      final localBooks = await sql.query(_bookTable);
      for (final row in localBooks) {
        final b = _bookFromLocal(row);
        await bookCol.doc(b.id).set(b.toCloudMap());
      }
      final localNotes = await sql.query(_noteTable);
      for (final row in localNotes) {
        final n = _noteFromLocal(row);
        await noteCol.doc(n.id).set(n.toCloudMap());
      }

      final tombs = await sql.query('tombstones',
          where: 'kind IN (?, ?)', whereArgs: [_bookKind, _noteKind]);
      for (final t in tombs) {
        final kind = t['kind'].toString();
        final ref = t['ref'].toString();
        final deletedAt = (t['deleted_at'] as num?)?.toInt() ?? 0;
        await tombCol.doc('${kind}_$ref').set({
          'kind': kind,
          'ref': ref,
          'deleted_at': deletedAt,
        });
        if (kind == _bookKind) {
          await bookCol.doc(ref).delete();
        } else {
          await noteCol.doc(ref).delete();
        }
      }
    } catch (_) {
      // Local-first：雲端不可用時不影響本地讀寫；下次進入/操作再同步。
    }
  }
}
