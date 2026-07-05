import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/topics.dart';
import 'package:bible_app/models/models.dart';
import 'package:bible_app/services/verse_locator.dart';

List<Book> loadBooks() {
  final raw = File('assets/bible/cuv.json').readAsStringSync();
  final data = json.decode(raw) as Map<String, dynamic>;
  return (data['books'] as List)
      .map((b) => Book.fromJson(b as Map<String, dynamic>))
      .toList();
}

void main() {
  final books = loadBooks();

  group('VerseLocator.parse', () {
    test('縮寫 + 章:節', () {
      final r = VerseLocator.parse('約3:16', books);
      expect(r, isNotNull);
      expect(r!.bookId, 43); // 約翰福音
      expect(r.chapter, 3);
      expect(r.verse, 16);
    });

    test('全名 + 全形冒號', () {
      final r = VerseLocator.parse('約翰福音 3：16', books);
      expect(r!.bookId, 43);
      expect(r.verse, 16);
    });

    test('只有章', () {
      final r = VerseLocator.parse('詩23', books);
      expect(r!.bookId, 19); // 詩篇
      expect(r.chapter, 23);
      expect(r.verse, isNull);
    });

    test('前綴模糊比對', () {
      final r = VerseLocator.parse('約翰3:16', books);
      expect(r!.bookId, 43);
    });

    test('超出範圍回傳 null', () {
      expect(VerseLocator.parse('創51:1', books), isNull); // 創世記只有 50 章
      expect(VerseLocator.parse('約3:999', books), isNull);
      expect(VerseLocator.parse('不存在的書3:1', books), isNull);
    });
  });

  group('主題經文資料', () {
    test('所有主題/情境的節位都必須有效', () {
      for (final t in [...topics, ...situations]) {
        for (final ref in t.refs) {
          final r = VerseLocator.parse(ref, books);
          expect(r, isNotNull, reason: '「${t.name}」的節位無效：$ref');
          expect(r!.verse, isNotNull, reason: '「${t.name}」缺節號：$ref');
        }
      }
    });

    test('每日經文池不為空且無重複', () {
      final pool = dailyVersePool();
      expect(pool, isNotEmpty);
      expect(pool.toSet().length, pool.length);
    });
  });

  group('聖經資料完整性', () {
    test('66 卷、1189 章、31102+ 節', () {
      expect(books.length, 66);
      final chapters =
          books.fold<int>(0, (sum, b) => sum + b.chapterCount);
      expect(chapters, 1189);
    });
  });
}
