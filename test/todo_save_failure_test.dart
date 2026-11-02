import 'package:bible_app/models/models.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/screens/todos_screen.dart';
import 'package:bible_app/services/database_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 不碰真 DB：第一次寫入丟例外（模擬儲存空間滿／IndexedDB 被擋），之後成功。
class _FlakyTodoDatabaseService extends DatabaseService {
  int failuresLeft = 1;
  final saved = <Todo>[];

  @override
  Future<int> saveTodo(Todo t) async {
    if (failuresLeft > 0) {
      failuresLeft--;
      throw StateError('disk full');
    }
    saved.add(t);
    return saved.length;
  }

  @override
  Future<List<Todo>> getTodos() async => [
    for (var i = 0; i < saved.length; i++)
      Todo(id: i + 1, category: saved[i].category, content: saved[i].content),
  ];
}

void main() {
  testWidgets('375px 新增代辦寫入失敗：輸入保留、顯示錯誤，重試成功才關閉', (tester) async {
    SharedPreferences.setMockInitialValues({'todos_list_filter': 'all'});
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = _FlakyTodoDatabaseService();
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

    await tester.tap(find.byTooltip('新增代辦'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '要做的事'), '為家人禱告');
    await tester.enterText(find.widgetWithText(TextField, '分類'), '禱告');
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await tester.pumpAndSettle();

    // 失敗：sheet 仍在、文字仍在、明確提示，且按鈕變成重試。
    expect(tester.takeException(), isNull);
    expect(db.saved, isEmpty);
    expect(find.text('新增代辦'), findsWidgets);
    expect(find.text('為家人禱告'), findsOneWidget);
    expect(find.text('儲存失敗，內容仍保留，請再試一次。'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '重試儲存'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '重試儲存'));
    await tester.pumpAndSettle();

    // 重試成功：只寫入一次、sheet 關閉、清單出現新代辦。
    expect(db.saved, hasLength(1));
    expect(db.saved.single.content, '為家人禱告');
    expect(db.saved.single.category, '禱告');
    expect(find.text('儲存失敗，內容仍保留，請再試一次。'), findsNothing);
    expect(find.widgetWithText(FilledButton, '重試儲存'), findsNothing);
    expect(find.text('為家人禱告'), findsOneWidget);
    expect(find.text('全部 1'), findsOneWidget);
  });
}
