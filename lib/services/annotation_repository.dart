import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/models.dart';

/// 註解內容倉庫：從 asset 載入導讀/注釋（白板「二、註解內容模組」）。
///
/// 內容是**可插拔**的：目前只有少數示範章節，之後補內容只要編輯
/// `assets/annotations/annotations.json`，格式如下——
/// ```
/// {
///   "chapters": { "1:1": { "intro": {...}, "outline": [...], "conclusion": "..." } },
///   "verses":   { "1:1:1": { "commentary": "...", "keywords": [...],
///                            "application": {"category":"...","text":"..."},
///                            "crossRefs": ["約1:1"] } }
/// }
/// ```
/// key 用 `書卷id:章`（章註解）與 `書卷id:章:節`（節註解）。缺就不顯示。
class AnnotationRepository {
  Map<String, BookAnnotation>? _books;
  Map<String, ChapterAnnotation>? _chapters;
  Map<String, VerseAnnotation>? _verses;

  Future<void> _ensureLoaded() async {
    if (_chapters != null) return;
    try {
      final raw =
          await rootBundle.loadString('assets/annotations/annotations.json');
      final data = json.decode(raw) as Map<String, dynamic>;
      _books = ((data['books'] as Map?) ?? {}).map((k, v) => MapEntry(
          k as String, BookAnnotation.fromJson(v as Map<String, dynamic>)));
      _chapters = ((data['chapters'] as Map?) ?? {}).map((k, v) => MapEntry(
          k as String,
          ChapterAnnotation.fromJson(v as Map<String, dynamic>)));
      _verses = ((data['verses'] as Map?) ?? {}).map((k, v) => MapEntry(
          k as String, VerseAnnotation.fromJson(v as Map<String, dynamic>)));
    } catch (_) {
      // asset 缺失或格式錯誤：當作沒有註解，不擋讀經。
      _books = {};
      _chapters = {};
      _verses = {};
    }
  }

  /// 整卷書的導讀＋統整（沒有就回 null，頁面顯示待填空白）。
  Future<BookAnnotation?> book(int bookId) async {
    await _ensureLoaded();
    return _books!['$bookId'];
  }

  Future<ChapterAnnotation?> chapter(int bookId, int chapter) async {
    await _ensureLoaded();
    return _chapters!['$bookId:$chapter'];
  }

  /// 該章所有有註解的節（verseNo → 註解）。
  Future<Map<int, VerseAnnotation>> versesIn(int bookId, int chapter) async {
    await _ensureLoaded();
    final prefix = '$bookId:$chapter:';
    final out = <int, VerseAnnotation>{};
    _verses!.forEach((k, v) {
      if (k.startsWith(prefix)) {
        final verse = int.tryParse(k.substring(prefix.length));
        if (verse != null) out[verse] = v;
      }
    });
    return out;
  }
}
