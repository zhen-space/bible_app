import 'dart:async';

import 'package:bible_app/models/models.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/screens/chapter_screen.dart';
import 'package:bible_app/screens/search_screen.dart';
import 'package:bible_app/screens/student_home_screen.dart';
import 'package:bible_app/services/bible_repository.dart';
import 'package:bible_app/services/related_verse_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_notes_db.dart';

/// 共用單節面板（`showVerseActionSheet`）的螢光筆／書籤寫入失敗，從真實入口進：
/// 搜尋結果「更多經文操作」與首頁「每日經文」卡的「…」。
/// 失敗時畫面回到實際儲存的狀態、SnackBar（螢幕閱讀器會念）＋「重試」寫同一個目標狀態；
/// 關面板中的連點、寫入進行中再開面板、讀取中連點入口都不會重複寫入或多開一層。

const _books = [
  Book(
    id: 1,
    name: '約翰福音',
    abbr: '約',
    testament: 'nt',
    chapters: [
      ['神愛世人，甚至將他的獨生子賜給他們。', '因為神差他的兒子降世。'],
    ],
  ),
];

const _key = '1:1:1';

class _SearchBible extends BibleRepository {
  @override
  Future<List<Book>> loadBooks() async => _books;

  @override
  String? english(int bookId, int chapter, int verse) => null;

  @override
  List<VerseSearchHit> searchRelated(String query, {int limit = 100}) => [
    VerseSearchHit(
      verse: VerseRef(
        bookId: 1,
        chapter: 1,
        verse: 1,
        text: _books[0].chapters[0][0],
      ),
      score: 10000,
      isExact: true,
      matchedTerms: const ['神愛世人'],
    ),
  ];
}

void _phone(WidgetTester tester) {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpSearch(WidgetTester tester, FakeNotesDb db) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bibleRepositoryProvider.overrideWithValue(_SearchBible()),
        booksProvider.overrideWith((ref) async => _books),
        databaseServiceProvider.overrideWithValue(db),
        authorizedStudyContentProvider.overrideWith((ref) async => const []),
        publishedQuestionsProvider('').overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: SearchScreen()),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, '神愛世人');
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
}

Future<void> _openSearchMore(WidgetTester tester) async {
  await tester.tap(find.byTooltip('更多經文操作'));
  await tester.pumpAndSettle();
}

Future<void> _pumpHome(WidgetTester tester, FakeNotesDb db) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        booksProvider.overrideWith((ref) async => _books),
        databaseServiceProvider.overrideWithValue(db),
        publishedDailyVerseProvider.overrideWith(
          (ref) async =>
              (bookId: 1, chapter: 1, verse: 1, title: '', content: ''),
        ),
        dailyVerseProvider.overrideWith(
          (ref) async => VerseRef(
            bookId: 1,
            chapter: 1,
            verse: 1,
            text: _books[0].chapters[0][0],
          ),
        ),
        readingPlanTodayProvider.overrideWith((ref) async => null),
        churchOnboardingVisibleProvider.overrideWith((ref) async => false),
      ],
      child: const MaterialApp(home: Scaffold(body: StudentHomeScreen())),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openDailyMore(WidgetTester tester) async {
  final more = find.byTooltip('螢光筆／書籤／筆記／分享');
  await tester.scrollUntilVisible(
    more,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(more);
  await tester.pumpAndSettle();
}

/// 面板是否開著（「在經文中閱讀」只在面板裡）。
Finder get _sheet => find.text('在經文中閱讀');

Finder get _retry => find.widgetWithText(SnackBarAction, '重試');

void _expectAnnounced(WidgetTester tester, String message) {
  expect(find.text(message), findsOneWidget);
  expect(find.bySemanticsLabel(message), findsOneWidget);
  expect(
    tester
        .getSemantics(_retry)
        .getSemanticsData()
        .hasAction(SemanticsAction.tap),
    isTrue,
    reason: '重試要能用螢幕閱讀器操作',
  );
}

Future<void> _closeSheet(WidgetTester tester) async {
  await tester.tapAt(const Offset(10, 10));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('375px 搜尋入口：加入書籤失敗 → 畫面仍是未加入、可重試且只加一次', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final db = FakeNotesDb([])..failMarkCalls.add(1);
    await _pumpSearch(tester, db);
    await _openSearchMore(tester);

    await tester.tap(find.text('書籤'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_sheet, findsNothing);
    expect(find.byType(SearchScreen), findsOneWidget);
    _expectAnnounced(tester, '加入書籤失敗，這節沒有加入書籤。');
    expect(db.bookmarks, isEmpty);
    expect(find.bySemanticsLabel(RegExp('已加入書籤')), findsNothing);

    // 再開面板：顯示實際狀態（仍是「書籤」）
    await _openSearchMore(tester);
    expect(find.text('書籤'), findsOneWidget);
    expect(find.text('移除書籤'), findsNothing);
    await _closeSheet(tester);

    await tester.tap(_retry);
    await tester.pumpAndSettle();
    expect(db.bookmarks, {_key});
    expect(db.log, ['bookmark true', 'bookmark true']);
    expect(find.bySemanticsLabel(RegExp('已加入書籤')), findsOneWidget);
    expect(db.log, isNot(contains('legacy toggleBookmark')));
    handle.dispose();
  });

  testWidgets('375px 搜尋入口：移除書籤失敗 → 書籤仍在；重試寫目標狀態、不會翻回去', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final db = FakeNotesDb([])
      ..bookmarks.add(_key)
      ..failMarkCalls.add(1);
    await _pumpSearch(tester, db);
    expect(find.bySemanticsLabel(RegExp('已加入書籤')), findsOneWidget);
    await _openSearchMore(tester);

    await tester.tap(find.text('移除書籤'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    _expectAnnounced(tester, '移除書籤失敗，書籤仍保留。');
    expect(db.bookmarks, {_key});
    expect(find.bySemanticsLabel(RegExp('已加入書籤')), findsOneWidget);

    // 失敗後在別處已被移除：重試仍寫「不在書籤」，不會把它加回來
    db.bookmarks.clear();
    await tester.tap(_retry);
    await tester.pumpAndSettle();
    expect(db.bookmarks, isEmpty);
    expect(db.log, ['bookmark false', 'bookmark false']);
    expect(find.bySemanticsLabel(RegExp('已加入書籤')), findsNothing);
    handle.dispose();
  });

  testWidgets('375px 搜尋入口：加螢光筆失敗與移除螢光筆失敗都回到實際狀態並可重試', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final db = FakeNotesDb([])..failMarkCalls.addAll({1, 3});
    await _pumpSearch(tester, db);
    await _openSearchMore(tester);

    final yellow = find.bySemanticsLabel('螢光筆 黃色');
    expect(yellow, findsOneWidget);
    expect(
      tester
          .getSemantics(yellow)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    await tester.tap(yellow);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    _expectAnnounced(tester, '加上螢光筆失敗，經文沒有標記。');
    expect(db.highlights, isEmpty);

    await tester.tap(_retry);
    await tester.pumpAndSettle();
    expect(db.highlights, {_key: HighlightColor.yellow});

    // 移除失敗：螢光筆仍在，面板顯示仍有黃色與「移除螢光筆」
    await _openSearchMore(tester);
    expect(
      tester.getSemantics(find.bySemanticsLabel('螢光筆 黃色')),
      containsSemantics(isSelected: true),
    );
    await tester.tap(find.byTooltip('移除螢光筆'));
    await tester.pumpAndSettle();
    _expectAnnounced(tester, '移除螢光筆失敗，螢光筆仍保留。');
    expect(db.highlights, {_key: HighlightColor.yellow});
    await _openSearchMore(tester);
    expect(find.byTooltip('移除螢光筆'), findsOneWidget);
    await _closeSheet(tester);

    await tester.tap(_retry);
    await tester.pumpAndSettle();
    expect(db.highlights, isEmpty);
    expect(db.log, [
      'highlight yellow',
      'highlight yellow',
      'highlight null',
      'highlight null',
    ]);
    handle.dispose();
  });

  testWidgets('375px 搜尋入口：關面板中連點、寫入中再開面板都不會重複寫或多 pop 一層', (tester) async {
    _phone(tester);
    final db = FakeNotesDb([])..markGate = Completer<void>();
    await _pumpSearch(tester, db);
    await _openSearchMore(tester);

    final bookmark = find.text('書籤');
    await tester.tap(bookmark);
    await tester.tap(bookmark, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(db.log, ['bookmark true'], reason: '只寫一次');
    expect(find.byType(SearchScreen), findsOneWidget, reason: '沒有多 pop 一層');
    expect(_sheet, findsNothing);

    // 寫入還在進行：再開面板，書籤按鈕停用，點了也不會再寫
    await _openSearchMore(tester);
    expect(_sheet, findsOneWidget);
    await tester.tap(find.text('書籤'));
    await tester.pumpAndSettle();
    expect(db.log, ['bookmark true']);
    expect(_sheet, findsOneWidget, reason: '停用的按鈕不會關面板');
    await _closeSheet(tester);

    db.markGate!.complete();
    await tester.pumpAndSettle();
    expect(db.bookmarks, {_key});
    expect(find.bySemanticsLabel(RegExp('已加入書籤')), findsOneWidget);
    await _openSearchMore(tester);
    expect(find.text('移除書籤'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('375px 搜尋入口：讀取個人標記中連點「更多」只開一個面板', (tester) async {
    _phone(tester);
    final db = FakeNotesDb([]);
    await _pumpSearch(tester, db);

    await tester.tap(find.byTooltip('更多經文操作'));
    await tester.tap(find.byTooltip('更多經文操作'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(_sheet, findsOneWidget);

    await _closeSheet(tester);
    expect(_sheet, findsNothing);
    expect(find.byType(SearchScreen), findsOneWidget);
    // 關掉後可以再開
    await _openSearchMore(tester);
    expect(_sheet, findsOneWidget);
  });

  testWidgets('375px 每日經文入口：加入書籤失敗可重試；仍在首頁、不動閱讀位置', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final db = FakeNotesDb([])..failMarkCalls.add(1);
    await _pumpHome(tester, db);
    await _openDailyMore(tester);

    await tester.tap(find.text('書籤'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    _expectAnnounced(tester, '加入書籤失敗，這節沒有加入書籤。');
    expect(db.bookmarks, isEmpty);
    await _openDailyMore(tester);
    expect(find.text('書籤'), findsOneWidget);
    await _closeSheet(tester);

    await tester.tap(_retry);
    await tester.pumpAndSettle();
    expect(db.bookmarks, {_key});
    await _openDailyMore(tester);
    expect(find.text('移除書籤'), findsOneWidget);
    await _closeSheet(tester);

    expect(find.byType(ChapterScreen), findsNothing);
    expect(find.byType(StudentHomeScreen), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(StudentHomeScreen)),
    );
    expect(container.read(lastReadProvider), isNull);
    handle.dispose();
  });

  testWidgets('375px 每日經文入口：換螢光筆顏色失敗 → 仍是原色，重試換成新色', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final db = FakeNotesDb([])
      ..highlights[_key] = HighlightColor.green
      ..failMarkCalls.add(1);
    await _pumpHome(tester, db);
    await _openDailyMore(tester);

    await tester.tap(find.bySemanticsLabel('螢光筆 藍色'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    _expectAnnounced(tester, '更換螢光筆失敗，顏色沒有變更。');
    expect(db.highlights, {_key: HighlightColor.green});

    await _openDailyMore(tester);
    expect(
      tester.getSemantics(find.bySemanticsLabel('螢光筆 綠色')),
      containsSemantics(isSelected: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('螢光筆 藍色')),
      containsSemantics(isSelected: false),
    );
    await _closeSheet(tester);

    await tester.tap(_retry);
    await tester.pumpAndSettle();
    expect(db.highlights, {_key: HighlightColor.blue});
    expect(db.log, ['highlight blue', 'highlight blue']);
    handle.dispose();
  });
}
