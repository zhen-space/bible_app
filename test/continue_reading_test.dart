import 'dart:async';

import 'package:bible_app/models/models.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/screens/bible_hub_screen.dart';
import 'package:bible_app/screens/chapter_screen.dart';
import 'package:bible_app/screens/student_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_notes_db.dart';

/// 開 App 後「繼續閱讀」（375px，真實首頁）：
/// - 位置還在讀取：顯示載入中，**不**顯示「開始第一次閱讀」（一點就會把位置覆蓋成創 1）。
/// - 讀取失敗：可朗讀的錯誤＋「再試一次」，一樣不給「開始第一次閱讀」。
/// - 讀取晚到：不蓋掉這段期間已經更新的新位置。
/// - 存的位置對不上目前聖經資料：當作沒有位置，首頁與聖經頁都不當掉。
/// - 寫入失敗：不擋閱讀，記憶體中的位置照樣更新。

final _books = [
  for (var id = 1; id <= 43; id++)
    Book(
      id: id,
      name: switch (id) {
        1 => '創世記',
        43 => '約翰福音',
        _ => '書$id',
      },
      abbr: '書$id',
      testament: id < 40 ? 'ot' : 'nt',
      chapters: [
        for (var c = 1; c <= (id == 43 ? 3 : 1); c++)
          [for (var v = 1; v <= 3; v++) '書$id 第$c章 第$v節'],
      ],
    ),
];

class _FakeStore implements LastReadStore {
  _FakeStore(this.value);
  String? value;
  Completer<void>? gate;
  bool failRead = false;
  bool failWrite = false;
  int reads = 0;
  final writes = <String>[];

  @override
  Future<String?> read() async {
    reads++;
    final g = gate;
    if (g != null) await g.future;
    if (failRead) throw StateError('storage unavailable');
    return value;
  }

  @override
  Future<void> write(String v) async {
    writes.add(v);
    if (failWrite) throw StateError('quota exceeded');
    value = v;
  }
}

void _phone(WidgetTester tester) {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

List<Override> _overrides(_FakeStore store) => [
  lastReadStoreProvider.overrideWithValue(store),
  booksProvider.overrideWith((ref) async => _books),
  databaseServiceProvider.overrideWithValue(FakeNotesDb([])),
  publishedDailyVerseProvider.overrideWith((ref) async => null),
  dailyVerseProvider.overrideWith((ref) async => null),
  readingPlanTodayProvider.overrideWith((ref) async => null),
  churchOnboardingVisibleProvider.overrideWith((ref) async => false),
  chapterAnnotationProvider.overrideWith(
    (ref, args) async =>
        (chapter: null, verses: const <int, List<VerseAnnotationView>>{}),
  ),
  activeChurchNameProvider.overrideWith((ref) async => null),
  publicNotesProvider.overrideWith((ref, args) async => const {}),
  bookAnnotationProvider.overrideWith((ref, bookId) async => null),
];

Future<void> _pumpHome(WidgetTester tester, _FakeStore store) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(store),
      child: const MaterialApp(home: Scaffold(body: StudentHomeScreen())),
    ),
  );
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(StudentHomeScreen)));

void main() {
  testWidgets('375px 位置讀取中：顯示載入中，不出現「開始第一次閱讀」；讀到後顯示繼續閱讀', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final store = _FakeStore('43:3:120.0')..gate = Completer<void>();
    await _pumpHome(tester, store);
    await tester.pump();
    await tester.pump();

    expect(find.text('開始第一次閱讀'), findsNothing);
    expect(find.bySemanticsLabel('正在載入上次閱讀位置'), findsOneWidget);

    store.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('約翰福音 3'), findsOneWidget);
    expect(find.text('繼續閱讀'), findsWidgets);
    expect(find.text('開始第一次閱讀'), findsNothing);
    expect(store.writes, isEmpty, reason: '只是讀取，不寫入');
    handle.dispose();
  });

  testWidgets('375px 點「繼續閱讀」：回到存的章與捲動位置', (tester) async {
    _phone(tester);
    final store = _FakeStore('43:3:120.0');
    await _pumpHome(tester, store);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '繼續閱讀'));
    await tester.pumpAndSettle();

    final reader = tester.widget<ChapterScreen>(find.byType(ChapterScreen));
    expect((reader.bookId, reader.chapter), (43, 3));
    expect(reader.initialOffset, 120.0);
    expect(reader.updateReadingPosition, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('375px 位置讀取失敗：可朗讀的錯誤＋再試一次，不給「開始第一次閱讀」；重試後恢復', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final store = _FakeStore('43:2:0.0')..failRead = true;
    await _pumpHome(tester, store);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('上次閱讀位置暫時無法載入'), findsOneWidget);
    expect(find.text('開始第一次閱讀'), findsNothing, reason: '不能讓人覆蓋還讀不到的位置');
    final retry = find.widgetWithText(TextButton, '再試一次');
    expect(
      tester
          .getSemantics(retry)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );

    store.failRead = false;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(find.text('約翰福音 2'), findsOneWidget);
    expect(find.text('上次閱讀位置暫時無法載入'), findsNothing);
    expect(store.reads, 2);
    expect(store.writes, isEmpty);
    handle.dispose();
  });

  testWidgets('375px 第一次使用（沒有存的位置）：讀完才顯示「開始第一次閱讀」', (tester) async {
    _phone(tester);
    final store = _FakeStore(null);
    await _pumpHome(tester, store);
    await tester.pumpAndSettle();
    expect(find.text('開始第一次閱讀'), findsOneWidget);
    expect(_container(tester).read(lastReadLoadProvider), LastReadLoad.ready);
  });

  testWidgets('讀取晚到不蓋掉期間已更新的新位置', (tester) async {
    _phone(tester);
    final store = _FakeStore('1:1:0.0')..gate = Completer<void>();
    await _pumpHome(tester, store);
    await tester.pump();
    final container = _container(tester);
    container.read(lastReadProvider);

    // 讀取還沒回來前，使用者已經讀到約翰福音 3 章
    await container.read(lastReadProvider.notifier).set(43, 3, 40);
    store.gate!.complete();
    await tester.pumpAndSettle();

    final pos = container.read(lastReadProvider);
    expect((pos?.bookId, pos?.chapter, pos?.offset), (43, 3, 40.0));
    expect(store.value, '43:3:40.0');
    expect(find.text('約翰福音 3'), findsOneWidget);
  });

  testWidgets('375px 存的位置對不上目前聖經資料：首頁與聖經頁都不當掉、可重新開始', (tester) async {
    _phone(tester);
    final store = _FakeStore('99:7:0.0');
    await _pumpHome(tester, store);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('開始第一次閱讀'), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(_FakeStore('43:9:0.0')),
        child: const MaterialApp(home: Scaffold(body: BibleHubScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('回到上次閱讀位置'), findsNothing);
    expect(find.text('閱讀聖經'), findsOneWidget);
  });

  testWidgets('375px 聖經頁位置讀取中：不閃出錯誤的繼續閱讀卡', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final store = _FakeStore('43:3:120.0')..gate = Completer<void>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(store),
        child: const MaterialApp(home: Scaffold(body: BibleHubScreen())),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.bySemanticsLabel('正在載入上次閱讀位置'), findsOneWidget);
    expect(find.text('回到上次閱讀位置'), findsNothing);

    store.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('約翰福音 第 3 章'), findsOneWidget);
    expect(find.text('回到上次閱讀位置'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('375px 聖經頁位置讀取失敗：顯示可朗讀錯誤並可重試', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final store = _FakeStore('43:2:0.0')..failRead = true;

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(store),
        child: const MaterialApp(home: Scaffold(body: BibleHubScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('上次閱讀位置暫時無法載入'), findsOneWidget);
    expect(find.text('回到上次閱讀位置'), findsNothing);

    store.failRead = false;
    await tester.tap(find.widgetWithText(TextButton, '再試一次'));
    await tester.pumpAndSettle();
    expect(find.text('約翰福音 第 2 章'), findsOneWidget);
    expect(store.reads, 2);
    handle.dispose();
  });

  testWidgets('375px 格式壞掉的舊位置：當作沒有位置，不顯示錯誤', (tester) async {
    _phone(tester);
    final store = _FakeStore('abc');
    await _pumpHome(tester, store);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('開始第一次閱讀'), findsOneWidget);
    expect(find.text('上次閱讀位置暫時無法載入'), findsNothing);
  });

  testWidgets('375px 位置寫入失敗：不擋閱讀，首頁顯示剛讀的位置', (tester) async {
    _phone(tester);
    final store = _FakeStore(null)..failWrite = true;
    await _pumpHome(tester, store);
    await tester.pumpAndSettle();

    await tester.tap(find.text('開始第一次閱讀'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ChapterScreen), findsOneWidget);
    expect(store.writes, isNotEmpty, reason: '有嘗試寫入');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('創世記 1'), findsOneWidget);
  });
}
