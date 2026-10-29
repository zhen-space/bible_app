import 'package:bible_app/models/models.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/screens/chapter_screen.dart';
import 'package:bible_app/screens/search_screen.dart';
import 'package:bible_app/screens/student_home_screen.dart';
import 'package:bible_app/screens/verse_notes_sheet.dart';
import 'package:bible_app/services/bible_repository.dart';
import 'package:bible_app/services/related_verse_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_notes_db.dart';

/// 共用單節面板（`showVerseActionSheet`）的同節多則筆記流程，從真實入口進：
/// 搜尋結果「更多經文操作」與首頁「每日經文」卡的「…」。
/// 和讀經頁共用 `verse_notes_sheet.dart`：則數＋最新摘要、同節全部筆記、
/// 新增不覆蓋、只改／只刪選中那一則、失敗保留內容並可重試。

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

Note _n(
  int id,
  int verse,
  String content, {
  String title = '',
  List<String> refs = const [],
  required int at,
}) => Note(
  id: id,
  bookId: 1,
  chapter: 1,
  verse: verse,
  title: title,
  content: content,
  refs: refs,
  createdAt: at,
  updatedAt: at,
);

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
        allBookmarksProvider.overrideWith((ref) async => const []),
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

Finder _inList(Finder f) =>
    find.descendant(of: find.byType(VerseNotesSheet), matching: f);

Finder get _editorField => find.descendant(
  of: find.byType(VerseNoteEditorSheet),
  matching: find.widgetWithText(TextField, '筆記內容'),
);

String _editorText(WidgetTester tester) =>
    tester.widget<TextField>(_editorField).controller!.text;

void main() {
  testWidgets('375px 搜尋入口：顯示則數與最新摘要、列出同節全部筆記、只改選中那一則', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final db = FakeNotesDb([
      _n(1, 1, '較早的一則', title: '舊標題', refs: ['b45_c5_v8'], at: 10),
      _n(2, 1, '最新的觀察\n第二行', at: 20),
      _n(3, 2, '別節的筆記', at: 30),
    ]);
    await _pumpSearch(tester, db);
    await _openSearchMore(tester);

    expect(find.text('筆記 2'), findsOneWidget);
    expect(find.text('我的筆記 · 2 則'), findsOneWidget);
    expect(find.text('最新：最新的觀察'), findsOneWidget);
    expect(find.text('在經文中閱讀'), findsOneWidget);

    await tester.tap(find.text('我的筆記 · 2 則'));
    await tester.pumpAndSettle();
    expect(find.text('約翰福音 1:1 筆記（2 則）'), findsOneWidget);
    expect(_inList(find.text('最新的觀察')), findsOneWidget);
    expect(_inList(find.text('舊標題')), findsOneWidget);
    expect(_inList(find.text('別節的筆記')), findsNothing);
    final deletes = find.byTooltip('刪除這則筆記');
    expect(deletes, findsNWidgets(2));
    for (final e in deletes.evaluate()) {
      expect(
        tester
            .getSemantics(find.byWidget(e.widget))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
    }

    await tester.tap(_inList(find.text('舊標題')));
    await tester.pumpAndSettle();
    expect(find.text('約翰福音 1:1 編輯筆記'), findsOneWidget);
    expect(_editorText(tester), '較早的一則');
    await tester.enterText(_editorField, '較早的一則（補充）');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await tester.pumpAndSettle();

    expect(db.log, ['update 1']);
    final edited = db.rows.firstWhere((r) => r.id == 1);
    expect(edited.content, '較早的一則（補充）');
    expect(edited.title, '舊標題');
    expect(edited.refs, ['b45_c5_v8']);
    expect(db.rows.firstWhere((r) => r.id == 2).content, '最新的觀察\n第二行');
    expect(find.text('已儲存'), findsOneWidget);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('375px 搜尋入口：新增不覆蓋；注音組字中儲存失敗保留內容、重試只新增一則', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final db = FakeNotesDb([_n(1, 1, '甲', at: 10), _n(2, 1, '乙', at: 20)])
      ..failOnCalls.add(1);
    await _pumpSearch(tester, db);
    await _openSearchMore(tester);
    await tester.tap(find.text('筆記 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增筆記'));
    await tester.pumpAndSettle();

    expect(find.text('約翰福音 1:1 新增筆記'), findsOneWidget);
    expect(_editorText(tester), isEmpty, reason: '新增不帶入既有筆記');
    await tester.showKeyboard(_editorField);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '恩典ㄉㄜ˙',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 2, end: 5),
      ),
    );
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '恩典的記號',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 2, end: 5),
      ),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('約翰福音 1:1 新增筆記'), findsOneWidget, reason: '失敗不關閉');
    expect(_editorText(tester), '恩典的記號');
    expect(find.bySemanticsLabel('儲存失敗，內容仍保留，請再試一次。'), findsOneWidget);
    expect(db.rows.map((r) => r.content), ['甲', '乙']);

    final retry = find.widgetWithText(FilledButton, '重試儲存');
    expect(
      tester
          .getSemantics(retry)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(db.log, ['insert 3']);
    expect(db.rows.map((r) => r.content), ['甲', '乙', '恩典的記號']);
    expect(find.text('約翰福音 1:1 筆記（3 則）'), findsOneWidget);
    expect(db.log.where((l) => l.startsWith('legacy')), isEmpty);
    handle.dispose();
  });

  testWidgets('375px 搜尋入口：刪除選中那一則失敗仍保留、重試只刪那一則', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final db = FakeNotesDb([_n(1, 1, '要刪的', at: 10), _n(2, 1, '要留的', at: 20)])
      ..failOnCalls.add(1);
    await _pumpSearch(tester, db);
    await _openSearchMore(tester);
    await tester.tap(find.text('筆記 2'));
    await tester.pumpAndSettle();

    final row = find.ancestor(
      of: _inList(find.text('要刪的')),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: row, matching: find.byTooltip('刪除這則筆記')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '刪除'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('刪除失敗，筆記仍保留。'), findsOneWidget);
    expect(_inList(find.text('要刪的')), findsOneWidget);
    expect(find.text('約翰福音 1:1 筆記（2 則）'), findsOneWidget);

    await tester.tap(_inList(find.widgetWithText(TextButton, '重試')));
    await tester.pumpAndSettle();
    expect(find.text('移到最近刪除？'), findsNothing, reason: '重試不再詢問');
    expect(db.log, ['soft 1']);
    expect(_inList(find.text('要刪的')), findsNothing);
    expect(_inList(find.text('要留的')), findsOneWidget);
    expect(find.text('約翰福音 1:1 筆記（1 則）'), findsOneWidget);

    // 關掉清單再開面板：則數反映實際資料
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await _openSearchMore(tester);
    expect(find.text('筆記 1'), findsOneWidget);
    expect(find.text('我的筆記 · 1 則'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('375px 個人標記讀取失敗：面板照開、書籤／稍後讀／筆記停用並可重試', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final db = FakeNotesDb([_n(1, 1, '已存在的筆記', at: 10)])..failMarks = true;
    await _pumpSearch(tester, db);
    await _openSearchMore(tester);

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('個人標記暫時無法載入，書籤、稍後讀與筆記請稍後再試。'), findsOneWidget);
    expect(find.text('我的筆記 · 1 則'), findsNothing);
    for (final label in ['筆記', '書籤', '稍後讀']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    expect(
      find.byType(VerseNoteEditorSheet),
      findsNothing,
      reason: '狀態未知時不能開新增，否則會以為沒有筆記',
    );
    expect(db.log, isEmpty);
    expect(find.text('在經文中閱讀'), findsOneWidget, reason: '面板仍開著');

    db.failMarks = false;
    await tester.tap(find.widgetWithText(TextButton, '重試'));
    await tester.pumpAndSettle();
    expect(find.text('個人標記暫時無法載入，書籤、稍後讀與筆記請稍後再試。'), findsNothing);
    expect(find.text('筆記 1'), findsOneWidget);
    expect(find.text('我的筆記 · 1 則'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('375px 每日經文入口：同節多則、編輯失敗保留內容、重試只改那一則；不離開首頁、不動閱讀位置', (
    tester,
  ) async {
    _phone(tester);
    final db = FakeNotesDb([_n(1, 1, '每日一', at: 10), _n(2, 1, '每日二最新', at: 20)])
      ..failOnCalls.add(1);
    await _pumpHome(tester, db);
    await _openDailyMore(tester);

    expect(find.text('筆記 2'), findsOneWidget);
    expect(find.text('最新：每日二最新'), findsOneWidget);
    await tester.tap(find.text('我的筆記 · 2 則'));
    await tester.pumpAndSettle();
    await tester.tap(_inList(find.text('每日一')));
    await tester.pumpAndSettle();
    await tester.enterText(_editorField, '每日一（改寫中）');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('約翰福音 1:1 編輯筆記'), findsOneWidget);
    expect(_editorText(tester), '每日一（改寫中）');
    expect(find.text('儲存失敗，內容仍保留，請再試一次。'), findsOneWidget);
    expect(db.rows.map((r) => r.content), ['每日一', '每日二最新']);

    await tester.tap(find.widgetWithText(FilledButton, '重試儲存'));
    await tester.pumpAndSettle();
    expect(db.log, ['update 1']);
    expect(db.rows.map((r) => r.content), ['每日一（改寫中）', '每日二最新']);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(ChapterScreen), findsNothing);
    expect(find.byType(StudentHomeScreen), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(StudentHomeScreen)),
    );
    expect(container.read(lastReadProvider), isNull);
  });

  testWidgets('375px 每日經文入口：沒有筆記直接新增，儲存後再開面板顯示 1 則', (tester) async {
    _phone(tester);
    final db = FakeNotesDb([_n(1, 2, '別節', at: 10)]);
    await _pumpHome(tester, db);
    await _openDailyMore(tester);

    expect(find.text('我的筆記 · 1 則'), findsNothing);
    await tester.tap(find.text('筆記'));
    await tester.pumpAndSettle();
    expect(find.text('約翰福音 1:1 新增筆記'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '儲存'))
          .onPressed,
      isNull,
    );
    await tester.enterText(_editorField, '今天的領受');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await tester.pumpAndSettle();

    expect(find.byType(VerseNoteEditorSheet), findsNothing);
    expect(db.log, ['insert 2']);
    expect(db.rows.firstWhere((r) => r.id == 1).content, '別節');

    await _openDailyMore(tester);
    expect(find.text('筆記 1'), findsOneWidget);
    expect(find.text('最新：今天的領受'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
