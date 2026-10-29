import 'package:bible_app/models/models.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/screens/chapter_screen.dart';
import 'package:bible_app/services/database_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 不碰真 DB：記憶體完成集合；`failOnCalls` 指定第幾次寫入丟例外
/// （模擬墓碑寫入失敗→整筆回滾，完成狀態不變）。set/mark/unmark 共用計數，
/// 舊程式（toggle 走 mark/unmark、無錯誤處理）跑同一組測試也會走到失敗注入。
class _FlakyCompletionDatabaseService extends DatabaseService {
  _FlakyCompletionDatabaseService(this.done);
  final Set<int> done; // 已完成的章（創世記）
  int calls = 0;
  final failOnCalls = <int>{};

  void _write(int chapter, bool complete) {
    calls++;
    if (failOnCalls.contains(calls)) throw StateError('tombstone write failed');
    complete ? done.add(chapter) : done.remove(chapter);
  }

  @override
  Future<void> setChapterComplete(int b, int c, bool complete) async =>
      _write(c, complete);

  @override
  Future<void> markChapterComplete(int b, int c) async => _write(c, true);

  @override
  Future<void> unmarkChapterComplete(int b, int c) async => _write(c, false);

  @override
  Future<bool> isChapterComplete(int b, int c) async => done.contains(c);

  @override
  Future<void> markChapterRead(int bookId, int chapter) async {}

  @override
  Future<int> getReadChapterCount() async => done.length;
}

const _books = [
  Book(
    id: 1,
    name: '創世記',
    abbr: '創',
    testament: 'ot',
    chapters: [
      ['起初神創造天地。', '地是空虛混沌。'],
    ],
  ),
];

Future<_FlakyCompletionDatabaseService> _pumpReader(
  WidgetTester tester, {
  required Set<int> done,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final db = _FlakyCompletionDatabaseService(done);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        booksProvider.overrideWith((ref) async => _books),
        databaseServiceProvider.overrideWithValue(db),
        chapterMarksProvider.overrideWith(
          (ref, args) async => const ChapterMarks(
            bookmarks: {},
            highlights: {},
            notes: {},
            later: {},
          ),
        ),
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
  return db;
}

void main() {
  testWidgets('375px 取消本章完成失敗：仍顯示已完成、提示失敗，重試才取消（不翻回）', (tester) async {
    final db = await _pumpReader(tester, done: {1});
    db.failOnCalls.add(1);
    expect(find.byTooltip('已完成本章（點擊取消）'), findsOneWidget);

    await tester.tap(find.byTooltip('已完成本章（點擊取消）'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(db.done, {1});
    expect(find.text('取消完成標記失敗，本章仍為已完成。'), findsOneWidget);
    expect(find.text('已取消本章完成標記'), findsNothing);
    expect(find.byTooltip('已完成本章（點擊取消）'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, '重試'));
    await tester.pumpAndSettle();

    expect(db.calls, 2);
    expect(db.done, isEmpty);
    expect(find.byTooltip('標記本章完成'), findsOneWidget);
    expect(find.text('已取消本章完成標記'), findsOneWidget);
  });

  testWidgets('375px 標記本章完成失敗：仍顯示未完成、提示失敗，重試成功', (tester) async {
    final db = await _pumpReader(tester, done: {});
    db.failOnCalls.add(1);

    await tester.tap(find.byTooltip('標記本章完成'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(db.done, isEmpty);
    expect(find.text('標記本章完成失敗，請再試一次。'), findsOneWidget);
    expect(find.byTooltip('標記本章完成'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, '重試'));
    await tester.pumpAndSettle();

    expect(db.done, {1});
    expect(find.byTooltip('已完成本章（點擊取消）'), findsOneWidget);
    expect(find.text('已標記本章完成'), findsOneWidget);
  });

  testWidgets('375px 重試是寫入目標狀態：失敗後狀態已由他處改變，重試不會翻回', (tester) async {
    final db = await _pumpReader(tester, done: {1});
    db.failOnCalls.add(1);

    await tester.tap(find.byTooltip('已完成本章（點擊取消）'));
    await tester.pumpAndSettle();
    expect(find.text('取消完成標記失敗，本章仍為已完成。'), findsOneWidget);

    // 失敗之後，另一路徑（例如同步）已把本章取消。
    db.done.clear();
    await tester.tap(find.widgetWithText(SnackBarAction, '重試'));
    await tester.pumpAndSettle();

    // 重試的目標是「未完成」，不是 toggle → 不會被翻成已完成。
    expect(db.done, isEmpty);
    expect(find.byTooltip('標記本章完成'), findsOneWidget);
  });
}
