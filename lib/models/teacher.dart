/// 老師專區結構（Church/Teacher R1 §2.4）。**只負責組織/結構**；teaching body 永遠是
/// Study Content（以 `teacher_book_id`/`teacher_chapter_id` reference 掛上），不建 CMS。
/// Book/Chapter 本身也帶 audience 授權，避免 private hierarchy metadata leakage。
library;

import 'study_content.dart' show audienceAuthorized;
import 'managed_content.dart';

class TeacherBook {
  final String id;
  final String title;
  final String description;
  final int order;
  final ContentStatus status;
  final Audience? audience;
  final List<String> allowedChurchIds;

  const TeacherBook({
    required this.id,
    this.title = '',
    this.description = '',
    this.order = 0,
    this.status = ContentStatus.draft,
    this.audience,
    this.allowedChurchIds = const [],
  });

  bool authorizedFor(String? activeChurchId) => audienceAuthorized(
        status: status,
        audience: audience,
        allowedChurchIds: allowedChurchIds,
        activeChurchId: activeChurchId,
      );

  factory TeacherBook.fromDoc(String id, Map<String, dynamic> m) => TeacherBook(
        id: id,
        title: (m['title'] as String?) ?? '',
        description: (m['description'] as String?) ?? '',
        order: (m['order'] as int?) ?? 0,
        status: ContentStatus.fromName(m['status'] as String?),
        audience: Audience.fromName(m['audience'] as String?),
        allowedChurchIds: ((m['allowed_church_ids'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );

  Map<String, dynamic> toMap() => {
        'title': title,
        'description': description,
        'order': order,
        'status': status.name,
        if (audience != null) 'audience': audience!.name,
        'allowed_church_ids': allowedChurchIds,
      };
}

class TeacherChapter {
  final String id;
  final String bookId;
  final String title;
  final int order;
  final ContentStatus status;
  final Audience? audience;
  final List<String> allowedChurchIds;

  const TeacherChapter({
    required this.id,
    required this.bookId,
    this.title = '',
    this.order = 0,
    this.status = ContentStatus.draft,
    this.audience,
    this.allowedChurchIds = const [],
  });

  bool authorizedFor(String? activeChurchId) => audienceAuthorized(
        status: status,
        audience: audience,
        allowedChurchIds: allowedChurchIds,
        activeChurchId: activeChurchId,
      );

  factory TeacherChapter.fromDoc(String id, Map<String, dynamic> m) =>
      TeacherChapter(
        id: id,
        bookId: (m['book_id'] as String?) ?? '',
        title: (m['title'] as String?) ?? '',
        order: (m['order'] as int?) ?? 0,
        status: ContentStatus.fromName(m['status'] as String?),
        audience: Audience.fromName(m['audience'] as String?),
        allowedChurchIds: ((m['allowed_church_ids'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );

  Map<String, dynamic> toMap() => {
        'book_id': bookId,
        'title': title,
        'order': order,
        'status': status.name,
        if (audience != null) 'audience': audience!.name,
        'allowed_church_ids': allowedChurchIds,
      };
}
