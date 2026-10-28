import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/models/models.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/screens/chapter_screen.dart';
import 'package:bible_app/services/database_service.dart';

/// 不碰真 DB；記錄書籤切換次數，確認狀態未知時不會寫入。
class _MarksDatabaseService extends DatabaseService {
  int toggleCalls = 0;

  @override
  Future<void> toggleBookmark(int bookId, int chapter, int verse) async {
    toggleCalls++;
  }

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

void main() {
  testWidgets('個人標記載入失敗：經文照常、書籤/筆記鎖住、重試後恢復', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const books = [
      Book(
        id: 1,
        name: '創世記',
        abbr: '創',
        testament: 'ot',
        chapters: [
          ['起初神創造天地'],
        ],
      ),
    ];
    final db = _MarksDatabaseService();
    var attempts = 0;
    var fail = true;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          booksProvider.overrideWith((ref) async => books),
          databaseServiceProvider.overrideWithValue(db),
          chapterMarksProvider.overrideWith((ref, args) async {
            attempts++;
            if (fail) throw Exception('db offline');
            return const ChapterMarks(
              bookmarks: {1},
              highlights: {},
              notes: {},
            );
          }),
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

    expect(find.textContaining('起初神創造天地'), findsWidgets);
    expect(find.text('個人標記暫時無法載入'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 節面板：書籤/筆記鎖住，不會用「空集合」誤切換。
    await tester.tap(find.textContaining('起初神創造天地').first);
    await tester.pumpAndSettle();
    expect(find.text('個人標記暫時無法載入，書籤與筆記請稍後再試。'), findsOneWidget);
    await tester.tap(find.text('書籤'));
    await tester.pumpAndSettle();
    expect(db.toggleCalls, 0);
    expect(find.text('個人標記暫時無法載入，書籤與筆記請稍後再試。'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // 多選批次書籤同樣停用。
    await tester.longPress(find.textContaining('起初神創造天地').first);
    await tester.pumpAndSettle();
    final bulkBookmark = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('書籤'),
        matching: find.byType(IconButton),
      ),
    );
    expect(bulkBookmark.onPressed, isNull);
    await tester.tap(find.byTooltip('取消選取'));
    await tester.pumpAndSettle();

    final before = attempts;
    fail = false;
    await tester.tap(find.widgetWithText(TextButton, '重試'));
    await tester.pumpAndSettle();

    expect(attempts, greaterThan(before));
    expect(find.text('個人標記暫時無法載入'), findsNothing);
    expect(find.byIcon(Icons.bookmark), findsOneWidget);

    await tester.tap(find.textContaining('起初神創造天地').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除書籤'));
    await tester.pumpAndSettle();
    expect(db.toggleCalls, 1);
  });
}
