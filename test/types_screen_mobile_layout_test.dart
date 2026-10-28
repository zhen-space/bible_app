import 'package:bible_app/models/knowledge.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/screens/knowledge_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('375px 長節位預表與應驗可換行且仍可點擊', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const otRef = '以賽亞書 53:4-6（受苦僕人）';
    const ntRef = '馬太福音 8:16-17（耶穌醫治）';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          knowledgeProvider.overrideWith(
            (ref) async => const KnowledgeBase(
              parallels: [],
              timeline: [],
              people: [],
              types: [
                TypeFulfillment(
                  title: '担當疾病',
                  otRef: otRef,
                  ntRef: ntRef,
                  note: '',
                ),
              ],
            ),
          ),
        ],
        child: const MaterialApp(home: TypesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('預表 $otRef'), findsOneWidget);
    expect(find.text('應驗 $ntRef'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    final chips = tester
        .widgetList<ActionChip>(find.byType(ActionChip))
        .toList();
    expect(chips, hasLength(2));
    expect(chips.every((chip) => chip.onPressed != null), isTrue);
  });
}
