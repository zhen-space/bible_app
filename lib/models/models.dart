/// 資料模型：聖經內容（唯讀，來自 asset）與使用者資料（存 SQLite）。
library;

/// 一卷書（含所有章節經文，App 啟動後常駐記憶體）。
class Book {
  final int id; // 1-66
  final String name; // 創世記
  final String abbr; // 創
  final String testament; // 'ot' | 'nt'
  final List<List<String>> chapters; // chapters[章-1][節-1] = 經文

  const Book({
    required this.id,
    required this.name,
    required this.abbr,
    required this.testament,
    required this.chapters,
  });

  int get chapterCount => chapters.length;

  factory Book.fromJson(Map<String, dynamic> json) => Book(
        id: json['id'] as int,
        name: json['name'] as String,
        abbr: json['abbr'] as String,
        testament: json['testament'] as String,
        chapters: (json['chapters'] as List)
            .map((ch) => (ch as List).cast<String>())
            .toList(),
      );
}

/// 一節經文的定位 + 內容（搜尋結果、書籤列表用）。
class VerseRef {
  final int bookId;
  final int chapter; // 1-based
  final int verse; // 1-based
  final String text;

  const VerseRef({
    required this.bookId,
    required this.chapter,
    required this.verse,
    this.text = '',
  });
}

/// 書籤。
class Bookmark {
  final int? id;
  final int bookId;
  final int chapter;
  final int verse;
  final int createdAt; // epoch millis

  const Bookmark({
    this.id,
    required this.bookId,
    required this.chapter,
    required this.verse,
    required this.createdAt,
  });

  factory Bookmark.fromMap(Map<String, dynamic> m) => Bookmark(
        id: m['id'] as int,
        bookId: m['book_id'] as int,
        chapter: m['chapter'] as int,
        verse: m['verse'] as int,
        createdAt: m['created_at'] as int,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'book_id': bookId,
        'chapter': chapter,
        'verse': verse,
        'created_at': createdAt,
      };
}

/// 螢光筆顏色（存 DB 用 index，勿改順序，只能往後加）。
enum HighlightColor { yellow, green, blue, pink, orange }

/// 螢光筆標記。
class Highlight {
  final int? id;
  final int bookId;
  final int chapter;
  final int verse;
  final HighlightColor color;
  final int createdAt;

  const Highlight({
    this.id,
    required this.bookId,
    required this.chapter,
    required this.verse,
    required this.color,
    required this.createdAt,
  });

  factory Highlight.fromMap(Map<String, dynamic> m) => Highlight(
        id: m['id'] as int,
        bookId: m['book_id'] as int,
        chapter: m['chapter'] as int,
        verse: m['verse'] as int,
        color: HighlightColor.values[m['color'] as int],
        createdAt: m['created_at'] as int,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'book_id': bookId,
        'chapter': chapter,
        'verse': verse,
        'color': color.index,
        'created_at': createdAt,
      };
}

/// 筆記。
class Note {
  final int? id;
  final int bookId;
  final int chapter;
  final int verse;
  final String content;
  final int createdAt;
  final int updatedAt;

  const Note({
    this.id,
    required this.bookId,
    required this.chapter,
    required this.verse,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Note.fromMap(Map<String, dynamic> m) => Note(
        id: m['id'] as int,
        bookId: m['book_id'] as int,
        chapter: m['chapter'] as int,
        verse: m['verse'] as int,
        content: m['content'] as String,
        createdAt: m['created_at'] as int,
        updatedAt: m['updated_at'] as int,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'book_id': bookId,
        'chapter': chapter,
        'verse': verse,
        'content': content,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}
