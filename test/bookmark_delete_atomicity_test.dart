import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bible_app/services/database_service.dart';

/// 書籤的資料一致性：本體與刪除紀錄（tombstone）必須同成同敗。
///
/// 失敗注入用真正的 SQLite trigger 讓 tombstones 的 INSERT／DELETE 失敗（RAISE ABORT）。
/// 舊實作（兩步、無 transaction）刪除時會留下「本機已刪、沒有墓碑」→ 下次同步時
/// 雲端那筆被下載回來（復活）；加回時會留下「有書籤又有墓碑」→ 同步把它刪掉。
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

  Future<int> bookmarkCount(int b, int c, int v) async => (await db.query(
        'bookmarks',
        where: 'book_id = ? AND chapter = ? AND verse = ?',
        whereArgs: [b, c, v],
      ))
          .length;

  Future<List<Map<String, Object?>>> bookmarkTombstones() =>
      db.query('tombstones', where: 'kind = ?', whereArgs: ['bookmark']);

  test('toggleBookmark 移除時墓碑寫入失敗：刪除回滾，書籤保留、沒有半套狀態', () async {
    await svc.toggleBookmark(43, 3, 16);
    mutations = 0;
    await failTombstoneInserts();

    await expectLater(svc.toggleBookmark(43, 3, 16), throwsA(anything));

    expect(await bookmarkCount(43, 3, 16), 1);
    expect(await bookmarkTombstones(), isEmpty);
    expect(mutations, 0);
    expect(await svc.getBookmarkedVerses(43, 3), {16});

    await db.execute('DROP TRIGGER fail_tomb_insert');
    await svc.toggleBookmark(43, 3, 16);
    expect(await bookmarkCount(43, 3, 16), 0);
    final tombs = await bookmarkTombstones();
    expect(tombs, hasLength(1));
    expect(tombs.single['ref'], 'b43_c3_v16');
    expect(mutations, 1);
  });

  test('setBookmark(false) 墓碑寫入失敗：刪除回滾；重試成功且再重試不會加回', () async {
    await svc.toggleBookmark(1, 1, 1);
    mutations = 0;
    await failTombstoneInserts();

    await expectLater(svc.setBookmark(1, 1, 1, false), throwsA(anything));
    expect(await bookmarkCount(1, 1, 1), 1);
    expect(await bookmarkTombstones(), isEmpty);
    expect(mutations, 0);

    await db.execute('DROP TRIGGER fail_tomb_insert');
    await svc.setBookmark(1, 1, 1, false);
    expect(await bookmarkCount(1, 1, 1), 0);
    expect(await bookmarkTombstones(), hasLength(1));
    expect(mutations, 1);

    // 重複移除（例如重試多按一次）：維持已移除，不像 toggle 會加回來。
    await svc.setBookmark(1, 1, 1, false);
    expect(await bookmarkCount(1, 1, 1), 0);
    expect(await bookmarkTombstones(), hasLength(1));
    expect(mutations, 1);
  });

  test('加回時清墓碑失敗：插入回滾，不會出現「有書籤又有墓碑」', () async {
    await svc.toggleBookmark(19, 23, 1);
    await svc.toggleBookmark(19, 23, 1); // 移除 → 留墓碑
    expect(await bookmarkTombstones(), hasLength(1));
    mutations = 0;
    await failTombstoneDeletes();

    await expectLater(svc.setBookmark(19, 23, 1, true), throwsA(anything));
    await expectLater(svc.toggleBookmark(19, 23, 1), throwsA(anything));
    expect(await bookmarkCount(19, 23, 1), 0);
    expect(await bookmarkTombstones(), hasLength(1));
    expect(mutations, 0);

    await db.execute('DROP TRIGGER fail_tomb_delete');
    await svc.setBookmark(19, 23, 1, true);
    await svc.setBookmark(19, 23, 1, true); // 重複復原不重複插入
    expect(await bookmarkCount(19, 23, 1), 1);
    expect(await bookmarkTombstones(), isEmpty);
    expect(mutations, 1);
  });

  test('正常移除只影響該節，其他書籤不受影響', () async {
    await svc.toggleBookmark(1, 1, 1);
    await svc.toggleBookmark(1, 1, 2);

    await svc.setBookmark(1, 1, 1, false);

    expect(await bookmarkCount(1, 1, 1), 0);
    expect(await bookmarkCount(1, 1, 2), 1);
    expect(await bookmarkTombstones(), hasLength(1));
  });
}
