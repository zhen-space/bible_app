/// 經文複製／分享的文字格式（純經文 vs 經文＋出處）。
///
/// Web 沒有可靠的原生分享（需 share_plus 外掛），因此「分享」在此
/// 統一走剪貼簿：格式化好文字讓使用者貼到任何 App。純格式轉換，不代寫內容。
library;

import '../models/models.dart';

/// 單節出處，例：「約翰福音 3:16」。
String verseCitation(Book book, int chapter, int verse) =>
    '${book.name} $chapter:$verse';

/// 多節出處，例：「約翰福音 3:16-18」或「約翰福音 3:16, 18」。
String versesCitation(Book book, int chapter, List<int> verses) {
  if (verses.isEmpty) return book.name;
  final sorted = [...verses]..sort();
  if (sorted.length == 1) return verseCitation(book, chapter, sorted.first);
  // 連續 → 用範圍；否則逗號列出。
  final contiguous = sorted.last - sorted.first == sorted.length - 1;
  if (contiguous) {
    return '${book.name} $chapter:${sorted.first}-${sorted.last}';
  }
  return '${book.name} $chapter:${sorted.join(', ')}';
}

/// 純經文（多節以換行接合）。
String plainVerses(List<String> texts) => texts.join('\n');

/// 經文＋出處（引號包經文、括號附出處）。
String versesWithCitation(List<String> texts, String citation) =>
    '「${texts.join('\n')}」（$citation）';
