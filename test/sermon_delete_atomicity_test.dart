import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bible_app/models/models.dart';
import 'package:bible_app/services/database_service.dart';

/// deleteSermonNote 的資料一致性：刪除本體與寫刪除紀錄（tombstone）必須同成同敗。
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

  Future<void> failTombstoneWrites() => db.execute('''
    CREATE TRIGGER fail_tombstone BEFORE INSERT ON tombstones
    BEGIN SELECT RAISE(ABORT, 'injected tombstone failure'); END
  ''');

  Future<int> noteCount(int id) async =>
      (await db.query('sermon_notes', where: 'id = ?', whereArgs: [id])).length;

  Future<List<Map<String, Object?>>> sermonTombstones() =>
      db.query('tombstones', where: 'kind = ?', whereArgs: ['sermon']);

  SermonNote note(String title) =>
      SermonNote(date: 0, title: title, createdAt: 0, updatedAt: 0);

  test('墓碑寫入失敗：本體刪除一併回滾，筆記保留且沒有半套狀態', () async {
    final id = await svc.saveSermonNote(note('主日信息'));
    final createdAt = (await db.query(
      'sermon_notes',
      where: 'id = ?',
      whereArgs: [id],
    )).first['created_at'];
    mutations = 0;
    await failTombstoneWrites();

    await expectLater(svc.deleteSermonNote(id), throwsA(anything));

    // 同敗：本體仍在、沒有墓碑、不觸發自動同步。
    expect(await noteCount(id), 1);
    expect(await sermonTombstones(), isEmpty);
    expect(mutations, 0);
    final reloaded = await svc.getSermonNotes();
    expect(reloaded.map((n) => n.title), contains('主日信息'));

    // 修復後重試：同成——本體刪除且墓碑寫入（同步會刪雲端、擋下載）。
    await db.execute('DROP TRIGGER fail_tombstone');
    await svc.deleteSermonNote(id);
    expect(await noteCount(id), 0);
    final tombs = await sermonTombstones();
    expect(tombs, hasLength(1));
    expect(tombs.single['ref'], 's$createdAt');
    expect(mutations, 1);
  });

  test('正常刪除：本體與墓碑一起完成，其他筆記不受影響', () async {
    final a = await svc.saveSermonNote(note('A'));
    // created_at 是毫秒時間戳，確保兩筆 ref 不同。
    await Future<void>.delayed(const Duration(milliseconds: 2));
    final b = await svc.saveSermonNote(note('B'));

    await svc.deleteSermonNote(a);

    expect(await noteCount(a), 0);
    expect(await noteCount(b), 1);
    expect(await sermonTombstones(), hasLength(1));
  });

  test('刪除不存在的筆記：不寫墓碑也不出錯（重試安全）', () async {
    await svc.deleteSermonNote(9999);
    expect(await sermonTombstones(), isEmpty);
  });
}
