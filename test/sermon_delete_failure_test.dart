import 'package:bible_app/models/models.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/screens/sermon_notes_screen.dart';
import 'package:bible_app/services/database_service.dart';
import 'package:bible_app/widgets/student_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 不碰真 DB：記憶體清單；`failOnCalls` 指定第幾次 deleteSermonNote 丟例外
/// （模擬墓碑寫入失敗→整筆回滾，筆記仍在）。
class _FlakyDeleteDatabaseService extends DatabaseService {
  _FlakyDeleteDatabaseService(this.rows);
  final List<SermonNote> rows;
  int calls = 0;
  final deletedIds = <int>[];
  final failOnCalls = <int>{};

  @override
  Future<void> deleteSermonNote(int id) async {
    calls++;
    if (failOnCalls.contains(calls)) throw StateError('tombstone write failed');
    rows.removeWhere((r) => r.id == id);
    deletedIds.add(id);
  }

  @override
  Future<List<SermonNote>> getSermonNotes() async => List.of(rows);
}

SermonNote _note(int id, String title) =>
    SermonNote(id: id, date: 0, title: title, createdAt: id, updatedAt: id);

Future<_FlakyDeleteDatabaseService> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final db = _FlakyDeleteDatabaseService([
    _note(1, '恩典的記號'),
    _note(2, '信心的功課'),
    _note(3, '盼望的應許'),
  ]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseServiceProvider.overrideWithValue(db),
        allSermonNotesProvider.overrideWith((ref) => db.getSermonNotes()),
        statsProvider.overrideWith((ref) async => const <String, int>{}),
      ],
      child: const MaterialApp(home: SermonNotesScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

Future<void> _confirmDelete(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, '刪除'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('375px 批次刪除到一半失敗：畫面保留未刪筆記、提示部分完成、只重試剩餘', (tester) async {
    final db = await _pump(tester);
    db.failOnCalls.add(2); // 第 1 則刪除成功、第 2 則失敗（已回滾）

    await tester.tap(find.text('選取'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恩典的記號'));
    await tester.tap(find.text('信心的功課'));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(StudentBatchActionBar),
        matching: find.text('刪除'),
      ),
    );
    await tester.pumpAndSettle();
    await _confirmDelete(tester);

    expect(tester.takeException(), isNull);
    expect(db.deletedIds, [1]);
    // 畫面與資料一致：已刪的不見，未刪的仍在。
    expect(find.text('恩典的記號'), findsNothing);
    expect(find.text('信心的功課'), findsOneWidget);
    expect(find.text('只刪除了 1 / 2 則，其餘仍保留。'), findsOneWidget);
    // 保留選取模式，未刪的那則仍被選取。
    expect(find.text('已選 1 項'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, '重試'));
    await tester.pumpAndSettle();

    // 重試不再跳確認框，只刪剩下那一則（第 1 則不重刪、第 3 則不誤刪）。
    expect(find.byType(AlertDialog), findsNothing);
    expect(db.calls, 3);
    expect(db.deletedIds, [1, 2]);
    expect(find.text('信心的功課'), findsNothing);
    expect(find.text('盼望的應許'), findsOneWidget);
    expect(find.text('已選 1 項'), findsNothing);
    expect(find.byType(StudentBatchActionBar), findsNothing);
  });

  testWidgets('375px 滑動刪除失敗：列回彈仍在、提示失敗、重試成功', (tester) async {
    final db = await _pump(tester);
    db.failOnCalls.add(1);

    await tester.drag(find.text('恩典的記號'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await _confirmDelete(tester);

    expect(tester.takeException(), isNull);
    expect(db.rows, hasLength(3));
    expect(find.text('恩典的記號'), findsOneWidget);
    expect(find.text('刪除失敗，證道筆記仍保留。'), findsOneWidget);
    // 失敗提示要能被讀屏念出且有可操作的重試。
    final retry = tester
        .getSemantics(find.widgetWithText(SnackBarAction, '重試'))
        .getSemanticsData();
    expect(retry.label, '重試');
    expect(retry.hasAction(SemanticsAction.tap), isTrue);

    await tester.tap(find.widgetWithText(SnackBarAction, '重試'));
    await tester.pumpAndSettle();

    expect(db.deletedIds, [1]);
    expect(find.text('恩典的記號'), findsNothing);
    expect(find.text('信心的功課'), findsOneWidget);
  });

  testWidgets('375px 編輯頁刪除失敗：留在編輯頁、內容不丟、提示並可重試', (tester) async {
    final db = await _pump(tester);
    db.failOnCalls.add(1);

    await tester.tap(find.text('恩典的記號'));
    await tester.pumpAndSettle();
    expect(find.text('編輯證道筆記'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刪除').last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 不誤判完成：沒有返回清單、筆記仍在。
    expect(find.text('編輯證道筆記'), findsOneWidget);
    expect(find.widgetWithText(TextField, '恩典的記號'), findsOneWidget);
    expect(db.rows, hasLength(3));
    expect(find.text('刪除失敗，證道筆記仍保留。'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, '重試'));
    await tester.pumpAndSettle();

    expect(db.deletedIds, [1]);
    expect(find.text('編輯證道筆記'), findsNothing);
    expect(find.text('恩典的記號'), findsNothing);
    expect(find.text('信心的功課'), findsOneWidget);
  });
}
