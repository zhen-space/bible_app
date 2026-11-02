import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bible_app/models/models.dart';
import 'package:bible_app/services/database_service.dart';

/// 螢光筆的資料一致性：本體與刪除紀錄（tombstone）必須同成同敗。
///
/// 失敗注入用真正的 SQLite trigger 讓 tombstones 的 INSERT／DELETE 失敗（RAISE ABORT）。
/// 舊實作（兩步、無 transaction）移除時會留下「本機已刪、沒有墓碑」→ 下次同步時
/// 雲端那筆被下載回來（復活）；設色時會留下「有螢光筆又有墓碑」→ 同步把它刪掉。
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

  Future<List<Map<String, Object?>>> highlightTombstones() =>
      db.query('tombstones', where: 'kind = ?', whereArgs: ['highlight']);

  test('移除時墓碑寫入失敗：刪除回滾，螢光筆保留、沒有半套狀態；重試成功', () async {
    await svc.setHighlight(43, 3, 16, HighlightColor.green);
    mutations = 0;
    await failTombstoneInserts();

    await expectLater(svc.setHighlight(43, 3, 16, null), throwsA(anything));

    expect(await svc.getChapterHighlights(43, 3), {16: HighlightColor.green});
    expect(await highlightTombstones(), isEmpty);
    expect(mutations, 0);

    await db.execute('DROP TRIGGER fail_tomb_insert');
    await svc.setHighlight(43, 3, 16, null);
    expect(await svc.getChapterHighlights(43, 3), isEmpty);
    final tombs = await highlightTombstones();
    expect(tombs, hasLength(1));
    expect(tombs.single['ref'], 'b43_c3_v16');
    expect(mutations, 1);
  });

  test('重複移除（重試多按一次）是 no-op：不改寫墓碑時間、不觸發同步', () async {
    await svc.setHighlight(1, 1, 1, HighlightColor.yellow);
    await svc.setHighlight(1, 1, 1, null);
    final first = (await highlightTombstones()).single['deleted_at'];
    mutations = 0;

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await svc.setHighlight(1, 1, 1, null);

    expect((await highlightTombstones()).single['deleted_at'], first);
    expect(mutations, 0);
  });

  test('沒有螢光筆的節移除不留墓碑（批次清除不會蓋掉別台裝置的同節螢光筆）', () async {
    await svc.setHighlight(19, 23, 2, null);

    expect(await highlightTombstones(), isEmpty);
    expect(mutations, 0);
  });

  test('復原（設色）時清墓碑失敗：寫入回滾，不會出現「有螢光筆又有墓碑」', () async {
    await svc.setHighlight(19, 23, 1, HighlightColor.pink);
    await svc.setHighlight(19, 23, 1, null);
    expect(await highlightTombstones(), hasLength(1));
    mutations = 0;
    await failTombstoneDeletes();

    await expectLater(
        svc.setHighlight(19, 23, 1, HighlightColor.pink), throwsA(anything));
    expect(await svc.getChapterHighlights(19, 23), isEmpty);
    expect(await highlightTombstones(), hasLength(1));
    expect(mutations, 0);

    await db.execute('DROP TRIGGER fail_tomb_delete');
    await svc.setHighlight(19, 23, 1, HighlightColor.pink);
    await svc.setHighlight(19, 23, 1, HighlightColor.pink); // 重複復原不重複插入
    expect((await svc.getAllHighlights()).where((h) => h.verse == 1),
        hasLength(1));
    expect(await svc.getChapterHighlights(19, 23), {1: HighlightColor.pink});
    expect(await highlightTombstones(), isEmpty);
  });

  test('正常移除只影響該節，其他螢光筆不受影響', () async {
    await svc.setHighlight(1, 1, 1, HighlightColor.blue);
    await svc.setHighlight(1, 1, 2, HighlightColor.orange);

    await svc.setHighlight(1, 1, 1, null);

    expect(await svc.getChapterHighlights(1, 1), {2: HighlightColor.orange});
    expect(await highlightTombstones(), hasLength(1));
  });
}
