import 'package:bible_app/models/private_study.dart';
import 'package:bible_app/screens/private_study_screen.dart';
import 'package:bible_app/services/database_service.dart';
import 'package:bible_app/services/private_study_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestPrivateStudyRepository extends PrivateStudyRepository {
  _TestPrivateStudyRepository() : super(DatabaseService());

  @override
  Future<void> syncCurrentUser() async {}
}

void main() {
  testWidgets('375px 全部筆記錯誤不隱藏入口，重試後恢復數量', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var attempts = 0;
    var shouldFail = true;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          privateStudyRepositoryProvider.overrideWithValue(
            _TestPrivateStudyRepository(),
          ),
          privateStudyBooksProvider.overrideWith(
            (ref) async => const [
              PrivateStudyBook(
                id: 'book-1',
                title: '我的第一本書',
                createdAt: 1,
                updatedAt: 1,
                lastStudiedAt: 1,
              ),
            ],
          ),
          privateStudyAllNotesProvider.overrideWith((ref) async {
            attempts += 1;
            if (shouldFail) throw Exception('私人研讀筆記載入失敗');
            return const [
              PrivateStudyNote(
                id: 'note-1',
                bookId: 'book-1',
                quote: '一段重要的話',
                topics: ['經文'],
                createdAt: 1,
                updatedAt: 1,
              ),
            ];
          }),
        ],
        child: const MaterialApp(home: PrivateStudyHomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('我的第一本書'), findsOneWidget);
    expect(find.text('研讀筆記暫時無法載入。'), findsOneWidget);
    expect(find.text('主題分類'), findsNothing);

    final attemptsBeforeRetry = attempts;
    shouldFail = false;
    await tester.tap(find.text('重試'));
    await tester.pumpAndSettle();

    expect(attempts, greaterThan(attemptsBeforeRetry));
    expect(find.text('我的第一本書'), findsOneWidget);
    expect(find.text('主題分類'), findsOneWidget);
    expect(find.text('1 則筆記'), findsOneWidget);
  });
}
