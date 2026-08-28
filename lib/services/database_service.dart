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
  static const _dbVersion = 12;

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
        title TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL,
        tags TEXT NOT NULL DEFAULT '',
        refs TEXT NOT NULL DEFAULT '',
        deleted_at INTEGER NOT NULL DEFAULT 0,
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
    await _createTodosTable(db); // v8
    await _createChapterCompletionsTable(db); // v9
    await _createPlanItemProgressTable(db); // v10
    await _createLaterTable(db); // v11
  }

  /// 稍後閱讀（Later，v11）：使用者標記「待讀」的節，與書籤分開（書籤＝收藏、
  /// Later＝待讀清單）。結構同書籤。
  Future<void> _createLaterTable(Database db) async {
    await db.execute('''
      CREATE TABLE later (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        chapter INTEGER NOT NULL,
        verse INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        UNIQUE(book_id, chapter, verse)
      )
    ''');
  }

  /// 讀經計畫「單一讀經項目」完成紀錄（v10，Reading Plans v2）。
  /// 一天含多個 Reading Item（章），每個項目可獨立勾選完成——
  /// 與舊的 plan_progress（整天為單位）並存，plan_progress 保留給向後相容。
  Future<void> _createPlanItemProgressTable(Database db) async {
    await db.execute('''
      CREATE TABLE plan_item_progress (
        plan_id TEXT NOT NULL,
        book_id INTEGER NOT NULL,
        chapter INTEGER NOT NULL,
        day INTEGER NOT NULL,
        done_at INTEGER NOT NULL,
        PRIMARY KEY(plan_id, book_id, chapter)
      )
    ''');
  }

  /// 章節「完成」紀錄（v9）：**使用者主動確認完成**的章，與「閱讀紀錄／造訪」
  /// （reading_log）分離——打開章節不等於完成章節。信仰地圖與已讀統計改用此表。
  Future<void> _createChapterCompletionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE chapter_completions (
        book_id INTEGER NOT NULL,
        chapter INTEGER NOT NULL,
        completed_at INTEGER NOT NULL,
        PRIMARY KEY(book_id, chapter)
      )
    ''');
  }

  /// 信仰生活代辦事項（首頁區塊）：分類/內容/完成狀態，使用者自行增刪，**可打勾**。
  Future<void> _createTodosTable(Database db) async {
    await db.execute('''
      CREATE TABLE todos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        done INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
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
    if (oldV < 8) {
      await _createTodosTable(db);
    }
    if (oldV < 9) {
      await _createChapterCompletionsTable(db);
      // 向後相容：把既有「閱讀紀錄」視為已完成，保留使用者現有的信仰地圖進度。
      // （舊版打開章節即記 reading_log；升版後只有主動確認才算完成，但既有進度不清空。）
      await db.execute('''
        INSERT OR IGNORE INTO chapter_completions (book_id, chapter, completed_at)
        SELECT book_id, chapter, read_at FROM reading_log
      ''');
    }
    if (oldV < 10) {
      await _createPlanItemProgressTable(db);
    }
    if (oldV < 11) {
      await _createLaterTable(db);
    }
    if (oldV < 12) {
      // Notes v2：可選標題、額外多節引用、軟刪除（最近刪除）。全部 additive。
      await db.execute(
          "ALTER TABLE notes ADD COLUMN title TEXT NOT NULL DEFAULT ''");
      await db.execute(
          "ALTER TABLE notes ADD COLUMN refs TEXT NOT NULL DEFAULT ''");
      await db.execute(
          'ALTER TABLE notes ADD COLUMN deleted_at INTEGER NOT NULL DEFAULT 0');
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

  // ---- 稍後閱讀（Later）----

  /// 加入 / 移除「稍後閱讀」（切換）。
  Future<void> toggleLater(int bookId, int chapter, int verse) async {
    final db = await database;
    final ref = _rowRef(bookId, chapter, verse);
    final deleted = await db.delete(
      'later',
      where: 'book_id = ? AND chapter = ? AND verse = ?',
      whereArgs: [bookId, chapter, verse],
    );
    if (deleted == 0) {
      await db.insert('later', {
        'book_id': bookId,
        'chapter': chapter,
        'verse': verse,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await _untomb(db, 'later', ref);
    } else {
      await _tombstone(db, 'later', ref);
    }
    _mutated();
  }

  /// 設定「稍後閱讀」（多選批次用；已存在則保留）。
  Future<void> addLater(int bookId, int chapter, int verse) async {
    final db = await database;
    await db.insert(
      'later',
      {
        'book_id': bookId,
        'chapter': chapter,
        'verse': verse,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await _untomb(db, 'later', _rowRef(bookId, chapter, verse));
    _mutated();
  }

  Future<void> removeLater(int bookId, int chapter, int verse) async {
    final db = await database;
    await db.delete(
      'later',
      where: 'book_id = ? AND chapter = ? AND verse = ?',
      whereArgs: [bookId, chapter, verse],
    );
    await _tombstone(db, 'later', _rowRef(bookId, chapter, verse));
    _mutated();
  }

  Future<List<Bookmark>> getAllLater() async {
    final db = await database;
    final rows = await db.query('later', orderBy: 'created_at DESC');
    return rows.map(Bookmark.fromMap).toList();
  }

  Future<Set<int>> getLaterVerses(int bookId, int chapter) async {
    final db = await database;
    final rows = await db.query(
      'later',
      columns: ['verse'],
      where: 'book_id = ? AND chapter = ?',
      whereArgs: [bookId, chapter],
    );
    return rows.map((r) => r['verse'] as int).toSet();
  }

  /// 雲端同步 upsert（已存在略過）。
  Future<void> upsertLater(
      int bookId, int chapter, int verse, int createdAt) async {
    final db = await database;
    await db.insert(
      'later',
      {
        'book_id': bookId,
        'chapter': chapter,
        'verse': verse,
        'created_at': createdAt,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
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

  /// 逐節快速筆記（Reader/單節面板用）：以錨點 (book,chapter,verse) upsert。
  /// **不動** title/refs（保留 v2 欄位不被簡易編輯清掉）；會清軟刪除旗標。
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
        {'content': content, 'tags': tags, 'deleted_at': 0, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
    await _untomb(db, 'note', _rowRef(bookId, chapter, verse));
    _mutated();
  }

  /// Notes v2 完整存檔（含標題/額外引用/標籤）。id 為 null＝新增，回傳 id。
  Future<int> saveNoteFull(Note note) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (note.id == null) {
      final id = await db.insert('notes', {
        'book_id': note.bookId,
        'chapter': note.chapter,
        'verse': note.verse,
        'title': note.title,
        'content': note.content,
        'tags': note.tags,
        'refs': note.refs.join(','),
        'deleted_at': 0,
        'created_at': now,
        'updated_at': now,
      });
      await _untomb(db, 'note', _rowRef(note.bookId, note.chapter, note.verse));
      _mutated();
      return id;
    }
    await db.update(
      'notes',
      {
        'book_id': note.bookId,
        'chapter': note.chapter,
        'verse': note.verse,
        'title': note.title,
        'content': note.content,
        'tags': note.tags,
        'refs': note.refs.join(','),
        'deleted_at': 0,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [note.id],
    );
    await _untomb(db, 'note', _rowRef(note.bookId, note.chapter, note.verse));
    _mutated();
    return note.id!;
  }

  /// 軟刪除到「最近刪除」（不寫墓碑；真正刪除走 purgeNote）。
  Future<void> deleteNote(int bookId, int chapter, int verse) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'notes',
      {'deleted_at': now, 'updated_at': now},
      where: 'book_id = ? AND chapter = ? AND verse = ? AND deleted_at = 0',
      whereArgs: [bookId, chapter, verse],
    );
    _mutated();
  }

  Future<void> softDeleteNoteById(int id) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update('notes', {'deleted_at': now, 'updated_at': now},
        where: 'id = ?', whereArgs: [id]);
    _mutated();
  }

  Future<void> restoreNote(int id) async {
    final db = await database;
    await db.update(
        'notes',
        {'deleted_at': 0, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [id]);
    _mutated();
  }

  /// 從「最近刪除」永久刪除（寫墓碑，同步刪除）。
  Future<void> purgeNote(int id) async {
    final db = await database;
    final rows = await db.query('notes',
        columns: ['book_id', 'chapter', 'verse'],
        where: 'id = ?',
        whereArgs: [id]);
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      final r = rows.first;
      await _tombstone(db, 'note',
          _rowRef(r['book_id'] as int, r['chapter'] as int, r['verse'] as int));
    }
    _mutated();
  }

  /// 全部正常（未軟刪除）筆記。
  Future<List<Note>> getAllNotes() async {
    final db = await database;
    final rows = await db.query('notes',
        where: 'deleted_at = 0', orderBy: 'updated_at DESC');
    return rows.map(Note.fromMap).toList();
  }

  /// 「最近刪除」的筆記（軟刪除）。
  Future<List<Note>> getDeletedNotes() async {
    final db = await database;
    final rows = await db.query('notes',
        where: 'deleted_at > 0', orderBy: 'deleted_at DESC');
    return rows.map(Note.fromMap).toList();
  }

  Future<Map<int, Note>> getChapterNotes(int bookId, int chapter) async {
    final db = await database;
    final rows = await db.query(
      'notes',
      where: 'book_id = ? AND chapter = ? AND deleted_at = 0',
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

  /// 曾造訪過的章數（Reading History）。
  Future<int> getVisitedChapterCount() async {
    final db = await database;
    final rows =
        await db.rawQuery('SELECT COUNT(*) AS c FROM reading_log');
    return rows.first['c'] as int;
  }

  Future<List<Map<String, dynamic>>> getReadingLog() async {
    final db = await database;
    return db.query('reading_log');
  }

  // ---- 章節完成（Chapter Completion，使用者主動確認）----

  /// 標記某章為「已完成」（主動確認）。
  Future<void> markChapterComplete(int bookId, int chapter) async {
    final db = await database;
    await db.insert(
      'chapter_completions',
      {
        'book_id': bookId,
        'chapter': chapter,
        'completed_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _untomb(db, 'completion', _completionRef(bookId, chapter));
    _mutated();
  }

  /// 取消某章的「已完成」標記（記墓碑供同步刪除）。
  Future<void> unmarkChapterComplete(int bookId, int chapter) async {
    final db = await database;
    await db.delete(
      'chapter_completions',
      where: 'book_id = ? AND chapter = ?',
      whereArgs: [bookId, chapter],
    );
    await _tombstone(db, 'completion', _completionRef(bookId, chapter));
    _mutated();
  }

  String _completionRef(int bookId, int chapter) => 'b${bookId}_c$chapter';

  Future<bool> isChapterComplete(int bookId, int chapter) async {
    final db = await database;
    final rows = await db.query(
      'chapter_completions',
      where: 'book_id = ? AND chapter = ?',
      whereArgs: [bookId, chapter],
    );
    return rows.isNotEmpty;
  }

  /// 已完成章數（全聖經 1,189 章）。
  Future<int> getReadChapterCount() async {
    final db = await database;
    final rows =
        await db.rawQuery('SELECT COUNT(*) AS c FROM chapter_completions');
    return rows.first['c'] as int;
  }

  Future<List<Map<String, dynamic>>> getAllChapterCompletions() async {
    final db = await database;
    return db.query('chapter_completions');
  }

  /// 每卷已完成章數（bookId → 已完成章數），信仰地圖用。
  Future<Map<int, int>> getReadCountsByBook() async {
    final db = await database;
    final rows = await db.rawQuery(
        'SELECT book_id, COUNT(*) AS c FROM chapter_completions GROUP BY book_id');
    return {for (final r in rows) r['book_id'] as int: r['c'] as int};
  }

  /// 完成紀錄合併（保留較新的 completed_at），雲端同步用。
  Future<void> upsertChapterCompletion(
      int bookId, int chapter, int completedAt) async {
    final db = await database;
    final existing = await db.query(
      'chapter_completions',
      where: 'book_id = ? AND chapter = ?',
      whereArgs: [bookId, chapter],
    );
    if (existing.isNotEmpty &&
        (existing.first['completed_at'] as int) >= completedAt) {
      return;
    }
    await db.insert(
      'chapter_completions',
      {'book_id': bookId, 'chapter': chapter, 'completed_at': completedAt},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
      {String tags = '', String title = '', String refs = ''}) async {
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
        'title': title,
        'content': content,
        'tags': tags,
        'refs': refs,
        'created_at': createdAt,
        'updated_at': updatedAt,
      });
    } else if ((existing.first['updated_at'] as int) < updatedAt) {
      await db.update(
        'notes',
        {
          'title': title,
          'content': content,
          'tags': tags,
          'refs': refs,
          'updated_at': updatedAt
        },
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
      'read': await count('chapter_completions'),
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

  // ---- 讀經計畫 v2：單一讀經項目（章）進度 ----

  /// 某計畫已完成的讀經項目（book_id*1000+chapter 無法保證唯一，改用字串 key）。
  /// 回傳 {'b{book}_c{chapter}'} 集合。
  Future<Set<String>> getPlanItemProgress(String planId) async {
    final db = await database;
    final rows = await db.query('plan_item_progress',
        columns: ['book_id', 'chapter'],
        where: 'plan_id = ?',
        whereArgs: [planId]);
    return {
      for (final r in rows) 'b${r['book_id']}_c${r['chapter']}',
    };
  }

  /// 各計畫已完成項目數（planId → 已完成章數），計畫列表進度條用。
  Future<Map<String, int>> getPlanItemDoneCounts() async {
    final db = await database;
    final rows = await db.rawQuery(
        'SELECT plan_id, COUNT(*) AS c FROM plan_item_progress GROUP BY plan_id');
    return {for (final r in rows) r['plan_id'] as String: r['c'] as int};
  }

  /// 勾選/取消單一讀經項目（章）。取消＝本地刪除（同 plan_progress 慣例，無墓碑）。
  Future<void> setPlanItemDone(
      String planId, int day, int bookId, int chapter, bool done) async {
    final db = await database;
    if (done) {
      await db.insert(
        'plan_item_progress',
        {
          'plan_id': planId,
          'book_id': bookId,
          'chapter': chapter,
          'day': day,
          'done_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await db.delete(
        'plan_item_progress',
        where: 'plan_id = ? AND book_id = ? AND chapter = ?',
        whereArgs: [planId, bookId, chapter],
      );
    }
    _mutated();
  }

  Future<List<Map<String, dynamic>>> getAllPlanItemProgress() async {
    final db = await database;
    return db.query('plan_item_progress');
  }

  /// 向後相容：把舊版「整天完成」（plan_progress）一次性攤平成 v2 的
  /// 逐項目完成（plan_item_progress）。只在該計畫尚無任何 v2 項目進度時做，
  /// 需要外部傳入 day→該天章清單（因排程依賴 books，不能純 SQL 算）。
  /// [dayItems]：day(1-based) → 該天的 [(bookId, chapter), …]。
  Future<int> seedPlanItemsFromDays(
      String planId, Map<int, List<List<int>>> dayItems) async {
    final db = await database;
    final already = await db.query('plan_item_progress',
        where: 'plan_id = ?', whereArgs: [planId], limit: 1);
    if (already.isNotEmpty) return 0; // 已有 v2 進度，不覆蓋
    final doneDays = await getPlanProgress(planId);
    if (doneDays.isEmpty) return 0;
    var seeded = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final day in doneDays) {
      for (final item in dayItems[day] ?? const <List<int>>[]) {
        batch.insert(
          'plan_item_progress',
          {
            'plan_id': planId,
            'book_id': item[0],
            'chapter': item[1],
            'day': day,
            'done_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        seeded++;
      }
    }
    await batch.commit(noResult: true);
    if (seeded > 0) _mutated();
    return seeded;
  }

  /// 計畫項目進度合併（保留較新的 done_at），雲端同步用。
  Future<void> upsertPlanItemProgress(
      String planId, int bookId, int chapter, int day, int doneAt) async {
    final db = await database;
    final existing = await db.query(
      'plan_item_progress',
      where: 'plan_id = ? AND book_id = ? AND chapter = ?',
      whereArgs: [planId, bookId, chapter],
    );
    if (existing.isNotEmpty && (existing.first['done_at'] as int) >= doneAt) {
      return;
    }
    await db.insert(
      'plan_item_progress',
      {
        'plan_id': planId,
        'book_id': bookId,
        'chapter': chapter,
        'day': day,
        'done_at': doneAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 勾選/取消某一天（整天為單位；v1 相容保留）。
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

  // ---- 信仰生活代辦事項 ----

  Future<List<Todo>> getTodos() async {
    final db = await database;
    final rows = await db.query('todos',
        orderBy: 'done, category, created_at DESC');
    return rows.map(Todo.fromMap).toList();
  }

  Future<int> saveTodo(Todo t) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (t.id == null) {
      final m = t.toMap()
        ..['created_at'] = now
        ..['updated_at'] = now;
      final id = await db.insert('todos', m);
      await _untomb(db, 'todo', 't$now');
      _mutated();
      return id;
    }
    await db.update('todos', t.toMap()..['updated_at'] = now,
        where: 'id = ?', whereArgs: [t.id]);
    await _untomb(db, 'todo', 't${t.createdAt}');
    _mutated();
    return t.id!;
  }

  Future<void> deleteTodo(int id) async {
    final db = await database;
    final rows = await db.query('todos',
        columns: ['created_at'], where: 'id = ?', whereArgs: [id]);
    await db.delete('todos', where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      await _tombstone(db, 'todo', 't${rows.first['created_at']}');
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
      case 'later':
      case 'highlight':
      case 'note':
        if (parts == null) return 0;
        final table = kind == 'bookmark'
            ? 'bookmarks'
            : (kind == 'later'
                ? 'later'
                : (kind == 'highlight' ? 'highlights' : 'notes'));
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
      case 'todo':
        final createdAt = int.tryParse(ref.replaceFirst('t', ''));
        if (createdAt == null) return 0;
        removed = await db.delete(
          'todos',
          where: 'created_at = ? AND updated_at <= ?',
          whereArgs: [createdAt, deletedAt],
        );
      case 'completion':
        final cm = RegExp(r'^b(\d+)_c(\d+)$').firstMatch(ref);
        if (cm == null) return 0;
        removed = await db.delete(
          'chapter_completions',
          where: 'book_id = ? AND chapter = ? AND completed_at <= ?',
          whereArgs: [
            int.parse(cm.group(1)!),
            int.parse(cm.group(2)!),
            deletedAt,
          ],
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
