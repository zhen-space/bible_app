import 'package:bible_app/models/models.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/screens/notes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('375px 標籤筆記載入失敗顯示錯誤，重試後恢復資料', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var attempts = 0;
    var shouldFail = true;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allNotesProvider.overrideWith((ref) async {
            attempts += 1;
            if (shouldFail) throw Exception('筆記載入失敗');
            return const [
              Note(
                id: 1,
                bookId: 1,
                chapter: 1,
                verse: 1,
                title: '起初的信心',
                content: '我的默想',
                tags: '信心',
                createdAt: 1,
                updatedAt: 1,
              ),
            ];
          }),
          booksProvider.overrideWith(
            (ref) async => const [
              Book(
                id: 1,
                name: '創世記',
                abbr: '創',
                testament: 'ot',
                chapters: [
                  ['起初神創造天地'],
                ],
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: NotesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暫時無法載入內容。'), findsOneWidget);
    await tester.tap(find.text('標籤'));
    await tester.pumpAndSettle();

    expect(find.text('暫時無法載入內容。'), findsOneWidget);
    expect(find.text('還沒有經文筆記'), findsNothing);

    final attemptsBeforeRetry = attempts;
    shouldFail = false;
    await tester.tap(find.text('重試'));
    await tester.pumpAndSettle();

    expect(attempts, greaterThan(attemptsBeforeRetry));
    expect(find.text('#信心'), findsOneWidget);
    expect(find.text('暫時無法載入內容。'), findsNothing);
  });

  testWidgets('按書卷載入失敗重試會同時重載書卷與筆記', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var bookAttempts = 0;
    var booksShouldFail = true;
    const note = Note(
      id: 1,
      bookId: 1,
      chapter: 1,
      verse: 1,
      content: '起初的默想',
      createdAt: 1,
      updatedAt: 1,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allNotesProvider.overrideWith((ref) async => const [note]),
          booksProvider.overrideWith((ref) async {
            bookAttempts += 1;
            if (booksShouldFail) throw Exception('書卷載入失敗');
            return const [
              Book(
                id: 1,
                name: '創世記',
                abbr: '創',
                testament: 'ot',
                chapters: [
                  ['起初神創造天地'],
                ],
              ),
            ];
          }),
        ],
        child: const MaterialApp(home: NotesScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('書卷'));
    await tester.pumpAndSettle();

    expect(find.text('暫時無法載入內容。'), findsOneWidget);
    final attemptsBeforeRetry = bookAttempts;
    booksShouldFail = false;
    await tester.tap(find.text('重試'));
    await tester.pumpAndSettle();

    expect(bookAttempts, greaterThan(attemptsBeforeRetry));
    expect(find.text('創世記'), findsOneWidget);
  });
}
