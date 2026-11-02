import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bible_app/services/database_service.dart';
import 'package:bible_app/services/sync_service.dart';

/// 讀經計畫進度取消勾選的同步一致性：進度本體與刪除紀錄（`plan_item`／`plan_day`
/// tombstone）必須同成同敗，且取消要能同步到雲端（不再「只刪本機」）。
///
/// 失敗注入用真正的 SQLite trigger 讓 tombstones 的 INSERT／DELETE 失敗（RAISE ABORT）。
/// 舊實作取消時只刪本機列、不寫墓碑 → 下次同步時雲端那筆進度被下載回來（復活）。
void main() {
  sqfliteFfiInit();

  late Database db;
  late DatabaseService svc;
  late int mutations;

  Future<(Database, DatabaseService)> openDevice() async {
    final d = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    final s = DatabaseService();
    await s.debugCreateAllTables(d);
    s.debugUseDatabase(d);
    return (d, s);
  }

  setUp(() async {
    (db, svc) = await openDevice();
    mutations = 0;
    svc.onMutate = () => mutations++;
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> failTombstoneInserts({String? ref}) => db.execute('''
    CREATE TRIGGER fail_tomb_insert BEFORE INSERT ON tombstones
    ${ref == null ? '' : "WHEN NEW.ref = '$ref'"}
    BEGIN SELECT RAISE(ABORT, 'injected tombstone failure'); END
  ''');

  Future<void> failTombstoneDeletes() => db.execute('''
    CREATE TRIGGER fail_tomb_delete BEFORE DELETE ON tombstones
    BEGIN SELECT RAISE(ABORT, 'injected untomb failure'); END
  ''');

  Future<List<Map<String, Object?>>> items(String plan) => db.query(
    'plan_item_progress',
    where: 'plan_id = ?',
    whereArgs: [plan],
    orderBy: 'book_id, chapter',
  );

  Future<List<Map<String, Object?>>> tombs(String kind) =>
      db.query('tombstones', where: 'kind = ?', whereArgs: [kind]);

  test('取消勾選時墓碑寫入失敗：刪除回滾、進度保留；重試成功且只有一個墓碑', () async {
    await svc.setPlanItemDone('whole-365', 1, 43, 3, true);
    mutations = 0;
    await failTombstoneInserts();

    await expectLater(
      svc.setPlanItemDone('whole-365', 1, 43, 3, false),
      throwsA(anything),
    );
    expect(await items('whole-365'), hasLength(1));
    expect(await tombs('plan_item'), isEmpty);
    expect(mutations, 0);

    await db.execute('DROP TRIGGER fail_tomb_insert');
    await svc.setPlanItemDone('whole-365', 1, 43, 3, false);
    expect(await items('whole-365'), isEmpty);
    final t = await tombs('plan_item');
    expect(t, hasLength(1));
    expect(t.single['ref'], 'whole-365_b43_c3');
    expect(mutations, 1);
  });

  test('整天取消：其中一章墓碑失敗 → 整批回滾（不會只取消一半）', () async {
    final day = [
      const PlanItemTarget(1, 1, 1),
      const PlanItemTarget(1, 1, 2),
      const PlanItemTarget(1, 1, 3),
    ];
    await svc.setPlanItemsDone('p', day, true);
    mutations = 0;
    await failTombstoneInserts(ref: 'p_b1_c2');

    await expectLater(svc.setPlanItemsDone('p', day, false), throwsA(anything));
    expect(await items('p'), hasLength(3));
    expect(await tombs('plan_item'), isEmpty);
    expect(mutations, 0);

    await db.execute('DROP TRIGGER fail_tomb_insert');
    expect(await svc.setPlanItemsDone('p', day, false), 3);
    expect(await items('p'), isEmpty);
    expect((await tombs('plan_item')).map((t) => t['ref']).toSet(), {
      'p_b1_c1',
      'p_b1_c2',
      'p_b1_c3',
    });
    expect(mutations, 1);
  });

  test('重新勾選時清墓碑失敗：新增回滾，不會「已勾選＋墓碑」並存', () async {
    await svc.setPlanItemDone('p', 1, 1, 1, true);
    await svc.setPlanItemDone('p', 1, 1, 1, false);
    mutations = 0;
    await failTombstoneDeletes();

    await expectLater(
      svc.setPlanItemDone('p', 1, 1, 1, true),
      throwsA(anything),
    );
    expect(await items('p'), isEmpty);
    expect(await tombs('plan_item'), hasLength(1));
    expect(mutations, 0);

    await db.execute('DROP TRIGGER fail_tomb_delete');
    await svc.setPlanItemDone('p', 1, 1, 1, true);
    expect(await items('p'), hasLength(1));
    expect(await tombs('plan_item'), isEmpty);
    expect(mutations, 1);
  });

  test('目標狀態冪等：重複取消不記新墓碑、重複勾選不改 done_at、都不觸發同步', () async {
    await svc.setPlanItemDone('p', 1, 1, 1, true);
    await svc.setPlanItemDone('p', 1, 1, 2, true);
    await svc.setPlanItemDone('p', 1, 1, 1, false);
    final deletedAt = (await tombs('plan_item')).single['deleted_at'];
    final doneAt = (await items('p')).single['done_at'];
    mutations = 0;
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(
      await svc.setPlanItemsDone('p', [const PlanItemTarget(1, 1, 1)], false),
      0,
    );
    expect(
      await svc.setPlanItemsDone('p', [const PlanItemTarget(1, 9, 9)], false),
      0,
    );
    expect(
      await svc.setPlanItemsDone('p', [const PlanItemTarget(1, 1, 2)], true),
      0,
    );
    expect((await tombs('plan_item')).single['deleted_at'], deletedAt);
    expect((await items('p')).single['done_at'], doneAt);
    expect(mutations, 0);
  });

  test('舊資料「勾選＋墓碑」並存：再次勾選清墓碑並更新 done_at，同步不會誤刪', () async {
    await db.insert('plan_item_progress', {
      'plan_id': 'p',
      'book_id': 40,
      'chapter': 5,
      'day': 2,
      'done_at': 1000,
    });
    await db.insert('tombstones', {
      'kind': 'plan_item',
      'ref': 'p_b40_c5',
      'deleted_at': 2000,
    });

    await svc.setPlanItemDone('p', 2, 40, 5, true);
    expect(await tombs('plan_item'), isEmpty);
    expect((await items('p')).single['done_at'] as int, greaterThan(2000));

    await svc.upsertTombstone('plan_item', 'p_b40_c5', 2000);
    await svc.applyTombstone('plan_item', 'p_b40_c5', 2000);
    expect(await items('p'), hasLength(1));
  });

  test('套用墓碑：只刪不比刪除時間新的進度；planId 含底線也能解析', () async {
    await svc.upsertPlanItemProgress('my_plan_x', 1, 2, 1, 1000);
    await svc.upsertPlanItemProgress('my_plan_x', 1, 3, 1, 5000);
    expect(await svc.applyTombstone('plan_item', 'my_plan_x_b1_c2', 2000), 1);
    expect(await svc.applyTombstone('plan_item', 'my_plan_x_b1_c3', 2000), 0);
    expect((await items('my_plan_x')).single['chapter'], 3);
  });

  test('全部取消後不會再從舊版整天進度種回來', () async {
    await svc.upsertPlanProgress('p', 1, 1000); // 舊版：第 1 天完成
    final dayItems = {
      1: [
        [1, 1],
        [1, 2],
      ],
    };
    expect(await svc.seedPlanItemsFromDays('p', dayItems), 2);
    await svc.setPlanItemsDone('p', [
      const PlanItemTarget(1, 1, 1),
      const PlanItemTarget(1, 1, 2),
    ], false);
    expect(await items('p'), isEmpty);

    expect(await svc.seedPlanItemsFromDays('p', dayItems), 0);
    expect(await items('p'), isEmpty);
  });

  test('舊版整天取消（plan_progress）：本體與 plan_day 墓碑同成同敗', () async {
    await svc.setPlanDayDone('p', 3, true);
    mutations = 0;
    await failTombstoneInserts();
    await expectLater(svc.setPlanDayDone('p', 3, false), throwsA(anything));
    expect(await svc.getPlanProgress('p'), {3});
    expect(mutations, 0);

    await db.execute('DROP TRIGGER fail_tomb_insert');
    await svc.setPlanDayDone('p', 3, false);
    await svc.setPlanDayDone('p', 3, false); // 冪等
    expect(await svc.getPlanProgress('p'), isEmpty);
    expect((await tombs('plan_day')).single['ref'], 'p_d3');
    expect(mutations, 1);
  });

  test('收斂：活資料比墓碑新（他處重新勾選）→ 清墓碑；較舊則保留', () async {
    await db.insert('plan_item_progress', {
      'plan_id': 'p',
      'book_id': 1,
      'chapter': 1,
      'day': 1,
      'done_at': 3000,
    });
    await svc.upsertTombstone('plan_item', 'p_b1_c1', 2000);
    await svc.upsertTombstone('plan_item', 'p_b1_c2', 2000);
    expect(await svc.reconcilePlanTombstones(), 1);
    expect((await tombs('plan_item')).single['ref'], 'p_b1_c2');
  });

  group('雲端同步（fake Firestore）', () {
    test('A 取消 → 同步刪除雲端並上傳墓碑；B 同步後也被取消，不會復活', () async {
      final fs = FakeFirebaseFirestore();
      final (dbB, svcB) = await openDevice();
      addTearDown(dbB.close);
      final syncA = SyncService(svc, firestore: fs);
      final syncB = SyncService(svcB, firestore: fs);
      final cloud = fs
          .collection('users')
          .doc('u')
          .collection('plan_item_progress');

      await svc.setPlanItemsDone('whole-365', [
        const PlanItemTarget(1, 1, 1),
        const PlanItemTarget(1, 1, 2),
      ], true);
      await syncA.syncAll('u');
      await syncB.syncAll('u');
      expect(await svcB.getPlanItemProgress('whole-365'), {'b1_c1', 'b1_c2'});

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await svc.setPlanItemDone('whole-365', 1, 1, 1, false);
      await syncA.syncAll('u');
      expect((await cloud.get()).docs.map((d) => d.id), ['whole-365_b1_c2']);
      // A 再同步一次：雲端舊資料不會把取消的進度下載回來。
      await syncA.syncAll('u');
      expect(await svc.getPlanItemProgress('whole-365'), {'b1_c2'});

      await syncB.syncAll('u');
      expect(await svcB.getPlanItemProgress('whole-365'), {'b1_c2'});
    });

    test('B 取消後 A 重新勾選（較新）：同步後兩邊都保留勾選，雲端不被誤刪', () async {
      final fs = FakeFirebaseFirestore();
      final (dbB, svcB) = await openDevice();
      addTearDown(dbB.close);
      final syncA = SyncService(svc, firestore: fs);
      final syncB = SyncService(svcB, firestore: fs);

      await svc.setPlanItemDone('p', 1, 1, 1, true);
      await syncA.syncAll('u');
      await syncB.syncAll('u');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await svcB.setPlanItemDone('p', 1, 1, 1, false);
      await syncB.syncAll('u');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      // A 尚未同步到 B 的取消就重新勾選（取消再勾），時間較新。
      await svc.setPlanItemDone('p', 1, 1, 1, false);
      await svc.setPlanItemDone('p', 1, 1, 1, true);
      await syncA.syncAll('u');
      await syncB.syncAll('u');
      await syncA.syncAll('u');

      expect(await svc.getPlanItemProgress('p'), {'b1_c1'});
      expect(await svcB.getPlanItemProgress('p'), {'b1_c1'});
      final docs = await fs
          .collection('users')
          .doc('u')
          .collection('plan_item_progress')
          .get();
      expect(docs.docs.map((d) => d.id), ['p_b1_c1']);
    });
  });
}
