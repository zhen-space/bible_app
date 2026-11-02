import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bible_app/models/models.dart';
import 'package:bible_app/services/database_service.dart';

/// deleteTodo 的資料一致性：刪除本體與寫刪除紀錄（tombstone）必須同成同敗。
///
/// 失敗注入用真正的 SQLite trigger 讓 tombstones 的 INSERT 失敗（RAISE ABORT），
/// 模擬「本體已刪、墓碑寫入失敗」。舊實作（兩步、無 transaction）會留下
/// 「本機已刪、沒有墓碑」→ 下次同步時雲端那筆會被下載回來（復活）。
void main() {
  sqfliteFfiInit();

  late Database db;
  late DatabaseService svc;
  late int mutations;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    svc = DatabaseService();
    await svc.debugCreateAllTables(db);
    svc.debugUseDatabase(db);
    mutations = 0;
    svc.onMutate = () => mutations++;
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> failTombstoneWrites() => db.execute('''
    CREATE TRIGGER fail_tombstone BEFORE INSERT ON tombstones
    BEGIN SELECT RAISE(ABORT, 'injected tombstone failure'); END
  ''');

  Future<int> todoCount(int id) async =>
      (await db.query('todos', where: 'id = ?', whereArgs: [id])).length;

  Future<List<Map<String, Object?>>> todoTombstones() =>
      db.query('tombstones', where: 'kind = ?', whereArgs: ['todo']);

  test('墓碑寫入失敗：本體刪除一併回滾，資料保留且沒有半套狀態', () async {
    final id = await svc.saveTodo(const Todo(category: '靈修', content: '讀詩篇'));
    final createdAt =
        (await db.query('todos', where: 'id = ?', whereArgs: [id]))
            .first['created_at'];
    mutations = 0;
    await failTombstoneWrites();

    await expectLater(svc.deleteTodo(id), throwsA(anything));

    // 同敗：本體仍在、沒有墓碑、不觸發自動同步。
    expect(await todoCount(id), 1);
    expect(await todoTombstones(), isEmpty);
    expect(mutations, 0);
    final reloaded = await svc.getTodos();
    expect(reloaded.map((t) => t.content), contains('讀詩篇'));

    // 修復後重試：同成——本體刪除且墓碑寫入（同步會刪雲端、擋下載）。
    await db.execute('DROP TRIGGER fail_tombstone');
    await svc.deleteTodo(id);
    expect(await todoCount(id), 0);
    final tombs = await todoTombstones();
    expect(tombs, hasLength(1));
    expect(tombs.single['ref'], 't$createdAt');
    expect(mutations, 1);
  });

  test('正常刪除：本體與墓碑一起完成，其他代辦不受影響', () async {
    final a = await svc.saveTodo(const Todo(content: 'A'));
    final b = await svc.saveTodo(const Todo(content: 'B'));

    await svc.deleteTodo(a);

    expect(await todoCount(a), 0);
    expect(await todoCount(b), 1);
    expect(await todoTombstones(), hasLength(1));
  });

  test('刪除不存在的代辦：不寫墓碑也不出錯（重試安全）', () async {
    await svc.deleteTodo(9999);
    expect(await todoTombstones(), isEmpty);
  });
}
