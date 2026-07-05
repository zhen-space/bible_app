import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// 網頁版：SQLite 編譯成 WASM，資料存在瀏覽器 IndexedDB。
/// 需要 web/sqlite3.wasm 與 web/sqflite_sw.js（Render 建置腳本會準備）。
DatabaseFactory get dbFactory => databaseFactoryFfiWeb;

Future<String> resolveDbPath(String dbName) async => dbName;
