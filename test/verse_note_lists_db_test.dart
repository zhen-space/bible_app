import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bible_app/models/models.dart';
import 'package:bible_app/services/database_service.dart';

/// 讀經頁同節多則筆記的資料來源（真 SQLite）：
/// - [DatabaseService.getChapterNoteLists] 每節回傳**全部**正常筆記（最新在前），
///   不像舊的 getChapterNotes 每節只留一則；
/// - [DatabaseService.getVerseNotes] 只回該節、排除最近刪除；
/// - 讀經頁新增走 saveNoteFull(id: null) → 一定是新的一則，不覆蓋同節既有筆記。
void main() {
  sqfliteFfiInit();

  late Database db;
  late DatabaseService svc;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    svc = DatabaseService();
    await svc.debugCreateAllTables(db);
    svc.debugUseDatabase(db);
  });

  tearDown(() async => db.close());

  Future<void> insert(
    int verse,
    String content,
    int updatedAt, {
    int deletedAt = 0,
    int chapter = 3,
  }) => db.insert('notes', {
    'book_id': 43,
    'chapter': chapter,
    'verse': verse,
    'content': content,
    'tags': '',
    'deleted_at': deletedAt,
    'created_at': updatedAt,
    'updated_at': updatedAt,
  });

  Note fresh(int verse, String content) => Note(
    bookId: 43,
    chapter: 3,
    verse: verse,
    content: content,
    createdAt: 0,
    updatedAt: 0,
  );

  test('getChapterNoteLists：同節全部筆記、最新在前，排除最近刪除與別章', () async {
    await insert(16, '舊', 100);
    await insert(16, '新', 300);
    await insert(16, '中', 200);
    await insert(16, '已刪', 400, deletedAt: 500);
    await insert(17, '別節', 150);
    await insert(16, '別章', 600, chapter: 4);

    final lists = await svc.getChapterNoteLists(43, 3);
    expect(lists.keys.toSet(), {16, 17});
    expect(lists[16]!.map((n) => n.content), ['新', '中', '舊']);
    expect(lists[17]!.map((n) => n.content), ['別節']);

    final verse = await svc.getVerseNotes(43, 3, 16);
    expect(verse.map((n) => n.content), ['新', '中', '舊']);
    expect(await svc.getVerseNotes(43, 3, 18), isEmpty);
  });

  test('讀經頁新增（saveNoteFull id=null）不覆蓋同節既有筆記；編輯只改選中那一則', () async {
    await insert(16, '既有一', 100);
    await insert(16, '既有二', 200);

    await svc.saveNoteFull(fresh(16, '新增的'));
    var notes = await svc.getVerseNotes(43, 3, 16);
    expect(notes, hasLength(3));
    expect(notes.first.content, '新增的');
    expect(
      notes.map((n) => n.createdAt).toSet(),
      hasLength(3),
      reason: 'created_at 是跨裝置身分，必須唯一',
    );

    final older = notes.firstWhere((n) => n.content == '既有一');
    await svc.saveNoteFull(
      Note(
        id: older.id,
        bookId: 43,
        chapter: 3,
        verse: 16,
        title: older.title,
        content: '既有一（改）',
        refs: older.refs,
        createdAt: older.createdAt,
        updatedAt: older.updatedAt,
      ),
    );
    notes = await svc.getVerseNotes(43, 3, 16);
    expect(notes.map((n) => n.content).toSet(), {'新增的', '既有一（改）', '既有二'});
    expect(
      notes.firstWhere((n) => n.id == older.id).createdAt,
      older.createdAt,
    );
  });
}
