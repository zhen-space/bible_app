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
  final String? commentary; // 注釋：每句背後意義（字義）
  final List<Keyword> keywords; // 關鍵字解釋（字義）
  final String? background; // 這一節的歷史／文化背景
  final String? applicationCategory; // 生活應用分類
  final String? application; // 生活應用建議
  final List<String> crossRefs; // 經文串連（節位字串，可跳轉）
  final int? updatedAt; // 雲端最後更新時間（版本化；asset 內容為 null）

  const VerseAnnotation({
    this.commentary,
    this.keywords = const [],
    this.background,
    this.applicationCategory,
    this.application,
    this.crossRefs = const [],
    this.updatedAt,
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
      background: j['background'] as String?,
      applicationCategory: app?['category'] as String?,
      application: app?['text'] as String?,
      crossRefs:
          (j['crossRefs'] as List?)?.map((e) => e as String).toList() ??
              const [],
      updatedAt: j['updated_at'] as int?,
    );
  }
}

/// 禱告事項（首頁區塊）：分類/子分類/內容，使用者自行增刪，不設打勾。
/// 禱告事項狀態。
enum PrayerStatus {
  praying, // 禱告中
  answered, // 已蒙應允
  ended; // 已結束（不再禱告，但非應允）

  static PrayerStatus fromName(String? s) => PrayerStatus.values.firstWhere(
      (e) => e.name == s,
      orElse: () => PrayerStatus.praying);

  String get label => switch (this) {
        PrayerStatus.praying => '禱告中',
        PrayerStatus.answered => '已蒙應允',
        PrayerStatus.ended => '已結束',
      };
}

/// 禱告事項（v2）。舊欄位 category/subcategory 保留供既有資料相容；
/// v2 新增：可選 title、prayer date、多節引用 refs、狀態、提醒、應允日期與回顧。
class Prayer {
  final int? id;
  final String category; // 舊：分類（例：家人）
  final String subcategory; // 舊：子分類（例：爸爸）
  final String title; // v2：標題（可空）
  final String content; // 禱告內容
  final int prayerDate; // v2：禱告日期（ms，0＝未設）
  final List<String> refs; // v2：相關經文 'b_c_v'
  final PrayerStatus status; // v2：狀態
  final int reminderAt; // v2：提醒時間（ms，0＝無）
  final int answeredAt; // v2：應允/結束日期（ms，0＝無）
  final String answeredReflection; // v2：應允後回顧
  final int createdAt;
  final int updatedAt;

  const Prayer({
    this.id,
    this.category = '',
    this.subcategory = '',
    this.title = '',
    this.content = '',
    this.prayerDate = 0,
    this.refs = const [],
    this.status = PrayerStatus.praying,
    this.reminderAt = 0,
    this.answeredAt = 0,
    this.answeredReflection = '',
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  Prayer copyWith({
    String? title,
    String? content,
    int? prayerDate,
    List<String>? refs,
    PrayerStatus? status,
    int? reminderAt,
    int? answeredAt,
    String? answeredReflection,
  }) =>
      Prayer(
        id: id,
        category: category,
        subcategory: subcategory,
        title: title ?? this.title,
        content: content ?? this.content,
        prayerDate: prayerDate ?? this.prayerDate,
        refs: refs ?? this.refs,
        status: status ?? this.status,
        reminderAt: reminderAt ?? this.reminderAt,
        answeredAt: answeredAt ?? this.answeredAt,
        answeredReflection: answeredReflection ?? this.answeredReflection,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  static List<String> _parseRefs(String? csv) =>
      (csv ?? '').split(',').where((s) => s.trim().isNotEmpty).toList();

  factory Prayer.fromMap(Map<String, dynamic> m) => Prayer(
        id: m['id'] as int?,
        category: m['category'] as String? ?? '',
        subcategory: m['subcategory'] as String? ?? '',
        title: m['title'] as String? ?? '',
        content: m['content'] as String? ?? '',
        prayerDate: m['prayer_date'] as int? ?? 0,
        refs: _parseRefs(m['refs'] as String?),
        status: PrayerStatus.fromName(m['status'] as String?),
        reminderAt: m['reminder_at'] as int? ?? 0,
        answeredAt: m['answered_at'] as int? ?? 0,
        answeredReflection: m['answered_reflection'] as String? ?? '',
        createdAt: m['created_at'] as int? ?? 0,
        updatedAt: m['updated_at'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'category': category,
        'subcategory': subcategory,
        'title': title,
        'content': content,
        'prayer_date': prayerDate,
        'refs': refs.join(','),
        'status': status.name,
        'reminder_at': reminderAt,
        'answered_at': answeredAt,
        'answered_reflection': answeredReflection,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}

/// 信仰生活代辦事項（首頁區塊）：分類/內容/完成狀態，**可打勾**（與禱告不同）。
class Todo {
  final int? id;
  final String category; // 分類（例：靈修、服事、關懷）
  final String content;
  final bool done;
  final int createdAt;
  final int updatedAt;

  const Todo({
    this.id,
    this.category = '',
    this.content = '',
    this.done = false,
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  Todo copyWith({bool? done}) => Todo(
        id: id,
        category: category,
        content: content,
        done: done ?? this.done,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  factory Todo.fromMap(Map<String, dynamic> m) => Todo(
        id: m['id'] as int?,
        category: m['category'] as String? ?? '',
        content: m['content'] as String? ?? '',
        done: (m['done'] as int? ?? 0) == 1,
        createdAt: m['created_at'] as int? ?? 0,
        updatedAt: m['updated_at'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'category': category,
        'content': content,
        'done': done ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}

/// 主日／證道筆記（結構化表單，白板「五、個人信仰整理」）。
class SermonNote {
  final int? id;
  final int date; // 講道日期（epoch millis）
  final String title; // 主題
  final String scripture; // 經文
  final String content; // 筆記
  final String trinityWho; // 神／聖子／聖靈／耶穌（選擇）
  final String trinityWord; // 該位格的話
  final String practice; // 實踐
  final String reflection; // 感想
  final int createdAt;
  final int updatedAt;

  const SermonNote({
    this.id,
    required this.date,
    this.title = '',
    this.scripture = '',
    this.content = '',
    this.trinityWho = '',
    this.trinityWord = '',
    this.practice = '',
    this.reflection = '',
    required this.createdAt,
    required this.updatedAt,
  });

  factory SermonNote.fromMap(Map<String, dynamic> m) => SermonNote(
        id: m['id'] as int?,
        date: m['date'] as int,
        title: (m['title'] as String?) ?? '',
        scripture: (m['scripture'] as String?) ?? '',
        content: (m['content'] as String?) ?? '',
        trinityWho: (m['trinity_who'] as String?) ?? '',
        trinityWord: (m['trinity_word'] as String?) ?? '',
        practice: (m['practice'] as String?) ?? '',
        reflection: (m['reflection'] as String?) ?? '',
        createdAt: m['created_at'] as int,
        updatedAt: m['updated_at'] as int,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'date': date,
        'title': title,
        'scripture': scripture,
        'content': content,
        'trinity_who': trinityWho,
        'trinity_word': trinityWord,
        'practice': practice,
        'reflection': reflection,
        'created_at': createdAt,
        'updated_at': updatedAt,
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

/// 筆記（v2）。[tags] 為空格分隔的標籤字串（例：「信心 禱告」），可空。
///
/// v2 新增：可選 [title]、額外多節引用 [refs]（錨點仍是 book/chapter/verse，
/// refs 為「除錨點外」的其他節位字串 'b_c_v'，CSV 儲存）、以及軟刪除 [deletedAt]
/// （0＝正常；>0＝在「最近刪除」）。全部向後相容（舊資料缺欄位以預設值帶入）。
class Note {
  final int? id;
  final int bookId;
  final int chapter;
  final int verse;
  final String title;
  final String content;
  final String tags;

  /// 額外引用（除錨點外）：每個元素 'b{book}_c{chapter}_v{verse}'。
  final List<String> refs;
  final int deletedAt;
  final int createdAt;
  final int updatedAt;

  const Note({
    this.id,
    required this.bookId,
    required this.chapter,
    required this.verse,
    this.title = '',
    required this.content,
    this.tags = '',
    this.refs = const [],
    this.deletedAt = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isDeleted => deletedAt > 0;

  List<String> get tagList =>
      tags.split(RegExp(r'[\s,，#]+')).where((t) => t.isNotEmpty).toList();

  /// 全部引用（錨點在最前）。
  List<({int bookId, int chapter, int verse})> get allRefs {
    final out = <({int bookId, int chapter, int verse})>[
      (bookId: bookId, chapter: chapter, verse: verse),
    ];
    for (final r in refs) {
      final m = RegExp(r'^b(\d+)_c(\d+)_v(\d+)$').firstMatch(r);
      if (m != null) {
        out.add((
          bookId: int.parse(m.group(1)!),
          chapter: int.parse(m.group(2)!),
          verse: int.parse(m.group(3)!),
        ));
      }
    }
    return out;
  }

  static List<String> _parseRefs(String? csv) =>
      (csv ?? '').split(',').where((s) => s.trim().isNotEmpty).toList();

  factory Note.fromMap(Map<String, dynamic> m) => Note(
        id: m['id'] as int?,
        bookId: m['book_id'] as int,
        chapter: m['chapter'] as int,
        verse: m['verse'] as int,
        title: (m['title'] as String?) ?? '',
        content: m['content'] as String,
        tags: (m['tags'] as String?) ?? '',
        refs: _parseRefs(m['refs'] as String?),
        deletedAt: (m['deleted_at'] as int?) ?? 0,
        createdAt: m['created_at'] as int,
        updatedAt: m['updated_at'] as int,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'book_id': bookId,
        'chapter': chapter,
        'verse': verse,
        'title': title,
        'content': content,
        'tags': tags,
        'refs': refs.join(','),
        'deleted_at': deletedAt,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}
