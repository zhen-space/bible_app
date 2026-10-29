import 'package:bible_app/models/models.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/screens/todos_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('375px 篩選無結果可一鍵清除並回到全部代辦', (tester) async {
    SharedPreferences.setMockInitialValues({'todos_list_filter': 'completed'});
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allTodosProvider.overrideWith(
            (ref) async => const [
              Todo(id: 1, category: '靈修', content: '讀一章聖經'),
            ],
          ),
        ],
        child: const MaterialApp(home: TodosScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('還沒有已完成的代辦'), findsOneWidget);
    expect(find.text('讀一章聖經'), findsNothing);

    await tester.tap(find.text('清除篩選'));
    await tester.pumpAndSettle();

    expect(find.text('讀一章聖經'), findsOneWidget);
    expect(find.text('還沒有已完成的代辦'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('todos_list_filter'), 'all');
  });
}
