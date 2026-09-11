library;

/// 「我的研讀」R1 固定主題。這些是 private personal-data 分類，
/// 與 Admin `study_topics` 完全無關。
const List<String> kPrivateStudyTopics = [
  '神',
  '聖子',
  '聖靈',
  '耶穌',
  '經文',
  '作者的話語',
  '實踐',
  '月明洞',
  '其他',
];

class PrivateStudyBook {
  final String id;
  final String title;
  final String author;
  final int deletedAt;
  final int createdAt;
  final int updatedAt;
  final int lastStudiedAt;

  const PrivateStudyBook({
    required this.id,
    required this.title,
    this.author = '',
    this.deletedAt = 0,
    required this.createdAt,
    required this.updatedAt,
    required this.lastStudiedAt,
  });

  bool get isDeleted => deletedAt > 0;

  PrivateStudyBook copyWith({
    String? title,
    String? author,
    int? deletedAt,
    int? updatedAt,
    int? lastStudiedAt,
  }) =>
      PrivateStudyBook(
        id: id,
        title: title ?? this.title,
        author: author ?? this.author,
        deletedAt: deletedAt ?? this.deletedAt,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        lastStudiedAt: lastStudiedAt ?? this.lastStudiedAt,
      );

  factory PrivateStudyBook.fromMap(Map<String, dynamic> m) => PrivateStudyBook(
        id: m['id']?.toString() ?? m['book_id']?.toString() ?? '',
        title: m['title']?.toString() ?? '',
        author: m['author']?.toString() ?? '',
        deletedAt: (m['deleted_at'] as num?)?.toInt() ?? 0,
        createdAt: (m['created_at'] as num?)?.toInt() ?? 0,
        updatedAt: (m['updated_at'] as num?)?.toInt() ?? 0,
        lastStudiedAt: (m['last_studied_at'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toCloudMap() => {
        'book_id': id,
        'title': title,
        'author': author,
        'deleted_at': deletedAt,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'last_studied_at': lastStudiedAt,
      };
}

class PrivateStudyNote {
  final String id;
  final String bookId;
  final String quote;
  final List<String> topics;
  final String reflection;
  final List<String> scriptureRefs;
  final String sourceLocation;
  final String practice;
  final int deletedAt;
  final int createdAt;
  final int updatedAt;

  const PrivateStudyNote({
    required this.id,
    required this.bookId,
    this.quote = '',
    this.topics = const [],
    this.reflection = '',
    this.scriptureRefs = const [],
    this.sourceLocation = '',
    this.practice = '',
    this.deletedAt = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isDeleted => deletedAt > 0;

  /// 列表只顯示這個文字，不摘要、不改寫。
  String get displayText {
    for (final value in [quote, reflection, practice]) {
      final t = value.trim();
      if (t.isNotEmpty) return t;
    }
    return '未命名筆記';
  }

  bool get hasMeaningfulContent =>
      quote.trim().isNotEmpty ||
      topics.isNotEmpty ||
      reflection.trim().isNotEmpty ||
      scriptureRefs.any((e) => e.trim().isNotEmpty) ||
      sourceLocation.trim().isNotEmpty ||
      practice.trim().isNotEmpty;

  PrivateStudyNote copyWith({
    String? quote,
    List<String>? topics,
    String? reflection,
    List<String>? scriptureRefs,
    String? sourceLocation,
    String? practice,
    int? deletedAt,
    int? updatedAt,
  }) =>
      PrivateStudyNote(
        id: id,
        bookId: bookId,
        quote: quote ?? this.quote,
        topics: topics ?? this.topics,
        reflection: reflection ?? this.reflection,
        scriptureRefs: scriptureRefs ?? this.scriptureRefs,
        sourceLocation: sourceLocation ?? this.sourceLocation,
        practice: practice ?? this.practice,
        deletedAt: deletedAt ?? this.deletedAt,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toCloudMap() => {
        'note_id': id,
        'book_id': bookId,
        'quote': quote,
        'topics': topics,
        'reflection': reflection,
        'scripture_refs': scriptureRefs,
        'source_location': sourceLocation,
        'practice': practice,
        'deleted_at': deletedAt,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}
