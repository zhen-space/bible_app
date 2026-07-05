import 'dart:convert';
import 'dart:io';

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

    // 首頁：書卷列表 + 今日經文
    expect(find.text('創世記'), findsOneWidget);
    expect(find.text('今日經文'), findsOneWidget);

    // 展開創世記 → 點第 1 章
    await tester.tap(find.text('創世記'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1').first);
    await tester.pumpAndSettle();

    // 讀經畫面：創 1:1
    expect(find.textContaining('起初', findRichText: true), findsWidgets);
    expect(find.text('創世記 第 1 章'), findsOneWidget);
  });
}
