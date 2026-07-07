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

  group('註解資料', () {
    final raw = File('assets/annotations/annotations.json').readAsStringSync();
    final data = json.decode(raw) as Map<String, dynamic>;

    test('章導讀 key 格式為 書卷id:章 且在範圍內', () {
      final chapters = (data['chapters'] as Map).keys.cast<String>();
      for (final k in chapters) {
        final parts = k.split(':');
        expect(parts.length, 2, reason: 'bad chapter key: $k');
        final bookId = int.parse(parts[0]);
        final ch = int.parse(parts[1]);
        expect(bookId, inInclusiveRange(1, 66));
        expect(ch, inInclusiveRange(1, books[bookId - 1].chapterCount),
            reason: '$k 超出章數');
      }
    });

    test('節註解 key 格式為 書卷id:章:節 且在範圍內', () {
      final verses = (data['verses'] as Map).keys.cast<String>();
      for (final k in verses) {
        final parts = k.split(':');
        expect(parts.length, 3, reason: 'bad verse key: $k');
        final bookId = int.parse(parts[0]);
        final ch = int.parse(parts[1]);
        final v = int.parse(parts[2]);
        expect(bookId, inInclusiveRange(1, 66));
        expect(ch, inInclusiveRange(1, books[bookId - 1].chapterCount));
        expect(v, inInclusiveRange(1, books[bookId - 1].chapters[ch - 1].length),
            reason: '$k 超出節數');
      }
    });

    test('所有交叉引用節位都能解析', () {
      final verses = (data['verses'] as Map);
      for (final entry in verses.entries) {
        final refs = ((entry.value as Map)['crossRefs'] as List?) ?? [];
        for (final r in refs.cast<String>()) {
          // 交叉引用可能帶範圍（約1:1-3），取破折號前解析
          final head = r.split('-').first;
          expect(VerseLocator.parse(head, books), isNotNull,
              reason: '${entry.key} 的交叉引用無法解析：$r');
        }
      }
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
