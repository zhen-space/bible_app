import 'package:sqflite/sqflite.dart'
    show Database, ConflictAlgorithm, OpenDatabaseOptions;

import '../models/models.dart';
import 'db_factory_native.dart' if (dart.library.js_interop) 'db_factory_web.dart';

/// SQLite 資料庫服務，只存使用者資料（經文本身在 asset，不進 DB）。
///
/// 升版規則（重要，兩邊都要寫）：
/// 1. `_dbVersion` +1
/// 2. `_onUpgrade` 加一個 `if (oldV < n)` 區塊執行 migration
/// 3. `_createAllTables` 同步加上新表/新欄位的建表語句（給全新安裝用）
class DatabaseService {
  static const _dbName = 'bible_app.db';
  static const _dbVersion = 7;

  /// 資料異動通知（自動備份用）：每次寫入後呼叫。
  /// providers 端掛上 debounce 的雲端同步（登入時筆記即時上傳，換手機不丟）。
  void Function()? onMutate;

  void _mutated() => onMutate?.call();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    // dbFactory 依平台切換：手機用原生 sqflite，網頁用 WASM + IndexedDB
    return dbFactory.openDatabase(
      await resolveDbPath(_dbName),
      options: OpenDatabaseOptions(
        version: _dbVersion,
        onCreate: (db, version) async => _createAllTables(db),
        onUpgrade: _onUpgrade,
      ),
    );
  }

  Future<void> _createAllTables(Database db) async {
    await db.execute('''
      CREATE TABLE bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        chapter INTEGER NOT NULL,
        verse INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        UNIQUE(book_id, chapter, verse)
      )
    ''');
    await db.execute('''
      CREATE TABLE highlights (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        chapter INTEGER NOT NULL,
        verse INTEGER NOT NULL,
        color INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        UNIQUE(book_id, chapter, verse)
      )
    ''');
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        chapter INTEGER NOT NULL,
        verse INTEGER NOT NULL,
        content TEXT NOT NULL,
        tags TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_notes_ref ON notes(book_id, chapter, verse)');
    await _createReadingLogTable(db); // v2
    await _createSermonNotesTable(db); // v4
    await _createPlanProgressTable(db); // v5
    await _createTombstonesTable(db); // v6
    await _createPrayersTable(db); // v7
  }

  /// 禱告事項（首頁區塊）：分類/子分類/內容，使用者自行增刪，不設打勾。
  Future<void> _createPrayersTable(Database db) async {
    await db.execute('''
      CREATE TABLE prayers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL DEFAULT '',
        subcategory TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _createReadingLogTable(Database db) async {
    await db.execute('''
      CREATE TABLE reading_log (
        book_id INTEGER NOT NULL,
        chapter INTEGER NOT NULL,
        read_at INTEGER NOT NULL,
        PRIMARY KEY(book_id, chapter)
      )
    ''');
  }

  Future<void> _createSermonNotesTable(Database db) async {
    await db.execute('''
      CREATE TABLE sermon_notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date INTEGER NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        scripture TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        trinity_who TEXT NOT NULL DEFAULT '',
        trinity_word TEXT NOT NULL DEFAULT '',
        practice TEXT NOT NULL DEFAULT '',
        reflection TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _createPlanProgressTable(Database db) async {
    await db.execute('''
      CREATE TABLE plan_progress (
        plan_id TEXT NOT NULL,
        day INTEGER NOT NULL,
        done_at INTEGER NOT NULL,
        PRIMARY KEY(plan_id, day)
      )
    ''');
  }

  /// 刪除墓碑（同步刪除用）：記錄「某筆資料已於某時刪除」。
  /// 不變量：同一個 (kind, ref) 不會同時是活資料又有墓碑——
  /// 刪除時寫墓碑、新增/更新時清墓碑（見各 CRUD 方法）。
  Future<void> _createTombstonesTable(Database db) async {
    await db.execute('''
      CREATE TABLE tombstones (
        kind TEXT NOT NULL,
        ref TEXT NOT NULL,
        deleted_at INTEGER NOT NULL,
        PRIMARY KEY(kind, ref)
      )
    ''');
  }

  /// 節位資料的雲端 doc id（與 sync_service 一致）。
  String _rowRef(int bookId, int chapter, int verse) =>
      'b${bookId}_c${chapter}_v$verse';

  Future<void> _tombstone(Database db, String kind, String ref) async {
    await db.insert(
      'tombstones',
      {
        'kind': kind,
        'ref': ref,
        'deleted_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _untomb(Database db, String kind, String ref) async {
    await db.delete('tombstones',
        where: 'kind = ? AND ref = ?', whereArgs: [kind, ref]);
  }

  Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    if (oldV < 2) {
      await _createReadingLogTable(db);
    }
    if (oldV < 3) {
      // v3：筆記加標籤欄
      await db.execute(
          "ALTER TABLE notes ADD COLUMN tags TEXT NOT NULL DEFAULT ''");
    }
    if (oldV < 4) {
      await _createSermonNotesTable(db);
    }
    if (oldV < 5) {
      await _createPlanProgressTable(db);
    }
    if (oldV < 6) {
      await _createTombstonesTable(db);
    }
    if (oldV < 7) {
      await _createPrayersTable(db);
    }
  }

  // ---- Bookmarks ----

  Future<void> toggleBookmark(int bookId, int chapter, int verse) async {
    final db = await database;
    final ref = _rowRef(bookId, chapter, verse);
    final deleted = await db.delete(
      'bookmarks',
      where: 'book_id = ? AND chapter = ? AND verse = ?',
      whereArgs: [bookId, chapter, verse],
    );
    if (deleted == 0) {
      await db.insert('bookmarks', {
        'book_id': bookId,
        'chapter': chapter,
        'verse': verse,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await _untomb(db, 'bookmark', ref); // 重新加入：清掉舊墓碑
    } else {
      await _tombstone(db, 'bookmark', ref); // 刪除：記墓碑
    }
    _mutated();
  }

  Future<List<Bookmark>> getAllBookmarks() async {
    final db = await database;
    final rows = await db.query('bookmarks', orderBy: 'created_at DESC');
    return rows.map(Bookmark.fromMap).toList();
  }

  Future<Set<int>> getBookmarkedVerses(int bookId, int chapter) async {
    final db = await database;
    final rows = await db.query(
      'bookmarks',
      columns: ['verse'],
      where: 'book_id = ? AND chapter = ?',
      whereArgs: [bookId, chapter],
    );
    return rows.map((r) => r['verse'] as int).toSet();
  }

  // ---- Highlights ----

  /// 設定螢光筆顏色；color 為 null 表示移除。
  Future<void> setHighlight(
      int bookId, int chapter, int verse, HighlightColor? color) async {
    final db = await database;
    final ref = _rowRef(bookId, chapter, verse);
    if (color == null) {
      await db.delete(
        'highlights',
        where: 'book_id = ? AND chapter = ? AND verse = ?',
        whereArgs: [bookId, chapter, verse],
      );
      await _tombstone(db, 'highlight', ref);
    } else {
      await db.insert(
        'highlights',
        {
          'book_id': bookId,
          'chapter': chapter,
          'verse': verse,
          'color': color.index,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _untomb(db, 'highlight', ref);
    }
    _mutated();
  }

  Future<List<Highlight>> getAllHighlights() async {
    final db = await database;
    final rows = await db.query('highlights', orderBy: 'created_at DESC');
    return rows.map(Highlight.fromMap).toList();
  }

  Future<Map<int, HighlightColor>> getChapterHighlights(
      int bookId, int chapter) async {
    final db = await database;
    final rows = await db.query(
      'highlights',
      where: 'book_id = ? AND chapter = ?',
      whereArgs: [bookId, chapter],
    );
    return {
      for (final r in rows)
        r['verse'] as int: HighlightColor.values[r['color'] as int],
    };
  }

  // ---- Notes ----

  Future<void> saveNote(int bookId, int chapter, int verse, String content,
      {String tags = ''}) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await db.query(
      'notes',
      where: 'book_id = ? AND chapter = ? AND verse = ?',
      whereArgs: [bookId, chapter, verse],
    );
    if (existing.isEmpty) {
      await db.insert('notes', {
        'book_id': bookId,
        'chapter': chapter,
        'verse': verse,
        'content': content,
        'tags': tags,
        'created_at': now,
        'updated_at': now,
      });
    } else {
      await db.update(
        'notes',
        {'content': content, 'tags': tags, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
    await _untomb(db, 'note', _rowRef(bookId, chapter, verse));
    _mutated();
  }

  Future<void> deleteNote(int bookId, int chapter, int verse) async {
    final db = await database;
    await db.delete(
      'notes',
      where: 'book_id = ? AND chapter = ? AND verse = ?',
      whereArgs: [bookId, chapter, verse],
    );
    await _tombstone(db, 'note', _rowRef(bookId, chapter, verse));
    _mutated();
  }

  Future<List<Note>> getAllNotes() async {
    final db = await database;
    final rows = await db.query('notes', orderBy: 'updated_at DESC');
    return rows.map(Note.fromMap).toList();
  }

  Future<Map<int, Note>> getChapterNotes(int bookId, int chapter) async {
    final db = await database;
    final rows = await db.query(
      'notes',
      where: 'book_id = ? AND chapter = ?',
      whereArgs: [bookId, chapter],
    );
    return {for (final r in rows) r['verse'] as int: Note.fromMap(r)};
  }

  // ---- Reading log（讀經紀錄）----

  Future<void> markChapterRead(int bookId, int chapter) async {
    final db = await database;
    await db.insert(
      'reading_log',
      {
        'book_id': bookId,
        'chapter': chapter,
        'read_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _mutated();
  }

  /// 已讀章數。
  Future<int> getReadChapterCount() async {
    final db = await database;
    final rows =
        await db.rawQuery('SELECT COUNT(*) AS c FROM reading_log');
    return rows.first['c'] as int;
  }

  Future<List<Map<String, dynamic>>> getReadingLog() async {
    final db = await database;
    return db.query('reading_log');
  }

  /// 每卷已讀章數（bookId → 已讀章數），信仰地圖用。
  Future<Map<int, int>> getReadCountsByBook() async {
    final db = await database;
    final rows = await db.rawQuery(
        'SELECT book_id, COUNT(*) AS c FROM reading_log GROUP BY book_id');
    return {for (final r in rows) r['book_id'] as int: r['c'] as int};
  }

  /// 每卷有筆記/書籤/螢光筆的節數合計（信仰地圖「有標記」用）。
  Future<Map<int, int>> getMarkCountsByBook() async {
    final db = await database;
    final out = <int, int>{};
    for (final t in ['bookmarks', 'highlights', 'notes']) {
      final rows = await db.rawQuery(
          'SELECT book_id, COUNT(*) AS c FROM $t GROUP BY book_id');
      for (final r in rows) {
        final id = r['book_id'] as int;
        out[id] = (out[id] ?? 0) + (r['c'] as int);
      }
    }
    return out;
  }

  // ---- 雲端同步用 upsert（last-write-wins 合併）----

  /// 書籤：已存在就略過（書籤沒有內容可比新舊）。
  Future<void> upsertBookmark(
      int bookId, int chapter, int verse, int createdAt) async {
    final db = await database;
    await db.insert(
      'bookmarks',
      {
        'book_id': bookId,
        'chapter': chapter,
        'verse': verse,
        'created_at': createdAt,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// 螢光筆：以 created_at 較新者為準。
  Future<void> upsertHighlight(int bookId, int chapter, int verse,
      int colorIndex, int createdAt) async {
    final db = await database;
    final existing = await db.query(
      'highlights',
      where: 'book_id = ? AND chapter = ? AND verse = ?',
      whereArgs: [bookId, chapter, verse],
    );
    if (existing.isNotEmpty &&
        (existing.first['created_at'] as int) >= createdAt) {
      return;
    }
    await db.insert(
      'highlights',
      {
        'book_id': bookId,
        'chapter': chapter,
        'verse': verse,
        'color': colorIndex,
        'created_at': createdAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 筆記：以 updated_at 較新者為準。
  Future<void> upsertNote(int bookId, int chapter, int verse, String content,
      int createdAt, int updatedAt,
      {String tags = ''}) async {
    final db = await database;
    final existing = await db.query(
      'notes',
      where: 'book_id = ? AND chapter = ? AND verse = ?',
      whereArgs: [bookId, chapter, verse],
    );
    if (existing.isEmpty) {
      await db.insert('notes', {
        'book_id': bookId,
        'chapter': chapter,
        'verse': verse,
        'content': content,
        'tags': tags,
        'created_at': createdAt,
        'updated_at': updatedAt,
      });
    } else if ((existing.first['updated_at'] as int) < updatedAt) {
      await db.update(
        'notes',
        {'content': content, 'tags': tags, 'updated_at': updatedAt},
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
  }

  // ---- 主日／證道筆記 ----

  Future<List<SermonNote>> getSermonNotes() async {
    final db = await database;
    final rows = await db.query('sermon_notes', orderBy: 'date DESC');
    return rows.map(SermonNote.fromMap).toList();
  }

  /// 新增或更新（id 為 null 則新增），回傳 id。
  Future<int> saveSermonNote(SermonNote note) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (note.id == null) {
      final m = note.toMap()
        ..['created_at'] = now
        ..['updated_at'] = now;
      final id = await db.insert('sermon_notes', m);
      await _untomb(db, 'sermon', 's$now');
      _mutated();
      return id;
    }
    await db.update(
      'sermon_notes',
      note.toMap()..['updated_at'] = now,
      where: 'id = ?',
      whereArgs: [note.id],
    );
    await _untomb(db, 'sermon', 's${note.createdAt}');
    _mutated();
    return note.id!;
  }

  Future<void> deleteSermonNote(int id) async {
    final db = await database;
    // 先取 created_at（雲端 doc id = s{createdAt}）再刪，才能記正確墓碑
    final rows = await db.query('sermon_notes',
        columns: ['created_at'], where: 'id = ?', whereArgs: [id]);
    await db.delete('sermon_notes', where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      await _tombstone(db, 'sermon', 's${rows.first['created_at']}');
    }
    _mutated();
  }

  /// 統計小卡用：各項數量。
  Future<Map<String, int>> getStats() async {
    final db = await database;
    Future<int> count(String t) async {
      final r = await db.rawQuery('SELECT COUNT(*) AS c FROM $t');
      return r.first['c'] as int;
    }
    return {
      'read': await count('reading_log'),
      'bookmarks': await count('bookmarks'),
      'highlights': await count('highlights'),
      'notes': await count('notes'),
      'sermons': await count('sermon_notes'),
    };
  }

  // ---- 讀經計畫進度 ----

  /// 該計畫已完成的天數集合（day 從 1 起算）。
  Future<Set<int>> getPlanProgress(String planId) async {
    final db = await database;
    final rows = await db.query(
      'plan_progress',
      columns: ['day'],
      where: 'plan_id = ?',
      whereArgs: [planId],
    );
    return rows.map((r) => r['day'] as int).toSet();
  }

  /// 全部進度列（雲端同步用）。
  Future<List<Map<String, dynamic>>> getAllPlanProgress() async {
    final db = await database;
    return db.query('plan_progress');
  }

  /// 進度合併（保留較新的 done_at）。
  Future<void> upsertPlanProgress(
      String planId, int day, int doneAt) async {
    final db = await database;
    final existing = await db.query(
      'plan_progress',
      where: 'plan_id = ? AND day = ?',
      whereArgs: [planId, day],
    );
    if (existing.isNotEmpty &&
        (existing.first['done_at'] as int) >= doneAt) {
      return;
    }
    await db.insert(
      'plan_progress',
      {'plan_id': planId, 'day': day, 'done_at': doneAt},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 各計畫已完成天數（planId → 已完成天數），計畫列表用。
  Future<Map<String, int>> getPlanDoneCounts() async {
    final db = await database;
    final rows = await db.rawQuery(
        'SELECT plan_id, COUNT(*) AS c FROM plan_progress GROUP BY plan_id');
    return {for (final r in rows) r['plan_id'] as String: r['c'] as int};
  }

  /// 勾選/取消某一天。
  Future<void> setPlanDayDone(String planId, int day, bool done) async {
    final db = await database;
    if (done) {
      await db.insert(
        'plan_progress',
        {
          'plan_id': planId,
          'day': day,
          'done_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await db.delete(
        'plan_progress',
        where: 'plan_id = ? AND day = ?',
        whereArgs: [planId, day],
      );
    }
    _mutated();
  }

  // ---- 禱告事項 ----

  Future<List<Prayer>> getPrayers() async {
    final db = await database;
    final rows = await db.query('prayers',
        orderBy: 'category, subcategory, created_at DESC');
    return rows.map(Prayer.fromMap).toList();
  }

  /// 新增或更新（id 為 null 則新增），回傳 id。
  Future<int> savePrayer(Prayer p) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (p.id == null) {
      final m = p.toMap()
        ..['created_at'] = now
        ..['updated_at'] = now;
      final id = await db.insert('prayers', m);
      await _untomb(db, 'prayer', 'p$now');
      _mutated();
      return id;
    }
    await db.update(
      'prayers',
      p.toMap()..['updated_at'] = now,
      where: 'id = ?',
      whereArgs: [p.id],
    );
    await _untomb(db, 'prayer', 'p${p.createdAt}');
    _mutated();
    return p.id!;
  }

  Future<void> deletePrayer(int id) async {
    final db = await database;
    final rows = await db.query('prayers',
        columns: ['created_at'], where: 'id = ?', whereArgs: [id]);
    await db.delete('prayers', where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      await _tombstone(db, 'prayer', 'p${rows.first['created_at']}');
    }
    _mutated();
  }

  // ---- 刪除墓碑（同步刪除）----

  Future<List<Map<String, dynamic>>> getAllTombstones() async {
    final db = await database;
    return db.query('tombstones');
  }

  /// 某 kind 的 ref → deleted_at 對照（sync 下載時用來擋掉被刪的資料）。
  Future<Map<String, int>> getTombstoneMap(String kind) async {
    final db = await database;
    final rows = await db.query('tombstones',
        columns: ['ref', 'deleted_at'],
        where: 'kind = ?',
        whereArgs: [kind]);
    return {for (final r in rows) r['ref'] as String: r['deleted_at'] as int};
  }

  /// 合併雲端墓碑（保留較新的 deleted_at）。
  Future<void> upsertTombstone(String kind, String ref, int deletedAt) async {
    final db = await database;
    final existing = await db.query('tombstones',
        where: 'kind = ? AND ref = ?', whereArgs: [kind, ref]);
    if (existing.isNotEmpty &&
        (existing.first['deleted_at'] as int) >= deletedAt) {
      return;
    }
    await db.insert(
      'tombstones',
      {'kind': kind, 'ref': ref, 'deleted_at': deletedAt},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 套用墓碑：刪掉本地「時間 <= 刪除時間」的對應資料（同步下載後呼叫）。
  /// 回傳刪除筆數。
  Future<int> applyTombstone(String kind, String ref, int deletedAt) async {
    final db = await database;
    final parts = RegExp(r'^b(\d+)_c(\d+)_v(\d+)$').firstMatch(ref);
    var removed = 0;
    switch (kind) {
      case 'bookmark':
      case 'highlight':
      case 'note':
        if (parts == null) return 0;
        final table = kind == 'bookmark'
            ? 'bookmarks'
            : (kind == 'highlight' ? 'highlights' : 'notes');
        final tsCol = kind == 'note' ? 'updated_at' : 'created_at';
        removed = await db.delete(
          table,
          where: 'book_id = ? AND chapter = ? AND verse = ? AND $tsCol <= ?',
          whereArgs: [
            int.parse(parts.group(1)!),
            int.parse(parts.group(2)!),
            int.parse(parts.group(3)!),
            deletedAt,
          ],
        );
      case 'sermon':
        final createdAt = int.tryParse(ref.replaceFirst('s', ''));
        if (createdAt == null) return 0;
        removed = await db.delete(
          'sermon_notes',
          where: 'created_at = ? AND updated_at <= ?',
          whereArgs: [createdAt, deletedAt],
        );
      case 'prayer':
        final createdAt = int.tryParse(ref.replaceFirst('p', ''));
        if (createdAt == null) return 0;
        removed = await db.delete(
          'prayers',
          where: 'created_at = ? AND updated_at <= ?',
          whereArgs: [createdAt, deletedAt],
        );
    }
    return removed;
  }

  /// 讀經紀錄：保留較新的 read_at。
  Future<void> upsertReadingLog(int bookId, int chapter, int readAt) async {
    final db = await database;
    final existing = await db.query(
      'reading_log',
      where: 'book_id = ? AND chapter = ?',
      whereArgs: [bookId, chapter],
    );
    if (existing.isNotEmpty &&
        (existing.first['read_at'] as int) >= readAt) {
      return;
    }
    await db.insert(
      'reading_log',
      {'book_id': bookId, 'chapter': chapter, 'read_at': readAt},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
