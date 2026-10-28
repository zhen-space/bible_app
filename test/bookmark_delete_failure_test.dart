import 'package:bible_app/models/models.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/screens/bookmarks_screen.dart';
import 'package:bible_app/services/database_service.dart';
import 'package:bible_app/widgets/student_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 不碰真 DB：記憶體清單；`failOnCalls` 指定第幾次寫入丟例外
/// （模擬墓碑寫入失敗→整筆回滾，書籤仍在）。toggle 與 set 共用同一套計數，
/// 舊程式（逐筆 toggle、無錯誤處理）跑同一組測試也會走到失敗注入。
class _FlakyBookmarkDatabaseService extends DatabaseService {
  _FlakyBookmarkDatabaseService(this.rows);
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
  Future<void> setBookmark(int b, int c, int v, bool bookmarked) async =>
      _write(b, c, v, bookmarked);

  @override
  Future<void> toggleBookmark(int b, int c, int v) async =>
      _write(b, c, v, !_has(b, c, v));

  @override
  Future<List<Bookmark>> getAllBookmarks() async => List.of(rows);
}

final _books = [
  const Book(
    id: 1,
    name: '創世記',
    abbr: '創',
    testament: 'ot',
    chapters: [
      ['起初神創造天地。', '地是空虛混沌。', '神說要有光。'],
    ],
  ),
];

Future<_FlakyBookmarkDatabaseService> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'bookmarks_sort_order': 'scripture'});
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final db = _FlakyBookmarkDatabaseService([
    const Bookmark(bookId: 1, chapter: 1, verse: 1, createdAt: 3),
    const Bookmark(bookId: 1, chapter: 1, verse: 2, createdAt: 2),
    const Bookmark(bookId: 1, chapter: 1, verse: 3, createdAt: 1),
  ]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseServiceProvider.overrideWithValue(db),
        allBookmarksProvider.overrideWith((ref) => db.getAllBookmarks()),
        booksProvider.overrideWith((ref) async => _books),
      ],
      child: const MaterialApp(home: BookmarksScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

bool _rowHas(_FlakyBookmarkDatabaseService db, int v) =>
    db.rows.any((r) => r.verse == v);

void main() {
  testWidgets('375px 批次移除到一半失敗：畫面保留未移除項目、提示部分完成、只重試剩餘', (tester) async {
    final db = await _pump(tester);
    db.failOnCalls.add(2); // 第 1 個移除成功、第 2 個失敗（已回滾）

    await tester.tap(find.text('選取'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('起初神創造天地。'));
    await tester.tap(find.text('地是空虛混沌。'));
    await tester.pump();
    await tester.tap(find.descendant(
      of: find.byType(StudentBatchActionBar),
      matching: find.text('移除'),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_rowHas(db, 1), isFalse);
    expect(_rowHas(db, 2), isTrue);
    // 畫面與資料一致：已移除的不見，未移除的仍在。
    expect(find.text('起初神創造天地。'), findsNothing);
    expect(find.text('地是空虛混沌。'), findsOneWidget);
    expect(find.text('只移除了 1 / 2 個，其餘仍保留。'), findsOneWidget);
    expect(find.text('已選 1 項'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, '重試'));
    await tester.pumpAndSettle();

    // 重試只處理剩下那個：第 1 個不會被 toggle 加回、第 3 個不誤刪。
    expect(db.calls, 3);
    expect(_rowHas(db, 1), isFalse);
    expect(_rowHas(db, 2), isFalse);
    expect(_rowHas(db, 3), isTrue);
    expect(find.text('地是空虛混沌。'), findsNothing);
    expect(find.text('神說要有光。'), findsOneWidget);
    expect(find.text('已移除 1 個書籤'), findsOneWidget);
    expect(find.byType(StudentBatchActionBar), findsNothing);
  });

  testWidgets('375px 滑動移除失敗：列回彈仍在、提示失敗、重試成功', (tester) async {
    final db = await _pump(tester);
    db.failOnCalls.add(1);

    await tester.drag(find.text('起初神創造天地。'), const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(db.rows, hasLength(3));
    expect(find.text('起初神創造天地。'), findsOneWidget);
    expect(find.text('移除失敗，書籤仍保留。'), findsOneWidget);
    final retry = tester
        .getSemantics(find.widgetWithText(SnackBarAction, '重試'))
        .getSemanticsData();
    expect(retry.label, '重試');
    expect(retry.hasAction(SemanticsAction.tap), isTrue);

    await tester.tap(find.widgetWithText(SnackBarAction, '重試'));
    await tester.pumpAndSettle();

    expect(_rowHas(db, 1), isFalse);
    expect(find.text('起初神創造天地。'), findsNothing);
    expect(find.text('地是空虛混沌。'), findsOneWidget);
  });

  testWidgets('375px 復原失敗：提示失敗、重試後加回且不重複', (tester) async {
    final db = await _pump(tester);
    db.failOnCalls.add(2); // 移除成功，第一次復原失敗

    await tester.drag(find.text('起初神創造天地。'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('起初神創造天地。'), findsNothing);

    await tester.tap(find.widgetWithText(SnackBarAction, '復原'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_rowHas(db, 1), isFalse);
    expect(find.text('起初神創造天地。'), findsNothing);
    expect(find.text('復原失敗，畫面顯示的是目前實際狀態。'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, '重試'));
    await tester.pumpAndSettle();

    expect(db.rows.where((r) => r.verse == 1), hasLength(1));
    expect(find.text('起初神創造天地。'), findsOneWidget);
  });
}
