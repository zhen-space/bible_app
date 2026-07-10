import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/models.dart';

/// 聖經經文倉庫：從 asset 載入和合本 JSON，常駐記憶體（約 3MB 文字）。
/// 經文唯讀，不進 SQLite；搜尋直接掃記憶體（3.1 萬節，毫秒級）。
class BibleRepository {
  List<Book>? _books;
  // 英文對照（KJV）：english[bookId-1][章-1][節-1]。首次需要時才載入。
  List<List<List<String>>>? _english;

  Future<List<Book>> loadBooks() async {
    if (_books != null) return _books!;
    final raw = await rootBundle.loadString('assets/bible/cuv.json');
    final data = json.decode(raw) as Map<String, dynamic>;
    _books = (data['books'] as List)
        .map((b) => Book.fromJson(b as Map<String, dynamic>))
        .toList();
    return _books!;
  }

  /// 載入英文 KJV（4.5MB，只有開啟英文對照時才載）。
  Future<void> loadEnglish() async {
    if (_english != null) return;
    final raw = await rootBundle.loadString('assets/bible/kjv.json');
    final data = json.decode(raw) as Map<String, dynamic>;
    final books = (data['books'] as List)
        .cast<Map<String, dynamic>>()
      ..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
    _english = books
        .map((b) => (b['chapters'] as List)
            .map((ch) => (ch as List).cast<String>())
            .toList())
        .toList();
  }

  bool get englishLoaded => _english != null;

  /// 取某節英文；沒有（版本節數差異）就回 null。
  String? english(int bookId, int chapter, int verse) {
    final e = _english;
    if (e == null || bookId < 1 || bookId > e.length) return null;
    final chapters = e[bookId - 1];
    if (chapter < 1 || chapter > chapters.length) return null;
    final verses = chapters[chapter - 1];
    if (verse < 1 || verse > verses.length) return null;
    return verses[verse - 1];
  }

  Book bookById(int id) => _books![id - 1];

  /// 全文搜尋。先找完全符合（子字串），不足時用模糊（子序列：查詢字依序出現，
  /// 中間可夾雜其他字）補上——打字漏字、順序拆開也找得到。
  List<VerseRef> search(String query, {int limit = 100, bool fuzzy = true}) {
    final books = _books;
    if (books == null) return [];
    // 去除空白與常見標點，讓「約 3 16」「神・愛」之類也能比對
    final q = _normalize(query);
    if (q.isEmpty) return [];

    final exact = <VerseRef>[];
    final loose = <VerseRef>[];
    for (final book in books) {
      for (var c = 0; c < book.chapters.length; c++) {
        final verses = book.chapters[c];
        for (var v = 0; v < verses.length; v++) {
          final raw = verses[v];
          final norm = _normalize(raw);
          if (norm.contains(q)) {
            exact.add(VerseRef(
                bookId: book.id, chapter: c + 1, verse: v + 1, text: raw));
            if (exact.length >= limit) return exact;
          } else if (fuzzy && q.length >= 2 && _isSubsequence(q, norm)) {
            if (loose.length < limit) {
              loose.add(VerseRef(
                  bookId: book.id, chapter: c + 1, verse: v + 1, text: raw));
            }
          }
        }
      }
    }
    final out = exact;
    for (final r in loose) {
      if (out.length >= limit) break;
      out.add(r);
    }
    return out;
  }

  static String _normalize(String s) =>
      s.replaceAll(RegExp(r'[\s，、。；：！？「」『』（）,.;:!?()　]'), '');

  /// q 的每個字是否依序出現在 text 中（子序列）。
  static bool _isSubsequence(String q, String text) {
    var i = 0;
    for (var j = 0; j < text.length && i < q.length; j++) {
      if (text[j] == q[i]) i++;
    }
    return i == q.length;
  }
}
