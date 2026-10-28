import 'package:bible_app/models/models.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/screens/search_screen.dart';
import 'package:bible_app/services/bible_repository.dart';
import 'package:bible_app/services/database_service.dart';
import 'package:bible_app/services/related_verse_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SearchBibleRepository extends BibleRepository {
  _SearchBibleRepository(this.books);

  final List<Book> books;

  @override
  Future<List<Book>> loadBooks() async => books;

  @override
  List<VerseSearchHit> searchRelated(String query, {int limit = 100}) => [
    const VerseSearchHit(
      verse: VerseRef(bookId: 1, chapter: 1, verse: 1, text: '神愛世人'),
      score: 10000,
      isExact: true,
      matchedTerms: ['神愛世人'],
    ),
  ];
}

class _SearchDatabaseService extends DatabaseService {
  @override
  Future<Map<int, HighlightColor>> getChapterHighlights(
    int bookId,
    int chapter,
  ) async => {};

  @override
  Future<Set<int>> getBookmarkedVerses(int bookId, int chapter) async => {};

  @override
  Future<Map<int, Note>> getChapterNotes(int bookId, int chapter) async => {};

  @override
  Future<Set<int>> getLaterVerses(int bookId, int chapter) async => {};

  @override
  Future<List<Bookmark>> getAllBookmarks() async => [];
}

void main() {
  testWidgets('搜尋結果可見更多按鈕可由語意操作建立經文筆記', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final books = [
      const Book(
        id: 1,
        name: '約翰福音',
        abbr: '約',
        testament: 'nt',
        chapters: [
          ['神愛世人'],
        ],
      ),
    ];
    final bible = _SearchBibleRepository(books);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bibleRepositoryProvider.overrideWithValue(bible),
          booksProvider.overrideWith((ref) async => books),
          databaseServiceProvider.overrideWithValue(_SearchDatabaseService()),
          authorizedStudyContentProvider.overrideWith((ref) async => const []),
          publishedQuestionsProvider('').overrideWith((ref) async => const []),
          allBookmarksProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: SearchScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '神愛世人');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    final result = find.descendant(
      of: find.byType(ListTile),
      matching: find.text('神愛世人'),
    );
    expect(result, findsOneWidget);

    final moreButton = find.byTooltip('更多經文操作');
    expect(moreButton, findsOneWidget);
    expect(find.bySemanticsLabel('更多經文操作'), findsOneWidget);

    await tester.tap(moreButton);
    await tester.pumpAndSettle();
    expect(find.text('筆記'), findsOneWidget);
    expect(find.text('稍後讀'), findsOneWidget);
    expect(find.text('分享'), findsOneWidget);
    expect(find.text('在經文中閱讀'), findsOneWidget);

    await tester.tap(find.text('筆記'));
    await tester.pumpAndSettle();
    expect(find.text('約翰福音 1:1 筆記'), findsOneWidget);
    expect(find.text('儲存'), findsOneWidget);
  });

  testWidgets('書籤狀態失敗不阻斷搜尋結果且可重試恢復', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const books = [
      Book(
        id: 1,
        name: '約翰福音',
        abbr: '約',
        testament: 'nt',
        chapters: [
          ['神愛世人'],
        ],
      ),
    ];
    var bookmarkAttempts = 0;
    var failBookmarks = true;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bibleRepositoryProvider.overrideWithValue(
            _SearchBibleRepository(books),
          ),
          booksProvider.overrideWith((ref) async => books),
          databaseServiceProvider.overrideWithValue(_SearchDatabaseService()),
          authorizedStudyContentProvider.overrideWith((ref) async => const []),
          publishedQuestionsProvider('').overrideWith((ref) async => const []),
          allBookmarksProvider.overrideWith((ref) async {
            bookmarkAttempts++;
            if (failBookmarks) throw Exception('offline');
            return const [
              Bookmark(bookId: 1, chapter: 1, verse: 1, createdAt: 1),
            ];
          }),
        ],
        child: const MaterialApp(home: SearchScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '神愛世人');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(ListTile), matching: find.text('神愛世人')),
      findsOneWidget,
    );
    expect(find.text('書籤狀態暫時無法載入'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<Dismissible>(find.byType(Dismissible)).direction,
      DismissDirection.startToEnd,
    );

    final attemptsBeforeRetry = bookmarkAttempts;
    failBookmarks = false;
    await tester.tap(find.widgetWithText(TextButton, '重試'));
    await tester.pumpAndSettle();

    expect(bookmarkAttempts, greaterThan(attemptsBeforeRetry));
    expect(find.text('書籤狀態暫時無法載入'), findsNothing);
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    expect(
      tester.widget<Dismissible>(find.byType(Dismissible)).direction,
      DismissDirection.horizontal,
    );
  });
}
