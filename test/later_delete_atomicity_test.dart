import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bible_app/services/database_service.dart';

/// 稍後閱讀的資料一致性：本體與刪除紀錄（tombstone）必須同成同敗。
///
/// 失敗注入用真正的 SQLite trigger 讓 tombstones 的 INSERT／DELETE 失敗（RAISE ABORT）。
/// 舊實作（兩步、無 transaction）移除時會留下「本機已刪、沒有墓碑」→ 下次同步時
/// 雲端那筆被下載回來（復活）；加回時會留下「有待讀又有墓碑」→ 同步把它刪掉（誤刪）。
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

  Future<void> failTombstoneInserts() => db.execute('''
    CREATE TRIGGER fail_tomb_insert BEFORE INSERT ON tombstones
    BEGIN SELECT RAISE(ABORT, 'injected tombstone failure'); END
  ''');

  Future<void> failTombstoneDeletes() => db.execute('''
    CREATE TRIGGER fail_tomb_delete BEFORE DELETE ON tombstones
    BEGIN SELECT RAISE(ABORT, 'injected untomb failure'); END
  ''');

  Future<List<Map<String, Object?>>> laterRows(int b, int c, int v) =>
      db.query(
        'later',
        where: 'book_id = ? AND chapter = ? AND verse = ?',
        whereArgs: [b, c, v],
      );

  Future<List<Map<String, Object?>>> laterTombstones() =>
      db.query('tombstones', where: 'kind = ?', whereArgs: ['later']);

  test('removeLater 墓碑寫入失敗：刪除回滾，待讀保留；重試成功且只有一個墓碑', () async {
    await svc.addLater(43, 3, 16);
    mutations = 0;
    await failTombstoneInserts();

    await expectLater(svc.removeLater(43, 3, 16), throwsA(anything));
    expect(await laterRows(43, 3, 16), hasLength(1));
    expect(await laterTombstones(), isEmpty);
    expect(mutations, 0);

    await db.execute('DROP TRIGGER fail_tomb_insert');
    await svc.removeLater(43, 3, 16);
    expect(await laterRows(43, 3, 16), isEmpty);
    final tombs = await laterTombstones();
    expect(tombs, hasLength(1));
    expect(tombs.single['ref'], 'b43_c3_v16');
    expect(mutations, 1);
  });

  test('重複移除不存在的節：不記新墓碑、不改 deleted_at、不觸發同步', () async {
    await svc.addLater(1, 1, 1);
    await svc.removeLater(1, 1, 1);
    final before = (await laterTombstones()).single['deleted_at'];
    mutations = 0;
    await Future<void>.delayed(const Duration(milliseconds: 5));

    await svc.removeLater(1, 1, 1);
    await svc.removeLater(2, 2, 2); // 從未加入
    final tombs = await laterTombstones();
    expect(tombs, hasLength(1));
    expect(tombs.single['deleted_at'], before);
    expect(mutations, 0);
  });

  test('toggleLater 移除時墓碑寫入失敗：刪除回滾，沒有半套狀態', () async {
    await svc.toggleLater(19, 23, 1);
    mutations = 0;
    await failTombstoneInserts();

    await expectLater(svc.toggleLater(19, 23, 1), throwsA(anything));
    expect(await laterRows(19, 23, 1), hasLength(1));
    expect(await laterTombstones(), isEmpty);
    expect(mutations, 0);
  });

  test('加回時清墓碑失敗：插入回滾，不會出現「有待讀又有墓碑」；重複加回不重複插入', () async {
    await svc.addLater(19, 23, 1);
    await svc.removeLater(19, 23, 1); // 留墓碑
    expect(await laterTombstones(), hasLength(1));
    mutations = 0;
    await failTombstoneDeletes();

    await expectLater(svc.addLater(19, 23, 1), throwsA(anything));
    await expectLater(svc.toggleLater(19, 23, 1), throwsA(anything));
    expect(await laterRows(19, 23, 1), isEmpty);
    expect(await laterTombstones(), hasLength(1));
    expect(mutations, 0);

    await db.execute('DROP TRIGGER fail_tomb_delete');
    await svc.setLater(19, 23, 1, true);
    final first = (await laterRows(19, 23, 1)).single['created_at'];
    await svc.setLater(19, 23, 1, true); // 重複復原：不動
    final rows = await laterRows(19, 23, 1);
    expect(rows, hasLength(1));
    expect(rows.single['created_at'], first);
    expect(await laterTombstones(), isEmpty);
    expect(mutations, 1);
  });

  test('舊資料殘留「有待讀又有墓碑」：再加入時清掉墓碑修復不變量', () async {
    await svc.addLater(40, 5, 3);
    await db.insert('tombstones',
        {'kind': 'later', 'ref': 'b40_c5_v3', 'deleted_at': 1});
    mutations = 0;

    await svc.addLater(40, 5, 3);
    expect(await laterRows(40, 5, 3), hasLength(1));
    expect(await laterTombstones(), isEmpty);
    expect(mutations, 1);
  });

  test('正常移除只影響該節，其他待讀不受影響', () async {
    await svc.addLater(1, 1, 1);
    await svc.addLater(1, 1, 2);
    await svc.removeLater(1, 1, 1);
    expect(await svc.getLaterVerses(1, 1), {2});
    expect((await laterTombstones()).single['ref'], 'b1_c1_v1');
  });
}
