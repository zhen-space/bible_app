import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/models.dart';

/// 聖經經文倉庫：從 asset 載入和合本 JSON，常駐記憶體（約 3MB 文字）。
/// 經文唯讀，不進 SQLite；搜尋直接掃記憶體（3.1 萬節，毫秒級）。
class BibleRepository {
  List<Book>? _books;

  Future<List<Book>> loadBooks() async {
    if (_books != null) return _books!;
    final raw = await rootBundle.loadString('assets/bible/cuv.json');
    final data = json.decode(raw) as Map<String, dynamic>;
    _books = (data['books'] as List)
        .map((b) => Book.fromJson(b as Map<String, dynamic>))
        .toList();
    return _books!;
  }

  Book bookById(int id) => _books![id - 1];

  /// 全文搜尋，回傳最多 [limit] 筆結果。
  List<VerseRef> search(String query, {int limit = 100}) {
    final books = _books;
    if (books == null || query.trim().isEmpty) return [];
    final q = query.trim();
    final results = <VerseRef>[];
    for (final book in books) {
      for (var c = 0; c < book.chapters.length; c++) {
        final verses = book.chapters[c];
        for (var v = 0; v < verses.length; v++) {
          if (verses[v].contains(q)) {
            results.add(VerseRef(
              bookId: book.id,
              chapter: c + 1,
              verse: v + 1,
              text: verses[v],
            ));
            if (results.length >= limit) return results;
          }
        }
      }
    }
    return results;
  }
}
