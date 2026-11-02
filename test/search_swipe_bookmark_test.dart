import 'dart:async';

import 'package:bible_app/models/models.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/screens/search_screen.dart';
import 'package:bible_app/services/bible_repository.dart';
import 'package:bible_app/services/related_verse_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_notes_db.dart';

/// 搜尋結果列「左滑書籤」（精確結果與相關經文兩條路徑）：寫目標狀態、失敗回到實際儲存
/// 的狀態＋可朗讀的錯誤與不會反轉的「重試」、滑動動畫中／連續滑動不重複寫入；
/// 搜尋字詞（含注音組字輸入）、結果與捲動位置都保留。

// 第 1 節是精確結果，其餘是相關經文；節數多一點讓清單可以捲動。
final _verses = [for (var i = 1; i <= 14; i++) '神愛世人第$i節'];

final _books = [
  Book(id: 1, name: '約翰福音', abbr: '約', testament: 'nt', chapters: [_verses]),
];

String _key(int verse) => '1:1:$verse';

class _SearchBible extends BibleRepository {
  @override
  Future<List<Book>> loadBooks() async => _books;

  @override
  List<VerseSearchHit> searchRelated(String query, {int limit = 100}) => [
    for (var i = 1; i <= _verses.length; i++)
      VerseSearchHit(
        verse: VerseRef(bookId: 1, chapter: 1, verse: i, text: _verses[i - 1]),
        score: 10000.0 - i,
        isExact: i == 1,
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

Finder get _field => find.byType(TextField).first;

/// 用注音輸入法打「神愛世人」：先有組字中的注音，再選字確定，最後按搜尋。
Future<void> _pumpAndSearchWithIme(WidgetTester tester, FakeNotesDb db) async {
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
  await tester.showKeyboard(_field);
  tester.testTextInput.updateEditingValue(
    const TextEditingValue(
      text: '神愛ㄕˋ',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 2, end: 4),
    ),
  );
  await tester.pump();
  tester.testTextInput.updateEditingValue(
    const TextEditingValue(
      text: '神愛世人',
      selection: TextSelection.collapsed(offset: 4),
    ),
  );
  await tester.pump();
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
}

/// 搜尋結果清單的捲動區（AppBar 裡的搜尋框也有自己的 Scrollable，要避開）。
Finder get _results => find
    .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
    .first;

Finder _row(int verse) => find.text(_verses[verse - 1]);

Future<void> _swipeLeft(WidgetTester tester, int verse) async {
  await tester.drag(_row(verse), const Offset(-300, 0));
  await tester.pumpAndSettle();
}

/// 這一列有沒有顯示「已加入書籤」。
bool _rowBookmarked(WidgetTester tester, int verse) => find
    .descendant(
      of: find.ancestor(of: _row(verse), matching: find.byType(ListTile)),
      matching: find.byIcon(Icons.bookmark),
    )
    .evaluate()
    .isNotEmpty;

Finder get _retry => find.widgetWithText(SnackBarAction, '重試');

void _expectAnnouncedWithRetry(WidgetTester tester, String message) {
  expect(find.text(message), findsOneWidget);
  expect(find.bySemanticsLabel(message), findsOneWidget);
  expect(
    tester
        .getSemantics(_retry)
        .getSemanticsData()
        .hasAction(SemanticsAction.tap),
    isTrue,
  );
}

void _expectSearchKept(WidgetTester tester) {
  expect(tester.widget<TextField>(_field).controller!.text, '神愛世人');
  expect(find.text('相關經文（13）'), findsOneWidget);
}

void main() {
  testWidgets('375px 精確結果左滑加入書籤失敗 → 列回到未加入、可朗讀錯誤；重試只加一次', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final db = FakeNotesDb([])..failMarkCalls.add(1);
    await _pumpAndSearchWithIme(tester, db);
    expect(_rowBookmarked(tester, 1), isFalse);

    await _swipeLeft(tester, 1);

    expect(tester.takeException(), isNull, reason: '錯誤不會丟回 confirmDismiss');
    _expectAnnouncedWithRetry(tester, '加入書籤失敗，這節沒有加入書籤。');
    expect(db.bookmarks, isEmpty);
    expect(_row(1), findsOneWidget, reason: '列回彈、沒被移走');
    expect(_rowBookmarked(tester, 1), isFalse);
    _expectSearchKept(tester);

    await tester.tap(_retry);
    await tester.pumpAndSettle();
    expect(db.bookmarks, {_key(1)});
    expect(db.log, ['bookmark true', 'bookmark true']);
    expect(_rowBookmarked(tester, 1), isTrue);
    expect(find.bySemanticsLabel(RegExp('已加入書籤')), findsWidgets);
    expect(find.text('已加入書籤'), findsOneWidget, reason: '成功提示');
    expect(db.log, isNot(contains('legacy toggleBookmark')));
    _expectSearchKept(tester);
    handle.dispose();
  });

  testWidgets('375px 相關經文左滑移除書籤失敗 → 書籤仍在；重試寫「移除」不會加回來', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final db = FakeNotesDb([])
      ..bookmarks.add(_key(2))
      ..failMarkCalls.add(1);
    await _pumpAndSearchWithIme(tester, db);
    expect(_rowBookmarked(tester, 2), isTrue);

    await _swipeLeft(tester, 2);

    expect(tester.takeException(), isNull);
    _expectAnnouncedWithRetry(tester, '移除書籤失敗，書籤仍保留。');
    expect(db.bookmarks, {_key(2)});
    expect(_rowBookmarked(tester, 2), isTrue);

    // 失敗後在別處已經移除：重試仍寫「不在書籤」，不會因切換而加回來。
    db.bookmarks.clear();
    await tester.tap(_retry);
    await tester.pumpAndSettle();
    expect(db.bookmarks, isEmpty);
    expect(db.log, ['bookmark false', 'bookmark false']);
    expect(_rowBookmarked(tester, 2), isFalse);
    expect(find.text('已移除書籤'), findsOneWidget);
    _expectSearchKept(tester);
    handle.dispose();
  });

  testWidgets('375px 寫入中連續左滑同一列只寫一次；完成後再滑依實際狀態寫相反目標', (tester) async {
    _phone(tester);
    final db = FakeNotesDb([])..markGate = Completer<void>();
    await _pumpAndSearchWithIme(tester, db);

    // 第一次滑動：寫入卡住中（列停在滑開的位置等待）
    await tester.drag(_row(1), const Offset(-300, 0));
    await tester.pump(const Duration(milliseconds: 400));
    // 動畫／等待中再滑兩次
    await tester.drag(_row(1), const Offset(-300, 0), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.drag(_row(1), const Offset(-300, 0), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(db.log, ['bookmark true'], reason: '寫入中不重複寫');

    db.markGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(db.log, ['bookmark true']);
    expect(db.bookmarks, {_key(1)});
    expect(_rowBookmarked(tester, 1), isTrue);

    // 狀態已更新：再滑就是移除（依實際狀態，而非切換）
    db.markGate = null;
    await _swipeLeft(tester, 1);
    expect(db.log, ['bookmark true', 'bookmark false']);
    expect(db.bookmarks, isEmpty);
    expect(_rowBookmarked(tester, 1), isFalse);
    _expectSearchKept(tester);
  });

  testWidgets('375px 捲動後在下方的相關經文失敗與重試：捲動位置與結果都保留', (tester) async {
    _phone(tester);
    final db = FakeNotesDb([])..failMarkCalls.add(1);
    await _pumpAndSearchWithIme(tester, db);

    await tester.scrollUntilVisible(_row(12), 200, scrollable: _results);
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(_results);
    final before = scrollable.position.pixels;
    expect(before, greaterThan(0));

    await _swipeLeft(tester, 12);
    expect(find.text('加入書籤失敗，這節沒有加入書籤。'), findsOneWidget);
    expect(scrollable.position.pixels, before);
    expect(_row(12), findsOneWidget);

    await tester.tap(_retry);
    await tester.pumpAndSettle();
    expect(db.bookmarks, {_key(12)});
    expect(scrollable.position.pixels, before);
    expect(_rowBookmarked(tester, 12), isTrue);
    // 捲回頂端：字詞與整份結果都還在（沒有被重新搜尋或清掉）
    scrollable.position.jumpTo(0);
    await tester.pumpAndSettle();
    _expectSearchKept(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('375px 兩列各自滑動：一列失敗不影響另一列，重試只補失敗那列', (tester) async {
    _phone(tester);
    final db = FakeNotesDb([])..failMarkCalls.add(2);
    await _pumpAndSearchWithIme(tester, db);

    await _swipeLeft(tester, 1); // 精確結果：成功
    await _swipeLeft(tester, 3); // 相關經文：失敗
    expect(db.bookmarks, {_key(1)});
    expect(find.text('加入書籤失敗，這節沒有加入書籤。'), findsOneWidget);
    expect(_rowBookmarked(tester, 1), isTrue);
    expect(_rowBookmarked(tester, 3), isFalse);

    await tester.tap(_retry);
    await tester.pumpAndSettle();
    expect(db.bookmarks, {_key(1), _key(3)});
    expect(db.log, ['bookmark true', 'bookmark true', 'bookmark true']);
    expect(tester.takeException(), isNull);
  });
}
