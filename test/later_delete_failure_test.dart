import 'package:bible_app/models/models.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/screens/chapter_screen.dart';
import 'package:bible_app/screens/my_content_screen.dart';
import 'package:bible_app/services/database_service.dart';
import 'package:bible_app/widgets/student_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 不碰真 DB：記憶體清單；`failOnCalls` 指定第幾次寫入丟例外
/// （模擬墓碑寫入失敗→整筆回滾，待讀狀態不變）。set/add/remove/toggle 共用計數，
/// 舊程式（逐筆 removeLater、無錯誤處理）跑同一組測試也會走到失敗注入。
class _FlakyLaterDatabaseService extends DatabaseService {
  _FlakyLaterDatabaseService(this.rows);
  final List<Bookmark> rows;
  int calls = 0;
  final failOnCalls = <int>{};

  bool _has(int b, int c, int v) =>
      rows.any((r) => r.bookId == b && r.chapter == c && r.verse == v);

  void _write(int b, int c, int v, bool on) {
    calls++;
    if (failOnCalls.contains(calls)) throw StateError('tombstone write failed');
    if (on && !_has(b, c, v)) {
      rows.add(Bookmark(bookId: b, chapter: c, verse: v, createdAt: 1000 + calls));
    } else if (!on) {
      rows.removeWhere((r) => r.bookId == b && r.chapter == c && r.verse == v);
    }
  }

  @override
  Future<void> setLater(int b, int c, int v, bool later) async =>
      _write(b, c, v, later);

  @override
  Future<void> addLater(int b, int c, int v) async => _write(b, c, v, true);

  @override
  Future<void> removeLater(int b, int c, int v) async => _write(b, c, v, false);

  @override
  Future<void> toggleLater(int b, int c, int v) async =>
      _write(b, c, v, !_has(b, c, v));

  @override
  Future<List<Bookmark>> getAllLater() async =>
      List.of(rows)..sort((a, b) => a.verse.compareTo(b.verse));

  @override
  Future<Set<int>> getLaterVerses(int b, int c) async => {
        for (final r in rows)
          if (r.bookId == b && r.chapter == c) r.verse,
      };

  @override
  Future<void> markChapterRead(int bookId, int chapter) async {}

  @override
  Future<bool> isChapterComplete(int bookId, int chapter) async => false;

  @override
  Future<List<Bookmark>> getAllBookmarks() async => [];

  @override
  Future<List<Highlight>> getAllHighlights() async => [];

  @override
  Future<List<Note>> getAllNotes() async => [];
}

const _books = [
  Book(
    id: 1,
    name: '創世記',
    abbr: '創',
    testament: 'ot',
    chapters: [
      ['起初神創造天地。', '地是空虛混沌。', '神說要有光。'],
    ],
  ),
];

void _phone(WidgetTester tester) {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<_FlakyLaterDatabaseService> _pumpLater(WidgetTester tester) async {
  _phone(tester);
  final db = _FlakyLaterDatabaseService([
    const Bookmark(bookId: 1, chapter: 1, verse: 1, createdAt: 3),
    const Bookmark(bookId: 1, chapter: 1, verse: 2, createdAt: 2),
    const Bookmark(bookId: 1, chapter: 1, verse: 3, createdAt: 1),
  ]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseServiceProvider.overrideWithValue(db),
        allLaterProvider.overrideWith((ref) => db.getAllLater()),
        booksProvider.overrideWith((ref) async => _books),
      ],
      child: const MaterialApp(home: LaterScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

bool _rowHas(_FlakyLaterDatabaseService db, int v) =>
    db.rows.any((r) => r.verse == v);

void main() {
  testWidgets('375px 稍後閱讀批次移除到一半失敗：保留未移除項目、提示部分完成、只重試剩餘',
      (tester) async {
    final db = await _pumpLater(tester);
    db.failOnCalls.add(2); // 第 1 個移除成功、第 2 個失敗（已回滾）

    await tester.tap(find.text('選取'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('創世記 1:1'));
    await tester.tap(find.text('創世記 1:2'));
    await tester.pump();
    await tester.tap(find.descendant(
      of: find.byType(StudentBatchActionBar),
      matching: find.text('移除'),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_rowHas(db, 1), isFalse);
    expect(_rowHas(db, 2), isTrue);
    expect(find.text('創世記 1:1'), findsNothing);
    expect(find.text('創世記 1:2'), findsOneWidget);
    expect(find.text('只移除了 1 / 2 則，其餘仍保留。'), findsOneWidget);
    expect(find.text('已選 1 項'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, '重試'));
    await tester.pumpAndSettle();

    // 重試只處理剩下那個：第 1 個不會被加回、第 3 個不誤刪。
    expect(db.calls, 3);
    expect(_rowHas(db, 1), isFalse);
    expect(_rowHas(db, 2), isFalse);
    expect(_rowHas(db, 3), isTrue);
    expect(find.text('創世記 1:3'), findsOneWidget);
    expect(find.text('已移除 1 則稍後閱讀'), findsOneWidget);
    expect(find.byType(StudentBatchActionBar), findsNothing);
  });

  testWidgets('375px 稍後閱讀滑動移除失敗：列回彈仍在、提示失敗、重試成功', (tester) async {
    final db = await _pumpLater(tester);
    db.failOnCalls.add(1);

    await tester.drag(find.text('創世記 1:1'), const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(db.rows, hasLength(3));
    expect(find.text('創世記 1:1'), findsOneWidget);
    expect(find.text('移除失敗，稍後閱讀仍保留。'), findsOneWidget);
    final retry = tester
        .getSemantics(find.widgetWithText(SnackBarAction, '重試'))
        .getSemanticsData();
    expect(retry.label, '重試');
    expect(retry.hasAction(SemanticsAction.tap), isTrue);

    await tester.tap(find.widgetWithText(SnackBarAction, '重試'));
    await tester.pumpAndSettle();

    expect(_rowHas(db, 1), isFalse);
    expect(find.text('創世記 1:1'), findsNothing);
    expect(find.text('創世記 1:2'), findsOneWidget);
  });

  testWidgets('375px 稍後閱讀復原失敗：提示失敗、重試後加回且不重複', (tester) async {
    final db = await _pumpLater(tester);
    db.failOnCalls.add(2); // 移除成功，第一次復原失敗

    await tester.drag(find.text('創世記 1:1'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('創世記 1:1'), findsNothing);

    await tester.tap(find.widgetWithText(SnackBarAction, '復原'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_rowHas(db, 1), isFalse);
    expect(find.text('創世記 1:1'), findsNothing);
    expect(find.text('復原失敗，畫面顯示的是目前實際狀態。'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, '重試'));
    await tester.pumpAndSettle();

    expect(db.rows.where((r) => r.verse == 1), hasLength(1));
    expect(find.text('創世記 1:1'), findsOneWidget);
  });

  testWidgets('375px 讀經頁多選加入稍後讀部分失敗：保留未加入的選取、重試只補剩下的',
      (tester) async {
    _phone(tester);
    final db = _FlakyLaterDatabaseService([]);
    db.failOnCalls.add(2);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          booksProvider.overrideWith((ref) async => _books),
          databaseServiceProvider.overrideWithValue(db),
          chapterMarksProvider.overrideWith((ref, args) async => ChapterMarks(
                bookmarks: const {},
                highlights: const {},
                notes: const {},
                later: await db.getLaterVerses(args.bookId, args.chapter),
              )),
          chapterAnnotationProvider.overrideWith(
            (ref, args) async => (
              chapter: null,
              verses: const <int, List<VerseAnnotationView>>{},
            ),
          ),
          activeChurchNameProvider.overrideWith((ref) async => null),
          publicNotesProvider.overrideWith((ref, args) async => const {}),
          bookAnnotationProvider.overrideWith((ref, bookId) async => null),
        ],
        child: const MaterialApp(home: ChapterScreen(bookId: 1, chapter: 1)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.textContaining('起初神創造天地').first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('地是空虛混沌').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('稍後讀'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_rowHas(db, 1), isTrue);
    expect(_rowHas(db, 2), isFalse);
    expect(find.text('只加入了 1 / 2 節，其餘尚未加入。'), findsOneWidget);
    // 仍在多選模式，只剩未加入的那節被選取。
    expect(find.byTooltip('稍後讀'), findsOneWidget);
    expect(find.text('已選 1 節'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, '重試'));
    await tester.pumpAndSettle();

    expect(db.calls, 3);
    expect(db.rows.map((r) => r.verse).toSet(), {1, 2});
    expect(find.byTooltip('稍後讀'), findsNothing);
  });
}
