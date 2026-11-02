import 'package:bible_app/models/models.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/screens/chapter_screen.dart';
import 'package:bible_app/services/tts_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_notes_db.dart';

/// 讀經頁節面板「相關」交叉引用與翻章的日常流程（375px，真實 ChapterScreen）：
/// - 交叉引用一律走 AppLinks.openVerseRef：範圍（約1:1-3、約1:1-2:3）定位到起點、
///   閃示該節，且是臨時瀏覽——不覆蓋「繼續閱讀」、不記閱讀紀錄；返回原章原位。
/// - 解析不了的引用：告知使用者（螢幕閱讀器會念），停在原章。
/// - 閱讀紀錄（markChapterRead）寫入失敗：開章與翻章照常、「繼續閱讀」照常更新。

/// 書卷 id＝索引+1（畫面用 books[bookId - 1]）：創世記(1) 有 2 章，約翰福音(43) 有 3 章。
final _books = [
  for (var id = 1; id <= 43; id++)
    Book(
      id: id,
      name: switch (id) {
        1 => '創世記',
        43 => '約翰福音',
        _ => '書$id',
      },
      abbr: switch (id) {
        1 => '創',
        43 => '約',
        _ => '書$id',
      },
      testament: id < 40 ? 'ot' : 'nt',
      chapters: switch (id) {
        1 => [
          ['起初神創造天地。', '地是空虛混沌，淵面黑暗。'],
          ['天地萬物都造齊了。'],
        ],
        43 => [
          ['太初有道，道與神同在。', '這道太初與神同在。', '萬物是藉著他造的。'],
          ['第三天，在加利利的迦拿有娶親的筵席。', '耶穌和他的門徒也被請去赴席。', '酒用盡了。'],
          for (var c = 3; c <= 3; c++)
            [
              for (var v = 1; v <= 16; v++)
                v == 16 ? '神愛世人，甚至將他的獨生子賜給他們。' : '約三$v',
            ],
        ],
        _ => [
          ['第$id卷'],
        ],
      },
    ),
];

/// 模擬「聽聖經」正在朗讀第 1 節（不碰真的 TTS plugin）。
class _PlayingTts extends TtsController {
  @override
  TtsState build() => const TtsState(playing: true, verse: 1);
}

class _ReadLogDb extends FakeNotesDb {
  _ReadLogDb() : super([]);
  bool failReadLog = false;
  final reads = <String>[];

  @override
  Future<void> markChapterRead(int b, int c) async {
    reads.add('$b:$c');
    if (failReadLog) throw StateError('read log write failed');
  }
}

void _phone(WidgetTester tester) {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(
  WidgetTester tester,
  _ReadLogDb db, {
  List<String> crossRefs = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        booksProvider.overrideWith((ref) async => _books),
        databaseServiceProvider.overrideWithValue(db),
        chapterAnnotationProvider.overrideWith(
          (ref, args) async => (
            chapter: null,
            verses: args.bookId == 1 && args.chapter == 1
                ? {
                    1: [
                      VerseAnnotationView(
                        verse: 1,
                        isChurch: false,
                        annotationId: 'verse_1_1_1',
                        ann: VerseAnnotation(crossRefs: crossRefs),
                      ),
                    ],
                  }
                : const <int, List<VerseAnnotationView>>{},
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
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ChapterScreen).first));

Future<void> _openRelated(WidgetTester tester) async {
  await tester.tap(find.textContaining('起初神創造天地').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('相關'));
  await tester.pumpAndSettle();
}

Future<void> _tapRef(WidgetTester tester, String ref) async {
  await tester.tap(find.widgetWithText(ActionChip, ref));
  await tester.pumpAndSettle();
}

ChapterScreen _topReader(WidgetTester tester) =>
    tester.widget<ChapterScreen>(find.byType(ChapterScreen).last);

void main() {
  testWidgets('375px 交叉引用範圍「約1:1-3」：開到約翰福音1章並定位第1節，臨時瀏覽不覆蓋繼續閱讀', (
    tester,
  ) async {
    _phone(tester);
    final db = _ReadLogDb();
    await _pump(tester, db, crossRefs: ['約1:1-3', '約3:16']);
    final before = _container(tester).read(lastReadProvider);
    expect(before?.bookId, 1);
    expect(before?.chapter, 1);
    expect(db.reads, ['1:1']);

    await _openRelated(tester);
    await _tapRef(tester, '約1:1-3');

    expect(tester.takeException(), isNull);
    expect(
      find.byType(ChapterScreen, skipOffstage: false),
      findsNWidgets(2),
      reason: '原章仍在底下，臨時 Reader 疊在上面',
    );
    final top = _topReader(tester);
    expect(top.bookId, 43);
    expect(top.chapter, 1);
    expect(top.focusVerse, 1);
    expect(top.updateReadingPosition, isFalse);
    expect(find.textContaining('太初有道'), findsWidgets);
    expect(_container(tester).read(lastReadProvider), before);
    expect(db.reads, ['1:1'], reason: '臨時瀏覽不記閱讀紀錄');

    // 返回：回到原章，繼續閱讀仍是創世記1章
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ChapterScreen), findsOneWidget);
    expect(find.textContaining('起初神創造天地'), findsWidgets);
    expect(_container(tester).read(lastReadProvider), before);
  });

  testWidgets('375px 交叉引用單節「約3:16」：定位並顯示第16節', (tester) async {
    _phone(tester);
    final db = _ReadLogDb();
    await _pump(tester, db, crossRefs: ['約3:16']);
    final before = _container(tester).read(lastReadProvider);

    await _openRelated(tester);
    await _tapRef(tester, '約3:16');

    final top = _topReader(tester);
    expect((top.bookId, top.chapter, top.focusVerse), (43, 3, 16));
    expect(top.updateReadingPosition, isFalse);
    expect(find.textContaining('神愛世人'), findsWidgets);
    expect(_container(tester).read(lastReadProvider), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('375px 跨章範圍「約1:1-2:3」定位到起點 約1:1', (tester) async {
    _phone(tester);
    final db = _ReadLogDb();
    await _pump(tester, db, crossRefs: ['約1:1-2:3']);

    await _openRelated(tester);
    await _tapRef(tester, '約1:1-2:3');

    final top = _topReader(tester);
    expect((top.bookId, top.chapter, top.focusVerse), (43, 1, 1));
    expect(top.updateReadingPosition, isFalse);
  });

  testWidgets('375px 解析不了的引用：可朗讀的提示、停在原章、繼續閱讀不變', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final db = _ReadLogDb();
    await _pump(tester, db, crossRefs: ['某書9:9']);
    final before = _container(tester).read(lastReadProvider);

    await _openRelated(tester);
    await _tapRef(tester, '某書9:9');

    expect(tester.takeException(), isNull);
    expect(find.byType(ChapterScreen), findsOneWidget, reason: '沒有開出空白頁');
    expect(find.text('找不到這段經文：某書9:9'), findsOneWidget);
    expect(find.bySemanticsLabel('找不到這段經文：某書9:9'), findsOneWidget);
    expect(find.textContaining('起初神創造天地'), findsWidgets);
    expect(_container(tester).read(lastReadProvider), before);
    handle.dispose();
  });

  testWidgets('375px 閱讀紀錄寫入失敗：開章與下一章照常，繼續閱讀照常更新', (tester) async {
    _phone(tester);
    final db = _ReadLogDb()..failReadLog = true;
    await _pump(tester, db);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('起初神創造天地'), findsWidgets);

    await tester.tap(find.byTooltip('下一章'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('天地萬物都造齊了'), findsWidgets);
    final pos = _container(tester).read(lastReadProvider);
    expect((pos?.bookId, pos?.chapter), (1, 2));
    expect(db.reads, ['1:1', '1:2'], reason: '每次開章都試著記，失敗不擋');
    expect(find.byType(SnackBar), findsNothing, reason: '背景紀錄失敗不打斷閱讀');
  });

  testWidgets('375px 朗讀中返回離開讀經頁：不丟例外，朗讀狀態歸零', (tester) async {
    _phone(tester);
    final db = _ReadLogDb();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          booksProvider.overrideWith((ref) async => _books),
          databaseServiceProvider.overrideWithValue(db),
          ttsProvider.overrideWith(_PlayingTts.new),
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
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const ChapterScreen(bookId: 43, chapter: 1),
                    ),
                  ),
                  child: const Text('開讀經頁'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開讀經頁'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChapterScreen)),
    );
    expect(container.read(ttsProvider).playing, isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'dispose 期間不改 provider');
    expect(find.byType(ChapterScreen), findsNothing);
    expect(find.text('開讀經頁'), findsOneWidget);
    expect(container.read(ttsProvider).playing, isFalse);
    expect(container.read(ttsProvider).verse, isNull);
  });
}
