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

/// 章前導讀（白板「二、註解內容模組」的整篇前導讀）。
/// 內容來自 `assets/annotations/annotations.json`，唯讀、可缺（沒有就不顯示）。
class ChapterAnnotation {
  final String? summary; // 段落大意整理
  final String? purpose; // 目的
  final String? author; // 作者
  final String? background; // 歷史／文化背景
  final List<String> outline; // 分段大綱，例：「1-5 光的創造」
  final String? conclusion; // 章後統整：重點（一句話）

  const ChapterAnnotation({
    this.summary,
    this.purpose,
    this.author,
    this.background,
    this.outline = const [],
    this.conclusion,
  });

  bool get hasIntro =>
      summary != null ||
      purpose != null ||
      author != null ||
      background != null ||
      outline.isNotEmpty;

  factory ChapterAnnotation.fromJson(Map<String, dynamic> j) {
    final intro = (j['intro'] as Map<String, dynamic>?) ?? const {};
    return ChapterAnnotation(
      summary: intro['summary'] as String?,
      purpose: intro['purpose'] as String?,
      author: intro['author'] as String?,
      background: intro['background'] as String?,
      outline:
          (j['outline'] as List?)?.map((e) => e as String).toList() ?? const [],
      conclusion: j['conclusion'] as String?,
    );
  }
}

/// 整卷書層級的導讀與統整（獨立於各章，白板「二、註解內容模組」）。
/// 內容由使用者自己寫在 annotations.json 的 `books` 區；缺就顯示空白待填頁。
class BookAnnotation {
  final ChapterAnnotation? intro; // 導讀：大意/目的/作者/背景/分段
  final String? summary; // 統整：整卷重點

  const BookAnnotation({this.intro, this.summary});

  bool get hasIntro => intro != null && intro!.hasIntro;
  bool get hasSummary => summary != null && summary!.trim().isNotEmpty;

  factory BookAnnotation.fromJson(Map<String, dynamic> j) {
    final intro = ChapterAnnotation.fromJson(j);
    return BookAnnotation(
      intro: (intro.hasIntro) ? intro : null,
      summary: j['summary'] as String?,
    );
  }
}

/// 關鍵字解釋。
class Keyword {
  final String word;
  final String note;

  const Keyword(this.word, this.note);
}

/// 每節註解（注釋／生活應用／經文串連）。內容唯讀、可缺。
class VerseAnnotation {
  final String? commentary; // 注釋：每句背後意義
  final List<Keyword> keywords; // 關鍵字解釋
  final String? applicationCategory; // 生活應用分類
  final String? application; // 生活應用建議
  final List<String> crossRefs; // 經文串連（節位字串，可跳轉）

  const VerseAnnotation({
    this.commentary,
    this.keywords = const [],
    this.applicationCategory,
    this.application,
    this.crossRefs = const [],
  });

  factory VerseAnnotation.fromJson(Map<String, dynamic> j) {
    final app = j['application'] as Map<String, dynamic>?;
    return VerseAnnotation(
      commentary: j['commentary'] as String?,
      keywords: (j['keywords'] as List?)
              ?.map((e) => Keyword(
                  (e as Map)['word'] as String, e['note'] as String))
              .toList() ??
          const [],
      applicationCategory: app?['category'] as String?,
      application: app?['text'] as String?,
      crossRefs:
          (j['crossRefs'] as List?)?.map((e) => e as String).toList() ??
              const [],
    );
  }
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

/// 筆記。[tags] 為空格分隔的標籤字串（例：「信心 禱告」），可空。
class Note {
  final int? id;
  final int bookId;
  final int chapter;
  final int verse;
  final String content;
  final String tags;
  final int createdAt;
  final int updatedAt;

  const Note({
    this.id,
    required this.bookId,
    required this.chapter,
    required this.verse,
    required this.content,
    this.tags = '',
    required this.createdAt,
    required this.updatedAt,
  });

  List<String> get tagList =>
      tags.split(RegExp(r'[\s,，#]+')).where((t) => t.isNotEmpty).toList();

  factory Note.fromMap(Map<String, dynamic> m) => Note(
        id: m['id'] as int,
        bookId: m['book_id'] as int,
        chapter: m['chapter'] as int,
        verse: m['verse'] as int,
        content: m['content'] as String,
        tags: (m['tags'] as String?) ?? '',
        createdAt: m['created_at'] as int,
        updatedAt: m['updated_at'] as int,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'book_id': bookId,
        'chapter': chapter,
        'verse': verse,
        'content': content,
        'tags': tags,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}
