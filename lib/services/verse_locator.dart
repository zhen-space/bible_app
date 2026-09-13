import '../models/models.dart';

/// 經文節位解析：把「約3:16」「約翰福音 3:16」「詩23」解析成書卷/章/節。
/// 白板「三、搜尋與索引系統」的節位快速鍵。
class VerseLocator {
  /// 解析成功回傳 (bookId, chapter, verse)；verse 可為 null（整章）。
  /// 解析失敗或超出範圍回傳 null。
  static ({int bookId, int chapter, int? verse})? parse(
      String input, List<Book> books) {
    // 先 normalize，讓使用者不必配合特定鍵盤格式：
    // 全形冒號「：」→ 半形「:」、全形空格「　」→ 半形空格。
    final normalized = input
        .trim()
        .replaceAll('：', ':')
        .replaceAll('　', ' ');
    // 書卷名（不含數字/空白/冒號）→ 書卷與章之間可有空白或冒號分隔（也可無）→
    // 章 →（可選）節分隔（空白/冒號/點/篇）+ 節。
    final m = RegExp(r'^([^\d\s:]+)[\s:]*(\d{1,3})(?:[\s:.篇]\s*(\d{1,3}))?$')
        .firstMatch(normalized);
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
