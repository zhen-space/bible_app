import '../models/models.dart';

/// 經文節位解析：把「約3:16」「約翰福音 3:16」「詩23」解析成書卷/章/節。
/// 白板「三、搜尋與索引系統」的節位快速鍵。
class VerseLocator {
  /// 解析成功回傳 (bookId, chapter, verse)；verse 可為 null（整章）。
  /// 解析失敗或超出範圍回傳 null。
  static ({int bookId, int chapter, int? verse})? parse(
      String input, List<Book> books) {
    final m = RegExp(r'^([^\d\s:：]+)\s*(\d{1,3})(?:[:：.篇\s]\s*(\d{1,3}))?$')
        .firstMatch(input.trim());
    if (m == null) return null;

    final name = m.group(1)!;
    final book = _findBook(name, books);
    if (book == null) return null;

    final chapter = int.parse(m.group(2)!);
    if (chapter < 1 || chapter > book.chapterCount) return null;

    final verseStr = m.group(3);
    if (verseStr == null) {
      return (bookId: book.id, chapter: chapter, verse: null);
    }
    final verse = int.parse(verseStr);
    if (verse < 1 || verse > book.chapters[chapter - 1].length) return null;
    return (bookId: book.id, chapter: chapter, verse: verse);
  }

  static Book? _findBook(String name, List<Book> books) {
    for (final b in books) {
      if (b.name == name || b.abbr == name) return b;
    }
    // 前綴模糊比對（「約翰」→ 約翰福音；注意「約」是縮寫直接命中約翰福音）
    for (final b in books) {
      if (b.name.startsWith(name)) return b;
    }
    return null;
  }
}
