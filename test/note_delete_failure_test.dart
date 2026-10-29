import 'package:bible_app/models/models.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/screens/notes_screen.dart';
import 'package:bible_app/services/database_service.dart';
import 'package:bible_app/widgets/student_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 不碰真 DB：記憶體清單。`failOnCalls` 指定第幾次寫入（軟刪除／還原／永久刪除
/// 共用計數）丟例外——DB 層這些操作都是單一陳述或交易，失敗＝這則完全沒變。
class _FlakyNotesDatabaseService extends DatabaseService {
  _FlakyNotesDatabaseService(this.rows);
  final List<Note> rows;
  int calls = 0;
  final failOnCalls = <int>{};
  final log = <String>[];

  void _maybeFail() {
    calls++;
    if (failOnCalls.contains(calls)) throw StateError('write failed');
  }

  Note _with(Note n, int deletedAt) => Note(
        id: n.id,
        bookId: n.bookId,
        chapter: n.chapter,
        verse: n.verse,
        title: n.title,
        content: n.content,
        deletedAt: deletedAt,
        createdAt: n.createdAt,
        updatedAt: n.updatedAt,
      );

  void _replace(int id, int deletedAt) {
    final i = rows.indexWhere((r) => r.id == id);
    rows[i] = _with(rows[i], deletedAt);
  }

  @override
  Future<void> softDeleteNoteById(int id) async {
    _maybeFail();
    log.add('soft $id');
    _replace(id, 1);
  }

  @override
  Future<void> restoreNote(int id) async {
    _maybeFail();
    log.add('restore $id');
    _replace(id, 0);
  }

  @override
  Future<void> purgeNote(int id) async {
    _maybeFail();
    log.add('purge $id');
    rows.removeWhere((r) => r.id == id);
  }

  @override
  Future<List<Note>> getAllNotes() async =>
      rows.where((r) => !r.isDeleted).toList();

  @override
  Future<List<Note>> getDeletedNotes() async =>
      rows.where((r) => r.isDeleted).toList();
}

Note _note(int id, String title, {int deletedAt = 0}) => Note(
      id: id,
      bookId: 1,
      chapter: 1,
      verse: id,
      title: title,
      content: '$title 的內容',
      deletedAt: deletedAt,
      createdAt: id,
      updatedAt: id,
    );

Future<_FlakyNotesDatabaseService> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final db = _FlakyNotesDatabaseService([
    _note(1, '起初的信心'),
    _note(2, '光與黑暗'),
    _note(3, '安息的應許'),
    _note(4, '舊的默想', deletedAt: 1),
  ]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseServiceProvider.overrideWithValue(db),
        booksProvider.overrideWith(
          (ref) async => const [
            Book(
              id: 1,
              name: '創世記',
              abbr: '創',
              testament: 'ot',
              chapters: [
                ['起初神創造天地', '地是空虛混沌', '神說要有光', '神看光是好的'],
              ],
            ),
          ],
        ),
      ],
      child: const MaterialApp(home: NotesScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

Future<void> _confirmDelete(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, '刪除'));
  await tester.pumpAndSettle();
}

Future<void> _openRecentlyDeleted(WidgetTester tester) async {
  await tester.tap(find.byTooltip('更多'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('最近刪除'));
  await tester.pumpAndSettle();
  expect(find.text('舊的默想'), findsOneWidget);
}

Future<void> _rowMenu(WidgetTester tester, String action) async {
  await tester.tap(find.byType(PopupMenuButton<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('375px 批次刪除到一半失敗：畫面保留未刪筆記、提示部分完成、只重試剩餘', (tester) async {
    final db = await _pump(tester);
    db.failOnCalls.add(2); // 第 1 則成功、第 2 則失敗（這則沒變）

    await tester.tap(find.text('選取'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('起初的信心'));
    await tester.tap(find.text('光與黑暗'));
    await tester.pump();
    await tester.tap(find.descendant(
      of: find.byType(StudentBatchActionBar),
      matching: find.text('刪除'),
    ));
    await tester.pumpAndSettle();
    await _confirmDelete(tester);

    expect(tester.takeException(), isNull);
    expect(db.log, ['soft 1']);
    // 畫面與資料一致：已刪的不見，未刪的仍在。
    expect(find.text('起初的信心'), findsNothing);
    expect(find.text('光與黑暗'), findsOneWidget);
    expect(find.text('只刪除了 1 / 2 則，其餘仍保留。'), findsOneWidget);
    // 保留選取模式，只剩未刪的那則被選取。
    expect(find.text('已選 1 項'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, '重試'));
    await tester.pumpAndSettle();

    // 重試不再跳確認框，只刪剩下那則（第 1 則不重刪、第 3 則不誤刪）。
    expect(find.byType(AlertDialog), findsNothing);
    expect(db.log, ['soft 1', 'soft 2']);
    expect(find.text('光與黑暗'), findsNothing);
    expect(find.text('安息的應許'), findsOneWidget);
    expect(find.byType(StudentBatchActionBar), findsNothing);
  });

  testWidgets('375px 滑動刪除失敗：列回彈仍在、提示可被讀屏操作、重試成功', (tester) async {
    final db = await _pump(tester);
    db.failOnCalls.add(1);

    await tester.drag(find.text('起初的信心'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await _confirmDelete(tester);

    expect(tester.takeException(), isNull);
    expect(db.log, isEmpty);
    expect(find.text('起初的信心'), findsOneWidget);
    expect(find.text('刪除失敗，筆記仍保留。'), findsOneWidget);
    final retry = tester
        .getSemantics(find.widgetWithText(SnackBarAction, '重試'))
        .getSemanticsData();
    expect(retry.label, '重試');
    expect(retry.hasAction(SemanticsAction.tap), isTrue);

    await tester.tap(find.widgetWithText(SnackBarAction, '重試'));
    await tester.pumpAndSettle();

    expect(db.log, ['soft 1']);
    expect(find.text('起初的信心'), findsNothing);
    expect(find.text('光與黑暗'), findsOneWidget);
  });

  testWidgets('375px 最近刪除「還原」失敗：仍列在最近刪除、提示並可重試', (tester) async {
    final db = await _pump(tester);
    await _openRecentlyDeleted(tester);
    db.failOnCalls.add(db.calls + 1);

    await _rowMenu(tester, '還原');

    expect(tester.takeException(), isNull);
    expect(db.log, isEmpty);
    expect(find.text('舊的默想'), findsOneWidget);
    expect(find.text('還原失敗，筆記仍在最近刪除。'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, '重試'));
    await tester.pumpAndSettle();

    expect(db.log, ['restore 4']);
    expect(find.text('沒有最近刪除的筆記'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('舊的默想'), findsOneWidget);
  });

  testWidgets('375px 最近刪除「永久刪除」失敗：筆記不消失、提示並可重試', (tester) async {
    final db = await _pump(tester);
    await _openRecentlyDeleted(tester);
    db.failOnCalls.add(db.calls + 1);

    await _rowMenu(tester, '永久刪除');

    expect(tester.takeException(), isNull);
    expect(db.rows.where((r) => r.id == 4), hasLength(1));
    expect(find.text('舊的默想'), findsOneWidget);
    expect(find.text('永久刪除失敗，筆記仍在最近刪除。'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, '重試'));
    await tester.pumpAndSettle();

    expect(db.log, ['purge 4']);
    expect(find.text('沒有最近刪除的筆記'), findsOneWidget);
    // 其他筆記不受影響。
    expect(db.rows.map((r) => r.id), [1, 2, 3]);
  });
}
