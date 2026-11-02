import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bible_app/models/models.dart';
import 'package:bible_app/services/database_service.dart';

/// 經文筆記的刪除／還原與 tombstone 一致性。
///
/// - 軟刪除（deleteNote / softDeleteNoteById）是單一 UPDATE、不寫墓碑；
/// - 永久刪除（purgeNote）＝刪本體＋寫墓碑，必須同成同敗；
/// - 存檔（saveNote / saveNoteFull）＝寫本體＋清墓碑，也必須同成同敗。
///
/// 永久刪除寫的是**單則**墓碑（kind `note_item`，ref `n{created_at}`）：同一節可有多則
/// 筆記共用同一個雲端 doc，整節墓碑會誤刪同節其他筆記。舊版 App 留下的整節墓碑
/// （kind `note`，ref `b{book}_c{ch}_v{v}`）存檔時仍要清掉。
///
/// 失敗注入用真正的 SQLite trigger（RAISE ABORT）讓墓碑的 INSERT 或 DELETE 失敗。
/// 舊實作（兩步、無 transaction）會留下「本機已刪、沒有墓碑」（下次同步雲端那則
/// 被下載回來＝復活），或「活資料＋墓碑」並存（下次同步把剛存的筆記刪掉）。
void main() {
  sqfliteFfiInit();

  late Database db;
  late DatabaseService svc;
  late int mutations;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    svc = DatabaseService();
    await svc.debugCreateAllTables(db);
    svc.debugUseDatabase(db);
    mutations = 0;
    svc.onMutate = () => mutations++;
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> failTombstoneInsert() => db.execute('''
    CREATE TRIGGER fail_tomb_insert BEFORE INSERT ON tombstones
    BEGIN SELECT RAISE(ABORT, 'injected tombstone insert failure'); END
  ''');

  Future<void> failTombstoneDelete() => db.execute('''
    CREATE TRIGGER fail_tomb_delete BEFORE DELETE ON tombstones
    BEGIN SELECT RAISE(ABORT, 'injected tombstone delete failure'); END
  ''');

  Future<List<Map<String, Object?>>> noteTombstones() => db.query('tombstones',
      where: "kind IN ('note', 'note_item')", orderBy: 'kind, ref');

  // 舊版 App 永久刪除時寫的整節墓碑。
  Future<void> legacyVerseTombstone() =>
      svc.upsertTombstone('note', 'b43_c3_v16', 1);

  Future<Map<String, Object?>?> row(int id) async {
    final rows = await db.query('notes', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> createdAtOf(int id) async =>
      (await row(id))!['created_at'] as int;

  Future<int> trashedNote(int b, int c, int v, String content) async {
    final id = await svc.saveNoteFull(
        Note(bookId: b, chapter: c, verse: v, content: content, createdAt: 0, updatedAt: 0));
    await svc.softDeleteNoteById(id);
    return id;
  }

  test('永久刪除：墓碑寫入失敗時整筆回滾，筆記仍在最近刪除；重試同成', () async {
    final id = await trashedNote(43, 3, 16, '神愛世人');
    final created = await createdAtOf(id);
    mutations = 0;
    await failTombstoneInsert();

    await expectLater(svc.purgeNote(id), throwsA(anything));

    // 同敗：本體仍在（仍是軟刪除狀態）、沒有墓碑、不觸發自動同步。
    expect(await row(id), isNotNull);
    expect((await row(id))!['deleted_at'] as int, greaterThan(0));
    expect(await noteTombstones(), isEmpty);
    expect(mutations, 0);
    expect((await svc.getDeletedNotes()).map((n) => n.id), [id]);

    // 修復後重試：同成——本體刪除、單則墓碑 n{created_at}（同步擋下載、改寫雲端 doc）。
    await db.execute('DROP TRIGGER fail_tomb_insert');
    await svc.purgeNote(id);
    expect(await row(id), isNull);
    final tombs = await noteTombstones();
    expect(tombs.map((t) => '${t['kind']}:${t['ref']}'), ['note_item:n$created']);
    expect(mutations, 1);

    // 再重試一次：已不存在 → no-op，不重寫墓碑時間、不觸發同步。
    final deletedAt = tombs.single['deleted_at'];
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await svc.purgeNote(id);
    expect((await noteTombstones()).single['deleted_at'], deletedAt);
    expect(mutations, 1);
  });

  test('永久刪除：只寫該則的單則墓碑，從不寫整節墓碑（同節其他筆記不受影響）', () async {
    final keep = await svc.saveNoteFull(
        const Note(bookId: 43, chapter: 3, verse: 16, content: '保留', createdAt: 0, updatedAt: 0));
    final gone = await trashedNote(43, 3, 16, '要永久刪除');
    final other = await trashedNote(1, 1, 1, '別節');
    final keepCreated = await createdAtOf(keep);
    final goneCreated = await createdAtOf(gone);
    // 同一毫秒連續新增也不共用 created_at（它是跨裝置身分）。
    expect(keepCreated, isNot(goneCreated));

    await svc.purgeNote(gone);

    expect(await row(gone), isNull);
    expect(await row(keep), isNotNull);
    expect(await row(other), isNotNull);
    expect((await noteTombstones()).map((t) => '${t['kind']}:${t['ref']}'),
        ['note_item:n$goneCreated']);

    // 同節最後一則也刪掉：仍是單則墓碑。
    await svc.softDeleteNoteById(keep);
    await svc.purgeNote(keep);
    expect((await noteTombstones()).map((t) => t['kind']).toSet(), {'note_item'});
    expect((await noteTombstones()).map((t) => t['ref']).toSet(),
        {'n$goneCreated', 'n$keepCreated'});
    expect(await row(other), isNotNull);
  });

  test('saveNote：清墓碑失敗時本體也不寫入，不會留下活資料＋墓碑並存', () async {
    // 舊版 App 永久刪除過這節（留下整節墓碑）。
    await legacyVerseTombstone();
    mutations = 0;
    await failTombstoneDelete();

    await expectLater(
        svc.saveNote(43, 3, 16, '新的筆記'), throwsA(anything));

    expect(await db.query('notes'), isEmpty);
    expect(await noteTombstones(), hasLength(1));
    expect(mutations, 0);

    await db.execute('DROP TRIGGER fail_tomb_delete');
    await svc.saveNote(43, 3, 16, '新的筆記');
    expect((await db.query('notes')).single['content'], '新的筆記');
    expect(await noteTombstones(), isEmpty);
    expect(mutations, 1);
  });

  test('saveNoteFull：清墓碑失敗時新增與更新都回滾', () async {
    await legacyVerseTombstone();
    await failTombstoneDelete();

    await expectLater(
        svc.saveNoteFull(const Note(
            bookId: 43, chapter: 3, verse: 16, content: '新增', createdAt: 0, updatedAt: 0)),
        throwsA(anything));
    expect(await db.query('notes'), isEmpty);
    expect(await noteTombstones(), hasLength(1));

    // 更新路徑：既有筆記改錨點到有墓碑的節。
    await db.execute('DROP TRIGGER fail_tomb_delete');
    final other = await svc.saveNoteFull(
        const Note(bookId: 1, chapter: 1, verse: 1, content: '原本', createdAt: 0, updatedAt: 0));
    await failTombstoneDelete();
    mutations = 0;
    await expectLater(
        svc.saveNoteFull(Note(
            id: other, bookId: 43, chapter: 3, verse: 16, content: '改了', createdAt: 0, updatedAt: 0)),
        throwsA(anything));
    final r = (await row(other))!;
    expect(r['book_id'], 1);
    expect(r['content'], '原本');
    expect(await noteTombstones(), hasLength(1));
    expect(mutations, 0);
  });

  test('軟刪除與還原可安全重試：重複呼叫不重寫時間、不重複觸發同步', () async {
    final id = await svc.saveNoteFull(
        const Note(bookId: 43, chapter: 3, verse: 16, content: '筆記', createdAt: 0, updatedAt: 0));
    mutations = 0;

    await svc.softDeleteNoteById(id);
    final deletedAt = (await row(id))!['deleted_at'];
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await svc.softDeleteNoteById(id);
    await svc.deleteNote(43, 3, 16);
    expect((await row(id))!['deleted_at'], deletedAt);
    expect(mutations, 1);

    await svc.restoreNote(id);
    final updatedAt = (await row(id))!['updated_at'];
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await svc.restoreNote(id);
    expect((await row(id))!['deleted_at'], 0);
    expect((await row(id))!['updated_at'], updatedAt);
    expect(mutations, 2);

    // 軟刪除本身不寫墓碑（最近刪除是本機 trash）。
    expect(await noteTombstones(), isEmpty);
  });

  test('正常永久刪除：只刪該則，其他筆記不受影響', () async {
    final a = await trashedNote(43, 3, 16, 'A');
    final aCreated = await createdAtOf(a);
    final b = await svc.saveNoteFull(
        const Note(bookId: 19, chapter: 23, verse: 1, content: 'B', createdAt: 0, updatedAt: 0));

    await svc.purgeNote(a);

    expect(await row(a), isNull);
    expect(await row(b), isNotNull);
    expect((await noteTombstones()).map((t) => t['ref']), ['n$aCreated']);
  });
}
