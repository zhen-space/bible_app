import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bible_app/services/database_service.dart';

/// 既有使用者「舊 schema → 最新」真實 migration 整合測試。
///
/// 直接以 sqflite_common_ffi 的暫存 SQLite 檔驅動 DatabaseService 的**正式**
/// onCreate/onUpgrade（透過 @visibleForTesting hook），不經過 production 平台 factory。
/// 網頁版正式也是走 ffi(web)，故此路徑與 Web/IndexedDB 的 SQLite 行為一致。
///
/// P0 root cause 回歸：production 既有 DB（oldV<10）升級時，`_createPlanItemProgressTable`
/// 已含 item_id，隨後 oldV<14 又無條件 `ALTER … ADD COLUMN item_id` →
/// `duplicate column name: item_id` → 整個 DB 初始化崩潰 → 我的標記/我的研讀全載入失敗。
void main() {
  sqfliteFfiInit();
  final svc = DatabaseService();

  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('bible_mig');
  });
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  String path() => '${tmp.path}/bible_app.db';

  /// 開一個「舊版」DB（以 [oldVersion] + 測試提供的舊 schema onCreate 建立），關閉，
  /// 再以最新版重開 → 觸發正式 onUpgrade(oldVersion → 最新)。回傳升級後的連線。
  Future<Database> upgradeFrom(
      int oldVersion, Future<void> Function(Database) oldCreate) async {
    final old = await databaseFactoryFfi.openDatabase(
      path(),
      options: OpenDatabaseOptions(
        version: oldVersion,
        onCreate: (db, _) => oldCreate(db),
      ),
    );
    await old.close();
    return databaseFactoryFfi.openDatabase(
      path(),
      options: OpenDatabaseOptions(
        version: svc.debugDbVersion,
        onCreate: (db, _) => svc.debugCreateAllTables(db),
        onUpgrade: (db, o, n) => svc.debugOnUpgrade(db, o, n),
      ),
    );
  }

  Future<Set<String>> columns(Database db, String table) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.map((r) => r['name'].toString()).toSet();
  }

  Future<int> columnCount(Database db, String table, String column) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.where((r) => r['name'].toString() == column).length;
  }

  // ---- 舊 schema 建構器（代表真實 production 歷史狀態）----

  // v9：plan_item_progress 尚未存在（v10 才加）；notes 只有 tags（v3）、無 title/refs/
  // deleted_at（v12）；prayers 只有舊 category/subcategory/content（v13 前）。
  Future<void> oldV9(Database db) async {
    await db.execute('''
      CREATE TABLE bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT, book_id INTEGER NOT NULL,
        chapter INTEGER NOT NULL, verse INTEGER NOT NULL, created_at INTEGER NOT NULL,
        UNIQUE(book_id, chapter, verse))''');
    await db.execute('''
      CREATE TABLE highlights (
        id INTEGER PRIMARY KEY AUTOINCREMENT, book_id INTEGER NOT NULL,
        chapter INTEGER NOT NULL, verse INTEGER NOT NULL, color INTEGER NOT NULL,
        created_at INTEGER NOT NULL, UNIQUE(book_id, chapter, verse))''');
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT, book_id INTEGER NOT NULL,
        chapter INTEGER NOT NULL, verse INTEGER NOT NULL, content TEXT NOT NULL,
        tags TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL)''');
    await db.execute('''
      CREATE TABLE prayers (
        id INTEGER PRIMARY KEY AUTOINCREMENT, category TEXT NOT NULL DEFAULT '',
        subcategory TEXT NOT NULL DEFAULT '', content TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''');
  }

  // v13：plan_item_progress 已存在，但為**舊 schema（無 item_id / plan_version）**，
  // 代表在 v14 之前建立此表的使用者。notes/prayers 已升到 v13 的 schema。
  Future<void> oldV13(Database db) async {
    await oldV9(db);
    await db.execute("ALTER TABLE notes ADD COLUMN title TEXT NOT NULL DEFAULT ''");
    await db.execute("ALTER TABLE notes ADD COLUMN refs TEXT NOT NULL DEFAULT ''");
    await db.execute('ALTER TABLE notes ADD COLUMN deleted_at INTEGER NOT NULL DEFAULT 0');
    await db.execute("ALTER TABLE prayers ADD COLUMN title TEXT NOT NULL DEFAULT ''");
    await db.execute('''
      CREATE TABLE plan_item_progress (
        plan_id TEXT NOT NULL, book_id INTEGER NOT NULL, chapter INTEGER NOT NULL,
        day INTEGER NOT NULL, done_at INTEGER NOT NULL,
        PRIMARY KEY(plan_id, book_id, chapter))''');
  }

  test('Case A：舊 DB（oldV<10）升級——不再 duplicate column item_id，且僅一個 item_id',
      () async {
    // 這正是 production 崩潰情境：oldV<10 建表已含 item_id，舊碼 oldV<14 再 ADD 會爆。
    final db = await upgradeFrom(9, oldV9);
    final cols = await columns(db, 'plan_item_progress');
    expect(cols, contains('item_id'));
    expect(cols, contains('plan_version'));
    expect(await columnCount(db, 'plan_item_progress', 'item_id'), 1);
    // notes / prayers 的 additive 欄位也正確補齊。
    expect(await columns(db, 'notes'),
        containsAll(['title', 'refs', 'deleted_at', 'tags']));
    expect(await columns(db, 'prayers'), contains('status'));
    await db.close();
  });

  test('Case B：舊 DB（v13，plan_item_progress 無 item_id）升級——恰好加上 item_id 一次',
      () async {
    final db = await upgradeFrom(13, oldV13);
    final cols = await columns(db, 'plan_item_progress');
    expect(cols, contains('item_id'));
    expect(cols, contains('plan_version'));
    expect(await columnCount(db, 'plan_item_progress', 'item_id'), 1);
    expect(await columnCount(db, 'plan_item_progress', 'plan_version'), 1);
    await db.close();
  });

  test('Case C：migration 重跑（再次 onUpgrade 同版本區間）安全、schema 不變、無 duplicate',
      () async {
    final db = await upgradeFrom(13, oldV13);
    // 直接重跑 v13→最新 的 upgrade（idempotent 加欄位應全部跳過）。
    await svc.debugOnUpgrade(db, 13, svc.debugDbVersion);
    await svc.debugOnUpgrade(db, 13, svc.debugDbVersion);
    expect(await columnCount(db, 'plan_item_progress', 'item_id'), 1);
    expect(await columnCount(db, 'plan_item_progress', 'plan_version'), 1);
    expect(await columnCount(db, 'notes', 'title'), 1);
    await db.close();
  });

  test('Case D：既有 Bookmarks / Highlights / Notes 資料在 migration 後仍保留', () async {
    // 先建舊 v9 並塞資料，再升級。
    final old = await databaseFactoryFfi.openDatabase(
      path(),
      options: OpenDatabaseOptions(version: 9, onCreate: (db, _) => oldV9(db)),
    );
    await old.insert('bookmarks',
        {'book_id': 43, 'chapter': 3, 'verse': 16, 'created_at': 1});
    await old.insert('highlights', {
      'book_id': 19, 'chapter': 23, 'verse': 1, 'color': 2, 'created_at': 1
    });
    await old.insert('notes', {
      'book_id': 40, 'chapter': 5, 'verse': 3, 'content': '虛心的人有福了',
      'tags': '登山寶訓', 'created_at': 1, 'updated_at': 1
    });
    await old.close();

    final db = await databaseFactoryFfi.openDatabase(
      path(),
      options: OpenDatabaseOptions(
        version: svc.debugDbVersion,
        onCreate: (db, _) => svc.debugCreateAllTables(db),
        onUpgrade: (db, o, n) => svc.debugOnUpgrade(db, o, n),
      ),
    );
    expect((await db.query('bookmarks')).length, 1);
    expect((await db.query('highlights')).length, 1);
    final notes = await db.query('notes');
    expect(notes.length, 1);
    expect(notes.first['content'], '虛心的人有福了');
    expect(notes.first['tags'], '登山寶訓');
    // 新增欄位有預設值、舊資料不受影響。
    expect(notes.first['title'], '');
    expect(notes.first['deleted_at'], 0);
    await db.close();
  });

  test('Case E：既有 plan_item_progress rows 在加 item_id 後仍保留', () async {
    final old = await databaseFactoryFfi.openDatabase(
      path(),
      options: OpenDatabaseOptions(version: 13, onCreate: (db, _) => oldV13(db)),
    );
    await old.insert('plan_item_progress', {
      'plan_id': 'oneyear', 'book_id': 1, 'chapter': 1, 'day': 1, 'done_at': 111
    });
    await old.close();

    final db = await databaseFactoryFfi.openDatabase(
      path(),
      options: OpenDatabaseOptions(
        version: svc.debugDbVersion,
        onCreate: (db, _) => svc.debugCreateAllTables(db),
        onUpgrade: (db, o, n) => svc.debugOnUpgrade(db, o, n),
      ),
    );
    final rows = await db.query('plan_item_progress');
    expect(rows.length, 1);
    expect(rows.first['plan_id'], 'oneyear');
    expect(rows.first['done_at'], 111);
    expect(rows.first['item_id'], ''); // 新欄位預設空字串
    expect(rows.first['plan_version'], 1); // 新欄位預設 1
    await db.close();
  });

  test('Case F：DB 初始化成功後，plan_item_progress 可正常查詢（下游 repository 不會卡死）',
      () async {
    // migration 成功 = db.database 不 throw = getBooks/我的標記/我的研讀能拿到連線並回本機資料。
    final db = await upgradeFrom(9, oldV9);
    // 這些查詢是我的標記/計畫頁載入時會做的；不得因 schema 壞掉而 throw。
    expect(() async => db.query('bookmarks'), returnsNormally);
    expect(() async => db.query('highlights'), returnsNormally);
    expect(() async => db.query('notes'), returnsNormally);
    final plan = await db.query('plan_item_progress');
    expect(plan, isEmpty); // 空表、能查、不崩潰
    await db.close();
  });

  test('Case G：Web/IndexedDB 等效路徑——同一 DB 重複 open 至最新版安全（無 migration 重跑崩潰）',
      () async {
    final db1 = await upgradeFrom(9, oldV9);
    await db1.close();
    // 第二次 open（版本已是最新）→ 不跑 onUpgrade、schema 穩定。
    final db2 = await databaseFactoryFfi.openDatabase(
      path(),
      options: OpenDatabaseOptions(
        version: svc.debugDbVersion,
        onCreate: (db, _) => svc.debugCreateAllTables(db),
        onUpgrade: (db, o, n) => svc.debugOnUpgrade(db, o, n),
      ),
    );
    expect(await columnCount(db2, 'plan_item_progress', 'item_id'), 1);
    await db2.close();
  });

  test('fresh install（onCreate）與升級路徑的 plan_item_progress schema 一致', () async {
    final fresh = await databaseFactoryFfi.openDatabase(
      '${tmp.path}/fresh.db',
      options: OpenDatabaseOptions(
        version: svc.debugDbVersion,
        onCreate: (db, _) => svc.debugCreateAllTables(db),
      ),
    );
    final freshCols = await columns(fresh, 'plan_item_progress');
    await fresh.close();

    final upgraded = await upgradeFrom(9, oldV9);
    final upgradedCols = await columns(upgraded, 'plan_item_progress');
    await upgraded.close();

    expect(freshCols, upgradedCols);
  });

  test('debugAddColumnIfMissing 純 idempotent：欄位已存在則跳過、不存在則加一次', () async {
    final db = await databaseFactoryFfi.openDatabase(
      '${tmp.path}/adc.db',
      options: OpenDatabaseOptions(version: 1),
    );
    await db.execute('CREATE TABLE t (a INTEGER)');
    await svc.debugAddColumnIfMissing(db, 't', 'b', 'b TEXT NOT NULL DEFAULT \'\'');
    await svc.debugAddColumnIfMissing(db, 't', 'b', 'b TEXT NOT NULL DEFAULT \'\'');
    final info = await db.rawQuery('PRAGMA table_info(t)');
    expect(info.where((r) => r['name'] == 'b').length, 1);
    await db.close();
  });
}
