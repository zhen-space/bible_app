import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// 手機/桌面版：sqflite 原生實作。
DatabaseFactory get dbFactory => databaseFactory;

Future<String> resolveDbPath(String dbName) async {
  return join(await getDatabasesPath(), dbName);
}
