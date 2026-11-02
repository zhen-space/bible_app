import 'dart:async';

import 'package:bible_app/models/models.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/screens/chapter_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_notes_db.dart';

/// 讀經頁（ChapterScreen）自己的螢光筆／書籤寫入失敗復原：單節面板與多選批次列。
/// 一律寫目標狀態（setHighlight／setBookmark，不再用 toggleBookmark）；失敗時畫面
/// 回到實際儲存的狀態、SnackBar（螢幕閱讀器會念）＋不會反轉的「重試」；
/// 批次只保留尚未寫入的節為選取、重試只補剩下的；連點／寫入中不重複寫。

const _books = [
  Book(
    id: 1,
    name: '創世記',
    abbr: '創',
    testament: 'ot',
    chapters: [
      ['起初神創造天地。', '地是空虛混沌，淵面黑暗。', '神說：要有光，就有了光。'],
    ],
  ),
];

String _key(int verse) => '1:1:$verse';

const _texts = ['起初神創造天地', '地是空虛混沌', '神說：要有光'];

void _phone(WidgetTester tester) {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(WidgetTester tester, FakeNotesDb db) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        booksProvider.overrideWith((ref) async => _books),
        databaseServiceProvider.overrideWithValue(db),
        chapterAnnotationProvider.overrideWith(
          (ref, args) async =>
              (chapter: null, verses: const <int, List<VerseAnnotationView>>{}),
        ),
        activeChurchNameProvider.overrideWith((ref) async => null),
        publicNotesProvider.overrideWith((ref, args) async => const {}),
        bookAnnotationProvider.overrideWith((ref, bookId) async => null),
      ],
      child: const MaterialApp(home: ChapterScreen(bookId: 1, chapter: 1)),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _verse(int v) => find.textContaining(_texts[v - 1]).first;

Future<void> _openPanel(WidgetTester tester, int v) async {
  await tester.tap(_verse(v));
  await tester.pumpAndSettle();
}

Future<void> _closePanel(WidgetTester tester) async {
  await tester.tapAt(const Offset(10, 10));
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester, List<int> verses) async {
  await tester.longPress(_verse(verses.first));
  await tester.pumpAndSettle();
  for (final v in verses.skip(1)) {
    await tester.tap(_verse(v));
    await tester.pumpAndSettle();
  }
}

Finder get _retry => find.widgetWithText(SnackBarAction, '重試');

Finder get _bulkBookmarkButton =>
    find.ancestor(of: find.byTooltip('書籤'), matching: find.byType(IconButton));

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

/// 經節上的書籤圖示數（面板裡的按鈕用的是 bookmark_add／bookmark_remove）。
int _bookmarkIcons() => find.byIcon(Icons.bookmark).evaluate().length;

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ChapterScreen)));

void main() {
  testWidgets('375px 單節加入書籤失敗 → 仍未加入、可朗讀錯誤；重試只加一次，閱讀位置不變', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final db = FakeNotesDb([])..failMarkCalls.add(1);
    await _pump(tester, db);
    final lastRead = _container(tester).read(lastReadProvider);
    expect(lastRead?.chapter, 1);

    await _openPanel(tester, 1);
    await tester.tap(find.text('書籤'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    _expectAnnounced(tester, '加入書籤失敗，這節沒有加入書籤。');
    expect(db.bookmarks, isEmpty);
    expect(_bookmarkIcons(), 0);
    await _openPanel(tester, 1);
    expect(find.text('書籤'), findsOneWidget, reason: '面板顯示實際狀態');
    expect(find.text('移除書籤'), findsNothing);
    await _closePanel(tester);

    await tester.tap(_retry);
    await tester.pumpAndSettle();
    expect(db.bookmarks, {_key(1)});
    expect(db.log, ['bookmark true', 'bookmark true']);
    expect(db.log, isNot(contains('legacy toggleBookmark')));
    expect(_bookmarkIcons(), 1);
    expect(_container(tester).read(lastReadProvider), lastRead);
    handle.dispose();
  });

  testWidgets('375px 單節移除書籤失敗 → 書籤仍在；重試寫「移除」，不會因切換加回來', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final db = FakeNotesDb([])
      ..bookmarks.add(_key(2))
      ..failMarkCalls.add(1);
    await _pump(tester, db);
    expect(_bookmarkIcons(), 1);

    await _openPanel(tester, 2);
    await tester.tap(find.text('移除書籤'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    _expectAnnounced(tester, '移除書籤失敗，書籤仍保留。');
    expect(db.bookmarks, {_key(2)});
    expect(_bookmarkIcons(), 1);

    db.bookmarks.clear(); // 失敗後在別處已移除
    await tester.tap(_retry);
    await tester.pumpAndSettle();
    expect(db.bookmarks, isEmpty);
    expect(db.log, ['bookmark false', 'bookmark false']);
    expect(_bookmarkIcons(), 0);
    handle.dispose();
  });

  testWidgets('375px 單節加螢光筆、換色、移除螢光筆失敗都回到實際狀態並可重試', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final db = FakeNotesDb([])..failMarkCalls.addAll({1, 3, 5});
    await _pump(tester, db);

    // 加上：失敗 → 重試
    await _openPanel(tester, 3);
    final yellow = find.bySemanticsLabel('螢光筆 黃色');
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
    expect(db.highlights, {_key(3): HighlightColor.yellow});

    // 換色：失敗仍是黃色 → 重試換成藍色
    await _openPanel(tester, 3);
    expect(
      tester.getSemantics(find.bySemanticsLabel('螢光筆 黃色')),
      containsSemantics(isSelected: true),
    );
    await tester.tap(find.bySemanticsLabel('螢光筆 藍色'));
    await tester.pumpAndSettle();
    _expectAnnounced(tester, '更換螢光筆失敗，顏色沒有變更。');
    expect(db.highlights, {_key(3): HighlightColor.yellow});
    await _openPanel(tester, 3);
    expect(
      tester.getSemantics(find.bySemanticsLabel('螢光筆 黃色')),
      containsSemantics(isSelected: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('螢光筆 藍色')),
      containsSemantics(isSelected: false),
    );
    await _closePanel(tester);
    await tester.tap(_retry);
    await tester.pumpAndSettle();
    expect(db.highlights, {_key(3): HighlightColor.blue});

    // 移除：失敗仍在 → 重試移除
    await _openPanel(tester, 3);
    await tester.tap(find.byTooltip('移除螢光筆'));
    await tester.pumpAndSettle();
    _expectAnnounced(tester, '移除螢光筆失敗，螢光筆仍保留。');
    expect(db.highlights, {_key(3): HighlightColor.blue});
    await tester.tap(_retry);
    await tester.pumpAndSettle();
    expect(db.highlights, isEmpty);
    expect(db.log, [
      'highlight yellow',
      'highlight yellow',
      'highlight blue',
      'highlight blue',
      'highlight null',
      'highlight null',
    ]);
    handle.dispose();
  });

  testWidgets('375px 單節面板關閉中連點、寫入中再開面板都不會重複寫或多 pop 一層', (tester) async {
    _phone(tester);
    final db = FakeNotesDb([])..markGate = Completer<void>();
    await _pump(tester, db);

    await _openPanel(tester, 1);
    await tester.tap(find.text('書籤'));
    await tester.tap(find.text('書籤'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(db.log, ['bookmark true'], reason: '只寫一次');
    expect(find.byType(ChapterScreen), findsOneWidget, reason: '沒有多 pop 一層');

    // 寫入還在進行：再開面板，書籤按鈕停用，點了不寫也不關面板
    await _openPanel(tester, 1);
    await tester.tap(find.text('書籤'));
    await tester.pumpAndSettle();
    expect(db.log, ['bookmark true']);
    expect(find.text('字義'), findsOneWidget, reason: '面板仍開著');
    await _closePanel(tester);

    db.markGate!.complete();
    await tester.pumpAndSettle();
    expect(db.bookmarks, {_key(1)});
    expect(_bookmarkIcons(), 1);
    await _openPanel(tester, 1);
    expect(find.text('移除書籤'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('375px 多選螢光筆部分失敗：只保留未寫入的節為選取，重試只補剩下的', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final db = FakeNotesDb([])..failMarkCalls.add(2);
    await _pump(tester, db);

    await _select(tester, [1, 2, 3]);
    expect(find.text('已選 3 節'), findsOneWidget);
    await tester.tap(find.byTooltip('螢光筆'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('螢光筆 黃色'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    _expectAnnounced(tester, '只標記了 1 / 3 節，其餘沒有變更。');
    expect(db.highlights, {_key(1): HighlightColor.yellow});
    expect(find.text('已選 2 節'), findsOneWidget, reason: '只剩沒寫入的第 2、3 節');

    await tester.tap(_retry);
    await tester.pumpAndSettle();
    expect(db.highlights, {
      _key(1): HighlightColor.yellow,
      _key(2): HighlightColor.yellow,
      _key(3): HighlightColor.yellow,
    });
    expect(db.log, [
      'highlight yellow', // 第 1 節
      'highlight yellow', // 第 2 節失敗
      'highlight yellow', // 重試第 2 節
      'highlight yellow', // 重試第 3 節
    ]);
    expect(find.textContaining('已選'), findsNothing, reason: '全部完成才離開多選');
    handle.dispose();
  });

  testWidgets('375px 多選移除螢光筆全部失敗：螢光筆仍保留、選取不變，重試移除', (tester) async {
    _phone(tester);
    final db = FakeNotesDb([])
      ..highlights[_key(1)] = HighlightColor.green
      ..highlights[_key(2)] = HighlightColor.pink
      ..failMarkCalls.add(1);
    await _pump(tester, db);

    await _select(tester, [1, 2]);
    await tester.tap(find.byTooltip('螢光筆'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('移除螢光筆'));
    await tester.pumpAndSettle();

    expect(find.text('移除螢光筆失敗，螢光筆仍保留。'), findsOneWidget);
    expect(db.highlights.length, 2);
    expect(find.text('已選 2 節'), findsOneWidget);
    await tester.tap(_retry);
    await tester.pumpAndSettle();
    expect(db.highlights, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('375px 多選加入書籤失敗：已有的書籤不會被移除；重試補完；寫入中按鈕停用不重複寫', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final db = FakeNotesDb([])
      ..bookmarks.add(_key(2))
      ..failMarkCalls.add(1)
      ..markGate = Completer<void>();
    await _pump(tester, db);

    await _select(tester, [1, 2, 3]);
    await tester.tap(_bulkBookmarkButton);
    await tester.pump();
    // 寫入中：批次書籤、螢光筆按鈕停用，連點不會再寫
    expect(tester.widget<IconButton>(_bulkBookmarkButton).onPressed, isNull);
    await tester.tap(_bulkBookmarkButton, warnIfMissed: false);
    await tester.pump();
    expect(db.log, ['bookmark true']);

    db.markGate!.complete();
    db.markGate = null;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    _expectAnnounced(tester, '加入書籤失敗，這幾節沒有加入書籤。');
    expect(db.bookmarks, {_key(2)}, reason: '原本的書籤沒被切換掉');
    expect(find.text('已選 3 節'), findsOneWidget);

    await tester.tap(_retry);
    await tester.pumpAndSettle();
    expect(db.bookmarks, {_key(1), _key(2), _key(3)});
    expect(db.log.every((l) => l == 'bookmark true'), isTrue);
    expect(db.log, isNot(contains('legacy toggleBookmark')));
    expect(_bookmarkIcons(), 3);
    expect(find.textContaining('已選'), findsNothing);
    handle.dispose();
  });
}
