import 'package:bible_app/models/models.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/screens/chapter_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_notes_db.dart';

/// 讀經頁「同一節多則經文筆記」的真實使用流程（375px）。
///
const _books = [
  Book(
    id: 1,
    name: '創世記',
    abbr: '創',
    testament: 'ot',
    chapters: [
      ['起初神創造天地。', '地是空虛混沌，淵面黑暗。'],
    ],
  ),
];

Note _n(
  int id,
  int verse,
  String content, {
  String title = '',
  List<String> refs = const [],
  int at = 0,
}) => Note(
  id: id,
  bookId: 1,
  chapter: 1,
  verse: verse,
  title: title,
  content: content,
  refs: refs,
  createdAt: at == 0 ? id : at,
  updatedAt: at == 0 ? id : at,
);

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

Future<void> _openVerse(WidgetTester tester, String text) async {
  await tester.tap(find.textContaining(text).first);
  await tester.pumpAndSettle();
}

Finder get _editorField => find.widgetWithText(TextField, '筆記內容');

void main() {
  testWidgets('375px 經節顯示筆記數量與最新摘要，點入列出同節全部筆記', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final db = FakeNotesDb([
      _n(1, 1, '較早的筆記', at: 10),
      _n(2, 1, '最新的觀察\n第二行', at: 20),
      _n(3, 2, '另一節的筆記', at: 30),
    ]);
    await _pump(tester, db);

    expect(find.bySemanticsLabel(RegExp('(^|\\D)2 則筆記')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('(^|\\D)1 則筆記')), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // 多則才顯示數字

    await _openVerse(tester, '起初神創造天地');
    expect(find.text('我的筆記 · 2 則'), findsOneWidget);
    expect(find.text('最新：最新的觀察'), findsOneWidget);
    expect(find.text('筆記 2'), findsOneWidget);

    await tester.tap(find.text('我的筆記 · 2 則'));
    await tester.pumpAndSettle();
    expect(find.text('創世記 1:1 筆記（2 則）'), findsOneWidget);
    expect(find.text('最新的觀察'), findsOneWidget);
    expect(find.text('較早的筆記'), findsOneWidget);
    expect(find.text('另一節的筆記'), findsNothing);
    // 最新在前
    expect(
      tester.getTopLeft(find.text('最新的觀察')).dy,
      lessThan(tester.getTopLeft(find.text('較早的筆記')).dy),
    );
    final deletes = find.byTooltip('刪除這則筆記');
    expect(deletes, findsNWidgets(2));
    for (final e in deletes.evaluate()) {
      final data = tester
          .getSemantics(find.byWidget(e.widget))
          .getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
    }
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('375px 選擇既有筆記編輯：只改那一則、保留標題與引用，不影響同節其他筆記', (tester) async {
    _phone(tester);
    final db = FakeNotesDb([
      _n(1, 1, '第一則', title: '標題一', refs: ['b43_c3_v16'], at: 10),
      _n(2, 1, '第二則', at: 20),
    ]);
    await _pump(tester, db);

    await _openVerse(tester, '起初神創造天地');
    await tester.tap(find.text('筆記 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('標題一'));
    await tester.pumpAndSettle();

    expect(find.text('創世記 1:1 編輯筆記'), findsOneWidget);
    expect(find.text('標題：標題一'), findsOneWidget);
    expect(find.text('第一則'), findsOneWidget);
    await tester.enterText(_editorField, '第一則（改）');
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await tester.pumpAndSettle();

    expect(db.log, ['update 1']);
    final edited = db.rows.firstWhere((r) => r.id == 1);
    expect(edited.content, '第一則（改）');
    expect(edited.title, '標題一');
    expect(edited.refs, ['b43_c3_v16']);
    expect(db.rows.firstWhere((r) => r.id == 2).content, '第二則');
    // 回到清單，顯示實際資料
    expect(find.text('已儲存'), findsOneWidget);
    expect(find.text('創世記 1:1 筆記（2 則）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('375px 新增不覆蓋既有筆記：從清單新增＝第三則，原本兩則不變', (tester) async {
    _phone(tester);
    final db = FakeNotesDb([_n(1, 1, '甲', at: 10), _n(2, 1, '乙', at: 20)]);
    await _pump(tester, db);

    await _openVerse(tester, '起初神創造天地');
    await tester.tap(find.text('筆記 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增筆記'));
    await tester.pumpAndSettle();

    expect(find.text('創世記 1:1 新增筆記'), findsOneWidget);
    // 新增編輯器是空白的，不會帶入既有筆記內容
    expect(tester.widget<TextField>(_editorField).controller!.text, isEmpty);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '儲存'))
          .onPressed,
      isNull,
      reason: '空白內容不能儲存',
    );
    await tester.enterText(_editorField, '丙');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await tester.pumpAndSettle();

    expect(db.log, ['insert 3']);
    expect(db.rows.map((r) => r.content), ['甲', '乙', '丙']);
    expect(find.text('創世記 1:1 筆記（3 則）'), findsOneWidget);
    expect(find.text('已新增筆記'), findsOneWidget);

    // 關掉清單，經節數量即時更新
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('375px 沒有筆記的節：直接開新增；中文輸入法組字中按儲存、失敗保留內容、重試只新增一則', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final db = FakeNotesDb([_n(1, 1, '別節的筆記', at: 10)])..failOnCalls.add(1);
    await _pump(tester, db);

    await _openVerse(tester, '地是空虛混沌');
    expect(find.text('我的筆記 · 1 則'), findsNothing);
    await tester.tap(find.text('筆記'));
    await tester.pumpAndSettle();
    expect(find.text('創世記 1:2 新增筆記'), findsOneWidget);

    // 注音組字中（composing 尚未確定）的文字也算內容
    await tester.showKeyboard(_editorField);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '信心ㄉㄜ˙',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 2, end: 5),
      ),
    );
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '信心的功課',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 2, end: 5),
      ),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('創世記 1:2 新增筆記'), findsOneWidget, reason: '失敗不關閉');
    expect(tester.widget<TextField>(_editorField).controller!.text, '信心的功課');
    expect(find.text('儲存失敗，內容仍保留，請再試一次。'), findsOneWidget);
    expect(find.bySemanticsLabel('儲存失敗，內容仍保留，請再試一次。'), findsOneWidget);
    expect(db.rows.where((r) => r.verse == 2), isEmpty);

    // 失敗後繼續打字（組字），重試時存的是畫面上的內容
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '信心的功課。',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    await tester.pump();
    final retry = find.widgetWithText(FilledButton, '重試儲存');
    expect(retry, findsOneWidget);
    final retryNode = tester.getSemantics(retry);
    expect(retryNode.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(find.text('創世記 1:2 新增筆記'), findsNothing);
    final saved = db.rows.where((r) => r.verse == 2).toList();
    expect(saved, hasLength(1));
    expect(saved.single.content, '信心的功課。');
    expect(db.rows.firstWhere((r) => r.id == 1).content, '別節的筆記');
    expect(find.bySemanticsLabel(RegExp('(^|\\D)1 則筆記')), findsNWidgets(2));
    expect(db.log.where((l) => l.startsWith('legacy')), isEmpty);
    handle.dispose();
  });

  testWidgets('375px 編輯失敗：保留修改中的內容，同節其他筆記不受影響，重試成功', (tester) async {
    _phone(tester);
    final db = FakeNotesDb([_n(1, 1, '原文一', at: 10), _n(2, 1, '原文二', at: 20)])
      ..failOnCalls.add(1);
    await _pump(tester, db);

    await _openVerse(tester, '起初神創造天地');
    await tester.tap(find.text('筆記 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('原文一'));
    await tester.pumpAndSettle();
    await tester.enterText(_editorField, '改寫中的內容');
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('創世記 1:1 編輯筆記'), findsOneWidget);
    expect(tester.widget<TextField>(_editorField).controller!.text, '改寫中的內容');
    expect(db.rows.map((r) => r.content), ['原文一', '原文二']);

    await tester.tap(find.widgetWithText(FilledButton, '重試儲存'));
    await tester.pumpAndSettle();
    expect(db.rows.map((r) => r.content), ['改寫中的內容', '原文二']);
    expect(db.log, ['update 1']);
  });

  testWidgets('375px 清單刪除失敗：筆記仍在、顯示可重試；重試只刪那一則，數量即時更新', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final db = FakeNotesDb([_n(1, 1, '要刪的', at: 10), _n(2, 1, '要留的', at: 20)])
      ..failOnCalls.add(1);
    await _pump(tester, db);

    await _openVerse(tester, '起初神創造天地');
    await tester.tap(find.text('筆記 2'));
    await tester.pumpAndSettle();

    final row = find.ancestor(
      of: find.text('要刪的'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: row, matching: find.byTooltip('刪除這則筆記')),
    );
    await tester.pumpAndSettle();
    expect(find.text('移到最近刪除？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '刪除'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('刪除失敗，筆記仍保留。'), findsOneWidget);
    expect(find.bySemanticsLabel('刪除失敗，筆記仍保留。'), findsOneWidget);
    expect(find.text('要刪的'), findsOneWidget);
    expect(find.text('創世記 1:1 筆記（2 則）'), findsOneWidget);

    final retry = find.widgetWithText(TextButton, '重試');
    expect(
      tester
          .getSemantics(retry)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(find.text('移到最近刪除？'), findsNothing, reason: '重試不再詢問');
    expect(db.log, ['soft 1']);
    expect(find.text('要刪的'), findsNothing);
    expect(find.text('要留的'), findsOneWidget);
    expect(find.text('創世記 1:1 筆記（1 則）'), findsOneWidget);
    expect(find.text('已移到最近刪除，可在「經文筆記」還原'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('(^|\\D)1 則筆記')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('(^|\\D)2 則筆記')), findsNothing);
    handle.dispose();
  });

  testWidgets('375px 編輯器內刪除失敗：留在編輯器、內容仍在，重試成功關閉', (tester) async {
    _phone(tester);
    final db = FakeNotesDb([_n(1, 1, '唯一一則', at: 10)])..failOnCalls.add(1);
    await _pump(tester, db);

    await _openVerse(tester, '起初神創造天地');
    await tester.tap(find.text('筆記 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('唯一一則'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '刪除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '刪除'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('創世記 1:1 編輯筆記'), findsOneWidget);
    expect(find.text('刪除失敗，筆記仍保留，請再試一次。'), findsOneWidget);
    expect(tester.widget<TextField>(_editorField).controller!.text, '唯一一則');

    await tester.tap(find.widgetWithText(TextButton, '重試刪除'));
    await tester.pumpAndSettle();
    expect(find.text('移到最近刪除？'), findsNothing);
    expect(find.text('創世記 1:1 編輯筆記'), findsNothing);
    expect(db.log, ['soft 1']);
    expect(find.text('這一節還沒有筆記。'), findsOneWidget);
  });

  testWidgets('375px 大字級（1.5x）同節多則清單與編輯器不溢出', (tester) async {
    _phone(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final db = FakeNotesDb([
      for (var i = 1; i <= 6; i++)
        _n(
          i,
          1,
          '很長很長的一段筆記內容，用來檢查小螢幕換行與省略 $i',
          title: i.isEven ? '標題 $i' : '',
          at: i * 10,
        ),
    ]);
    await _pump(tester, db);

    await _openVerse(tester, '起初神創造天地');
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('我的筆記 · 6 則'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('新增筆記'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('新增筆記'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('創世記 1:1 新增筆記'), findsOneWidget);
  });
}
