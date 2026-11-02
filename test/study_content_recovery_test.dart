import 'package:bible_app/models/study_content.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/screens/study_content_screen.dart';
import 'package:flutter/material.dart' hide Visibility;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('研讀內容載入失敗可重試，不會假裝成空資料', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authorizedStudyContentProvider.overrideWith((ref) async {
            attempts++;
            throw Exception('offline');
          }),
        ],
        child: const MaterialApp(home: StudentStudyContentScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('研讀內容暫時載入失敗。'), findsOneWidget);
    expect(find.text('重試'), findsOneWidget);
    expect(find.text('目前尚無已發布的研讀內容。'), findsNothing);

    final beforeRetry = attempts;
    await tester.tap(find.text('重試'));
    await tester.pumpAndSettle();
    expect(attempts, greaterThan(beforeRetry));
  });

  testWidgets('主題載入失敗可重試', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authorizedTopicsProvider.overrideWith((ref) async {
            attempts++;
            throw Exception('offline');
          }),
        ],
        child: const MaterialApp(home: StudentTopicsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('主題暫時載入失敗。'), findsOneWidget);
    final beforeRetry = attempts;
    await tester.tap(find.text('重試'));
    await tester.pumpAndSettle();
    expect(attempts, greaterThan(beforeRetry));
  });

  testWidgets('主題內容載入失敗可重試', (tester) async {
    var attempts = 0;
    const topic = StudyTopic(
      id: 'hope',
      title: '盼望',
      status: ContentStatus.published,
      visibility: Visibility.student,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authorizedStudyContentByTopicProvider.overrideWith((ref, id) async {
            attempts++;
            throw Exception('offline');
          }),
        ],
        child: const MaterialApp(home: StudentTopicContentScreen(topic: topic)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('主題研讀內容暫時載入失敗。'), findsOneWidget);
    final beforeRetry = attempts;
    await tester.tap(find.text('重試'));
    await tester.pumpAndSettle();
    expect(attempts, greaterThan(beforeRetry));
  });

  testWidgets('已儲存內容載入失敗可重試', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          resolvedSavedStudyContentProvider.overrideWith((ref) async {
            attempts++;
            throw Exception('offline');
          }),
        ],
        child: const MaterialApp(home: SavedStudyContentScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已儲存的研讀內容暫時載入失敗。'), findsOneWidget);
    final beforeRetry = attempts;
    await tester.tap(find.text('重試'));
    await tester.pumpAndSettle();
    expect(attempts, greaterThan(beforeRetry));
  });

  testWidgets('真正空資料仍顯示原本引導，不出現重試', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authorizedStudyContentProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: StudentStudyContentScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('目前尚無已發布的研讀內容。'), findsOneWidget);
    expect(find.text('重試'), findsNothing);
  });
}
