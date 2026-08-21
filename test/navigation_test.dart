import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/main.dart';
import 'package:bible_app/models/models.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/services/database_service.dart';

/// 不碰真 DB 的替身（widget test 環境沒有 sqflite plugin）。
class FakeDatabaseService extends DatabaseService {
  @override
  Future<Set<int>> getBookmarkedVerses(int bookId, int chapter) async => {};

  @override
  Future<Map<int, HighlightColor>> getChapterHighlights(
          int bookId, int chapter) async =>
      {};

  @override
  Future<Map<int, Note>> getChapterNotes(int bookId, int chapter) async => {};

  @override
  Future<void> markChapterRead(int bookId, int chapter) async {}

  @override
  Future<int> getReadChapterCount() async => 0;

  @override
  Future<List<Bookmark>> getAllBookmarks() async => [];

  @override
  Future<List<Highlight>> getAllHighlights() async => [];

  @override
  Future<List<Note>> getAllNotes() async => [];
}

List<Book> loadBooks() {
  final raw = File('assets/bible/cuv.json').readAsStringSync();
  final data = json.decode(raw) as Map<String, dynamic>;
  return (data['books'] as List)
      .map((b) => Book.fromJson(b as Map<String, dynamic>))
      .toList();
}

void main() {
  testWidgets('首頁 → 創世記 → 第 1 章 → 看到經文', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final books = loadBooks();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          booksProvider.overrideWith((ref) async => books),
          databaseServiceProvider.overrideWithValue(FakeDatabaseService()),
        ],
        child: const BibleApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 新版學生端主殼：底部導覽切到「聖經」→ 選擇書卷與章節 → 書卷列表
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('聖經')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('選擇書卷與章節'));
    await tester.pumpAndSettle();
    expect(find.text('創世記'), findsWidgets);
    await tester.tap(find.text('創世記').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('1').first);
    await tester.pumpAndSettle();

    // 讀經畫面：創 1:1（章層級導讀/重點已移除，讀經頁只有經文）
    expect(find.textContaining('起初', findRichText: true), findsWidgets);
    expect(find.text('創世記 第 1 章'), findsOneWidget);

    // 段落標題：來自章導讀「分段」欄（創1 範例第一行「1-2 起初：…」）
    expect(find.textContaining('起初：神創造天地'), findsWidgets);
  });

  testWidgets('章節格最前導讀、最後統整方格 → 開啟卷導讀頁', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final books = loadBooks();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          booksProvider.overrideWith((ref) async => books),
          databaseServiceProvider.overrideWithValue(FakeDatabaseService()),
          // 卷導讀無內容 → 立即回 null，避免轉圈動畫卡住 pumpAndSettle
          bookAnnotationProvider.overrideWith((ref, bookId) => null),
        ],
        child: const BibleApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 聖經 → 選擇書卷與章節 → 展開創世記，章節格前後應各有導讀/統整方格
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('聖經')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('選擇書卷與章節'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('創世記').first);
    await tester.pumpAndSettle();
    expect(find.text('導讀'), findsWidgets);
    expect(find.text('統整'), findsWidgets);

    // 點導讀方格 → 卷導讀頁（尚無內容顯示待填）
    await tester.tap(find.text('導讀').first);
    await tester.pumpAndSettle();
    expect(find.text('創世記 · 導讀'), findsOneWidget);
    expect(find.textContaining('尚未填寫'), findsOneWidget);
  });
}
