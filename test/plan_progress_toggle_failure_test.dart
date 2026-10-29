import 'dart:async';

import 'package:bible_app/data/reading_plans.dart';
import 'package:bible_app/models/models.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/screens/chapter_screen.dart';
import 'package:bible_app/screens/reading_plans_screen.dart';
import 'package:bible_app/services/database_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 不碰真 DB：記憶體進度集合；`failOnCalls` 指定第幾次寫入丟例外
/// （模擬墓碑寫入失敗→整批回滾，進度不變）。[gate] 非 null 時寫入會卡住直到完成。
class _FlakyPlanDatabaseService extends DatabaseService {
  _FlakyPlanDatabaseService(this.done);
  final Set<String> done; // 'b{book}_c{chapter}'
  int calls = 0;
  final failOnCalls = <int>{};
  Completer<void>? gate;

  @override
  Future<int> setPlanItemsDone(
    String planId,
    List<PlanItemTarget> items,
    bool done, {
    int planVersion = 1,
  }) async {
    calls++;
    if (gate != null) await gate!.future;
    if (failOnCalls.contains(calls)) throw StateError('tombstone write failed');
    var n = 0;
    for (final it in items) {
      final key = 'b${it.bookId}_c${it.chapter}';
      if (done ? this.done.add(key) : this.done.remove(key)) n++;
    }
    return n;
  }

  @override
  Future<Set<String>> getPlanItemProgress(String planId) async => {...done};

  @override
  Future<Map<String, int>> getPlanItemDoneCounts() async => {'t': done.length};

  @override
  Future<bool> isChapterComplete(int b, int c) async => false;

  @override
  Future<void> markChapterRead(int bookId, int chapter) async {}

  @override
  Future<int> getReadChapterCount() async => 0;

  @override
  Future<int> seedPlanItemsFromDays(
    String planId,
    Map<int, List<List<int>>> dayItems,
  ) async => 0;
}

final _books = [
  Book(
    id: 1,
    name: '測試書',
    abbr: '測',
    testament: 'ot',
    chapters: List.generate(4, (i) => ['第 ${i + 1} 章']),
  ),
];

const _plan = ReadingPlan(
  id: 't',
  name: '測試計畫',
  subtitle: '',
  emoji: '📖',
  days: 2,
);

Future<_FlakyPlanDatabaseService> _pumpPlan(
  WidgetTester tester, {
  required Set<String> done,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final db = _FlakyPlanDatabaseService(done);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        booksProvider.overrideWith((ref) async => _books),
        databaseServiceProvider.overrideWithValue(db),
      ],
      child: const MaterialApp(home: ReadingPlanDetailScreen(plan: _plan)),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

Finder _item(int chapter) =>
    find.widgetWithText(CheckboxListTile, '測試書 第 $chapter 章');

bool? _checked(WidgetTester tester, int chapter) =>
    tester.widget<CheckboxListTile>(_item(chapter)).value;

void main() {
  testWidgets('375px 取消勾選失敗：仍顯示已勾選、提示失敗，重試才取消', (tester) async {
    final db = await _pumpPlan(tester, done: {'b1_c1'});
    db.failOnCalls.add(1);
    expect(_checked(tester, 1), isTrue);

    await tester.tap(_item(1));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(db.done, {'b1_c1'});
    expect(_checked(tester, 1), isTrue);
    expect(find.text('取消勾選失敗，進度未變更。'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, '重試'));
    await tester.pumpAndSettle();

    expect(db.calls, 2);
    expect(db.done, isEmpty);
    expect(_checked(tester, 1), isFalse);
  });

  testWidgets('375px 重試寫入目標狀態：失敗後他處已改變，重試不會翻回', (tester) async {
    final db = await _pumpPlan(tester, done: {'b1_c1'});
    db.failOnCalls.add(1);

    await tester.tap(_item(1));
    await tester.pumpAndSettle();
    expect(find.text('取消勾選失敗，進度未變更。'), findsOneWidget);

    // 失敗之後，另一路徑（例如同步）已把這章取消。
    db.done.clear();
    await tester.tap(find.widgetWithText(SnackBarAction, '重試'));
    await tester.pumpAndSettle();

    // 重試的目標是「未完成」，不是 toggle → 不會被翻成已勾選。
    expect(db.done, isEmpty);
    expect(_checked(tester, 1), isFalse);
  });

  testWidgets('375px 完成今日後「復原」失敗：整天仍為完成、提示失敗，重試一次取消整天', (tester) async {
    final db = await _pumpPlan(tester, done: {});
    db.failOnCalls.add(2);

    await tester.tap(find.text('完成今日剩餘 2 章'));
    await tester.pumpAndSettle();
    expect(db.done, {'b1_c1', 'b1_c2'});
    expect(find.text('已完成今日 2 章'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, '復原'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(db.done, {'b1_c1', 'b1_c2'});
    expect(find.text('取消勾選失敗，進度未變更。'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, '重試'));
    await tester.pumpAndSettle();

    expect(db.calls, 3);
    expect(db.done, isEmpty);
    expect(_checked(tester, 1), isFalse);
    expect(_checked(tester, 2), isFalse);
  });

  testWidgets('375px 寫入中停用勾選：連點不會重複寫入', (tester) async {
    final db = await _pumpPlan(tester, done: {'b1_c1'});
    db.gate = Completer<void>();

    await tester.tap(_item(1));
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(_item(1)).onChanged, isNull);
    await tester.tap(_item(1), warnIfMissed: false);
    await tester.pump();
    expect(db.calls, 1);

    db.gate!.complete();
    await tester.pumpAndSettle();
    expect(db.done, isEmpty);
    expect(_checked(tester, 1), isFalse);
    expect(tester.widget<CheckboxListTile>(_item(1)).onChanged, isNotNull);
  });

  testWidgets('375px Reader 完成計畫本章失敗：不顯示已完成、提示失敗，重試成功', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = _FlakyPlanDatabaseService({});
    var attempts = 0;
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
            (ref, args) async => (
              chapter: null,
              verses: const <int, List<VerseAnnotationView>>{},
            ),
          ),
          activeChurchNameProvider.overrideWith((ref) async => null),
          publicNotesProvider.overrideWith((ref, args) async => const {}),
          bookAnnotationProvider.overrideWith((ref, bookId) async => null),
        ],
        child: MaterialApp(
          home: ChapterScreen(
            bookId: 1,
            chapter: 1,
            updateReadingPosition: false,
            onPlanComplete: () async {
              attempts++;
              if (attempts == 1) throw StateError('write failed');
              db.done.add('b1_c1');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('完成計畫本章'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('完成計畫本章失敗，請再試一次。'), findsOneWidget);
    expect(find.byTooltip('完成計畫本章'), findsOneWidget);
    expect(find.text('已完成讀經計畫中的本章'), findsNothing);

    await tester.tap(find.widgetWithText(SnackBarAction, '重試'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(db.done, {'b1_c1'});
    expect(find.byTooltip('計畫本章已完成'), findsOneWidget);
  });
}
