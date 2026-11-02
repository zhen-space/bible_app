import 'package:bible_app/models/models.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/screens/todos_screen.dart';
import 'package:bible_app/services/database_service.dart';
import 'package:bible_app/widgets/student_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 不碰真 DB：記憶體清單；`failOnCalls` 指定第幾次 deleteTodo 丟例外（模擬刪到一半儲存失敗）。
class _FlakyDeleteDatabaseService extends DatabaseService {
  _FlakyDeleteDatabaseService(this.rows);
  final List<Todo> rows;
  int calls = 0;
  final deletedIds = <int>[];
  final failOnCalls = <int>{};

  @override
  Future<void> deleteTodo(int id) async {
    calls++;
    if (failOnCalls.contains(calls)) throw StateError('disk full');
    rows.removeWhere((r) => r.id == id);
    deletedIds.add(id);
  }

  @override
  Future<List<Todo>> getTodos() async => List.of(rows);
}

Future<_FlakyDeleteDatabaseService> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'todos_list_filter': 'all'});
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final db = _FlakyDeleteDatabaseService([
    const Todo(id: 1, category: '靈修', content: '讀一章聖經'),
    const Todo(id: 2, category: '靈修', content: '背一節經文'),
    const Todo(id: 3, category: '禱告', content: '為家人禱告'),
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

Future<void> _confirmDelete(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, '刪除'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('375px 批次刪除到一半失敗：畫面保留未刪項目、提示部分完成、只重試剩餘', (tester) async {
    final db = await _pump(tester);
    db.failOnCalls.add(2); // 第 1 項刪除成功、第 2 項失敗

    await tester.tap(find.text('選取'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('讀一章聖經'));
    await tester.tap(find.text('背一節經文'));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(StudentBatchActionBar),
        matching: find.text('刪除'),
      ),
    );
    await tester.pumpAndSettle();
    await _confirmDelete(tester);

    expect(tester.takeException(), isNull);
    expect(db.deletedIds, [1]);
    // 畫面與資料一致：已刪的不見，未刪的仍在。
    expect(find.text('讀一章聖經'), findsNothing);
    expect(find.text('背一節經文'), findsOneWidget);
    expect(find.text('已完成 0 / 2 項'), findsOneWidget);
    expect(find.text('只刪除了 1 / 2 項，其餘仍保留。'), findsOneWidget);
    // 保留選取模式，未刪的那項仍被選取。
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('已選 1 項'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, '重試'));
    await tester.pumpAndSettle();

    // 重試不再跳確認框，只刪剩下那一項（總共 3 次呼叫，第 1 項不重刪、第 3 項不誤刪）。
    expect(find.byType(AlertDialog), findsNothing);
    expect(db.calls, 3);
    expect(db.deletedIds, [1, 2]);
    expect(find.text('背一節經文'), findsNothing);
    expect(find.text('為家人禱告'), findsOneWidget);
    expect(find.text('取消'), findsNothing);
  });

  testWidgets('375px 滑動刪除失敗：列回彈仍在、提示失敗、重試成功', (tester) async {
    final db = await _pump(tester);
    db.failOnCalls.add(1);

    await tester.drag(find.text('讀一章聖經'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await _confirmDelete(tester);

    expect(tester.takeException(), isNull);
    expect(db.rows, hasLength(3));
    expect(find.text('讀一章聖經'), findsOneWidget);
    expect(find.text('刪除失敗，代辦仍保留。'), findsOneWidget);
    // 失敗提示要能被讀屏念出且有可操作的重試。
    final retry = tester
        .getSemantics(find.widgetWithText(SnackBarAction, '重試'))
        .getSemanticsData();
    expect(retry.label, '重試');
    expect(retry.hasAction(SemanticsAction.tap), isTrue);

    await tester.tap(find.widgetWithText(SnackBarAction, '重試'));
    await tester.pumpAndSettle();

    expect(db.deletedIds, [1]);
    expect(find.text('讀一章聖經'), findsNothing);
    expect(find.text('已完成 0 / 2 項'), findsOneWidget);
  });
}
