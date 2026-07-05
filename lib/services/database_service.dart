import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';

/// SQLite 資料庫服務，只存使用者資料（經文本身在 asset，不進 DB）。
///
/// 升版規則（重要，兩邊都要寫）：
/// 1. `_dbVersion` +1
/// 2. `_onUpgrade` 加一個 `if (oldV < n)` 區塊執行 migration
/// 3. `_createAllTables` 同步加上新表/新欄位的建表語句（給全新安裝用）
class DatabaseService {
  static const _dbName = 'bible_app.db';
  static const _dbVersion = 2;

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      join(dbPath, _dbName),
      version: _dbVersion,
      onCreate: (db, version) async => _createAllTables(db),
      onUpgrade: _onUpgrade,
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
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_notes_ref ON notes(book_id, chapter, verse)');
    await _createReadingLogTable(db); // v2
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

  Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    if (oldV < 2) {
      await _createReadingLogTable(db);
    }
  }

  // ---- Bookmarks ----

  Future<void> toggleBookmark(int bookId, int chapter, int verse) async {
    final db = await database;
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
    }
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
    if (color == null) {
      await db.delete(
        'highlights',
        where: 'book_id = ? AND chapter = ? AND verse = ?',
        whereArgs: [bookId, chapter, verse],
      );
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
    }
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

  Future<void> saveNote(
      int bookId, int chapter, int verse, String content) async {
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
        'created_at': now,
        'updated_at': now,
      });
    } else {
      await db.update(
        'notes',
        {'content': content, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
  }

  Future<void> deleteNote(int bookId, int chapter, int verse) async {
    final db = await database;
    await db.delete(
      'notes',
      where: 'book_id = ? AND chapter = ? AND verse = ?',
      whereArgs: [bookId, chapter, verse],
    );
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
  }

  /// 已讀章數。
  Future<int> getReadChapterCount() async {
    final db = await database;
    final rows =
        await db.rawQuery('SELECT COUNT(*) AS c FROM reading_log');
    return rows.first['c'] as int;
  }
}
