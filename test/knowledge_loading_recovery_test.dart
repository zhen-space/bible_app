import 'package:bible_app/models/knowledge.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/screens/knowledge_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _loadedKnowledge = KnowledgeBase(
  parallels: [],
  types: [],
  timeline: [
    TimelineEvent(order: 1, era: '起初', title: '創造', when: '', ref: '創世記 1:1'),
  ],
  people: [
    Person(
      id: 'adam',
      name: '亞當',
      aka: [],
      bio: '第一個人',
      events: [],
      relations: [],
    ),
  ],
);

void main() {
  testWidgets('375px 知識庫首頁失敗可重試並恢復統計', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var attempts = 0;
    var shouldFail = true;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          knowledgeProvider.overrideWith((ref) async {
            attempts += 1;
            if (shouldFail) throw Exception('知識庫載入失敗');
            return _loadedKnowledge;
          }),
        ],
        child: const MaterialApp(home: KnowledgeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暫時無法載入內容。'), findsOneWidget);
    expect(find.textContaining('0 個事件'), findsNothing);
    final attemptsBeforeRetry = attempts;

    shouldFail = false;
    await tester.tap(find.text('重試'));
    await tester.pumpAndSettle();

    expect(attempts, greaterThan(attemptsBeforeRetry));
    expect(find.textContaining('1 個事件'), findsOneWidget);
    expect(find.textContaining('1 位'), findsOneWidget);
  });

  testWidgets('人物詳情載入失敗不會誤顯示找不到', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          knowledgeProvider.overrideWith(
            (ref) async => throw Exception('人物載入失敗'),
          ),
        ],
        child: const MaterialApp(home: PersonDetailScreen(personId: 'adam')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暫時無法載入內容。'), findsOneWidget);
    expect(find.text('找不到這個人物'), findsNothing);
    expect(find.text('重試'), findsOneWidget);
  });
}
