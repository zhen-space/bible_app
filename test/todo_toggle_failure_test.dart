import 'package:bible_app/models/models.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/screens/todos_screen.dart';
import 'package:bible_app/services/database_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 不碰真 DB：記憶體清單；`failOnCall` 指定第幾次 saveTodo 丟例外（模擬寫到一半儲存失敗）。
class _FlakyToggleDatabaseService extends DatabaseService {
  _FlakyToggleDatabaseService(this.rows);
  final List<Todo> rows;
  int calls = 0;
  final failOnCalls = <int>{};

  @override
  Future<int> saveTodo(Todo t) async {
    calls++;
    if (failOnCalls.contains(calls)) throw StateError('disk full');
    final i = rows.indexWhere((r) => r.id == t.id);
    rows[i] = t;
    return t.id!;
  }

  @override
  Future<List<Todo>> getTodos() async => List.of(rows);
}

Future<_FlakyToggleDatabaseService> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'todos_list_filter': 'all'});
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final db = _FlakyToggleDatabaseService([
    const Todo(id: 1, category: '靈修', content: '讀一章聖經'),
    const Todo(id: 2, category: '靈修', content: '背一節經文'),
  ]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseServiceProvider.overrideWithValue(db),
        allTodosProvider.overrideWith((ref) => db.getTodos()),
      ],
      child: const MaterialApp(home: TodosScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

void main() {
  testWidgets('375px 批次打勾寫到一半失敗：畫面反映實際狀態、提示部分完成、可重試剩餘', (tester) async {
    final db = await _pump(tester);
    db.failOnCalls.add(2); // 第 1 項寫入成功、第 2 項失敗

    await tester.tap(find.text('選取'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('讀一章聖經'));
    await tester.tap(find.text('背一節經文'));
    await tester.pump();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(db.rows.map((t) => t.done), [true, false]);
    // 畫面與資料一致：已寫入的一項顯示完成，未寫入的仍是待完成。
    expect(find.text('已完成 1 / 2 項'), findsOneWidget);
    expect(find.text('只更新了 1 / 2 項，其餘沒有變更。'), findsOneWidget);
    expect(find.text('已更新 2 項代辦'), findsNothing);
    // 保留選取模式，不假裝已完成。
    expect(find.text('取消'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, '重試'));
    await tester.pumpAndSettle();

    // 只重試剩下那一項：總共 3 次寫入，第 1 項不重複寫。
    expect(db.calls, 3);
    expect(db.rows.map((t) => t.done), [true, true]);
    expect(find.text('已完成 2 / 2 項'), findsOneWidget);
    expect(find.text('已標記為完成'), findsOneWidget);
  });

  testWidgets('375px 單項打勾失敗：不顯示已完成、勾選框維持原狀、提供重試', (tester) async {
    final db = await _pump(tester);
    db.failOnCalls.add(1);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(db.rows.every((t) => !t.done), isTrue);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isFalse);
    expect(find.text('已標記為完成'), findsNothing);
    expect(find.text('更新失敗，代辦狀態沒有變更。'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, '重試'));
    await tester.pumpAndSettle();

    expect(db.rows.first.done, isTrue);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isTrue);
    expect(find.text('已標記為完成'), findsOneWidget);
  });

  testWidgets('復原打勾失敗：提示復原失敗並可重試', (tester) async {
    final db = await _pump(tester);
    db.failOnCalls.add(2); // 打勾成功、復原第一次失敗

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SnackBarAction, '復原'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(db.rows.first.done, isTrue);
    expect(find.text('復原失敗，畫面顯示的是目前實際狀態。'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, '重試'));
    await tester.pumpAndSettle();

    expect(db.rows.first.done, isFalse);
    expect(find.text('已完成 0 / 2 項'), findsOneWidget);
  });
}
