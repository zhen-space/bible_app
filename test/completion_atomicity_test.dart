import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bible_app/services/database_service.dart';

/// 章節完成的資料一致性：完成紀錄與刪除紀錄（`completion` tombstone）必須同成同敗。
///
/// 失敗注入用真正的 SQLite trigger 讓 tombstones 的 INSERT／DELETE 失敗（RAISE ABORT）。
/// 舊實作（兩步、無 transaction）取消時會留下「本機已取消、沒有墓碑」→ 下次同步時
/// 雲端那筆完成被下載回來（復活）；重新完成時會留下「已完成又有墓碑」→ 同步把它刪掉（誤刪）。
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

  Future<List<Map<String, Object?>>> rows(int b, int c) => db.query(
    'chapter_completions',
    where: 'book_id = ? AND chapter = ?',
    whereArgs: [b, c],
  );

  Future<List<Map<String, Object?>>> tombs() =>
      db.query('tombstones', where: 'kind = ?', whereArgs: ['completion']);

  test('取消完成時墓碑寫入失敗：刪除回滾，完成保留；重試成功且只有一個墓碑', () async {
    await svc.markChapterComplete(43, 3);
    mutations = 0;
    await failTombstoneInserts();

    await expectLater(svc.unmarkChapterComplete(43, 3), throwsA(anything));
    expect(await rows(43, 3), hasLength(1));
    expect(await tombs(), isEmpty);
    expect(mutations, 0);

    await db.execute('DROP TRIGGER fail_tomb_insert');
    await svc.setChapterComplete(43, 3, false);
    expect(await rows(43, 3), isEmpty);
    final t = await tombs();
    expect(t, hasLength(1));
    expect(t.single['ref'], 'b43_c3');
    expect(mutations, 1);
  });

  test('重新完成時清墓碑失敗：新增回滾，不會「已完成＋墓碑」並存', () async {
    await svc.markChapterComplete(1, 1);
    await svc.unmarkChapterComplete(1, 1);
    mutations = 0;
    await failTombstoneDeletes();

    await expectLater(svc.markChapterComplete(1, 1), throwsA(anything));
    expect(await rows(1, 1), isEmpty);
    expect(await tombs(), hasLength(1));
    expect(mutations, 0);

    await db.execute('DROP TRIGGER fail_tomb_delete');
    await svc.setChapterComplete(1, 1, true);
    expect(await rows(1, 1), hasLength(1));
    expect(await tombs(), isEmpty);
    expect(mutations, 1);
  });

  test('重複取消／從未完成的章：不記新墓碑、不改 deleted_at、不觸發同步', () async {
    await svc.markChapterComplete(1, 1);
    await svc.unmarkChapterComplete(1, 1);
    final before = (await tombs()).single['deleted_at'];
    mutations = 0;
    await Future<void>.delayed(const Duration(milliseconds: 5));

    await svc.unmarkChapterComplete(1, 1);
    await svc.setChapterComplete(2, 5, false);
    final t = await tombs();
    expect(t, hasLength(1));
    expect(t.single['deleted_at'], before);
    expect(mutations, 0);
  });

  test('重複完成：不重複寫入、不改 completed_at、不觸發同步', () async {
    await svc.markChapterComplete(19, 23);
    final before = (await rows(19, 23)).single['completed_at'];
    mutations = 0;
    await Future<void>.delayed(const Duration(milliseconds: 5));

    await svc.markChapterComplete(19, 23);
    await svc.setChapterComplete(19, 23, true);
    final r = await rows(19, 23);
    expect(r, hasLength(1));
    expect(r.single['completed_at'], before);
    expect(mutations, 0);
  });

  test('舊資料「完成＋墓碑」並存：再次完成會清墓碑並更新 completed_at，同步不會誤刪', () async {
    await db.insert('chapter_completions', {
      'book_id': 40,
      'chapter': 5,
      'completed_at': 1000,
    });
    await db.insert('tombstones', {
      'kind': 'completion',
      'ref': 'b40_c5',
      'deleted_at': 2000,
    });
    mutations = 0;

    await svc.markChapterComplete(40, 5);
    expect(await tombs(), isEmpty);
    final completedAt = (await rows(40, 5)).single['completed_at'] as int;
    expect(completedAt, greaterThan(2000));
    expect(mutations, 1);

    // 雲端仍帶著那個舊墓碑 → 套用後不會刪掉剛確認的完成。
    await svc.upsertTombstone('completion', 'b40_c5', 2000);
    await svc.applyTombstone('completion', 'b40_c5', 2000);
    expect(await rows(40, 5), hasLength(1));
  });

  test('對照：正常取消只動該章，其他章不受影響', () async {
    await svc.markChapterComplete(1, 1);
    await svc.markChapterComplete(1, 2);
    await svc.unmarkChapterComplete(1, 1);
    expect(await rows(1, 1), isEmpty);
    expect(await rows(1, 2), hasLength(1));
    expect((await tombs()).map((t) => t['ref']), ['b1_c1']);
  });
}
