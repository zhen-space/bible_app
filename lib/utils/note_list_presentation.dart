import '../models/models.dart';
import 'query_utils.dart';

enum NoteSortOrder {
  updated('最近編輯'),
  created('最近建立'),
  title('標題'),
  scripture('經文位置');

  const NoteSortOrder(this.label);
  final String label;
}

NoteSortOrder decodeNoteSortOrder(String? value) {
  for (final order in NoteSortOrder.values) {
    if (order.name == value) return order;
  }
  return NoteSortOrder.updated;
}

List<Note> sortNotesForList(Iterable<Note> values, NoteSortOrder order) {
  final notes = values.toList();
  notes.sort((a, b) {
    switch (order) {
      case NoteSortOrder.updated:
        return _newestFirst(
          noteListTimestamp(a),
          noteListTimestamp(b),
          a.id,
          b.id,
        );
      case NoteSortOrder.created:
        return _newestFirst(a.createdAt, b.createdAt, a.id, b.id);
      case NoteSortOrder.title:
        final aTitle = a.title.trim();
        final bTitle = b.title.trim();
        if (aTitle.isEmpty != bTitle.isEmpty) return aTitle.isEmpty ? 1 : -1;
        final byTitle = aTitle.compareTo(bTitle);
        return byTitle != 0 ? byTitle : _byScripture(a, b);
      case NoteSortOrder.scripture:
        return _byScripture(a, b);
    }
  });
  return notes;
}

List<Note> searchNotesForList(
  Iterable<Note> values,
  String query, {
  String Function(Note note)? extraText,
}) {
  final terms = queryTerms(query);
  if (terms.isEmpty) return const [];

  final matches = values.where((note) {
    final searchable = [
      note.title,
      note.content,
      ...note.tagList,
      if (extraText != null) extraText(note),
    ]
        .join(' ')
        .toLowerCase();
    return terms.every(searchable.contains);
  }).toList();
  matches.sort((a, b) {
    final byRank = _noteSearchRank(a, terms).compareTo(_noteSearchRank(b, terms));
    if (byRank != 0) return byRank;
    return _newestFirst(
      noteListTimestamp(a),
      noteListTimestamp(b),
      a.id,
      b.id,
    );
  });
  return matches;
}

int _noteSearchRank(Note note, List<String> terms) {
  final title = note.title.toLowerCase();
  if (terms.every(title.contains)) return 0;
  final tags = note.tagList.join(' ').toLowerCase();
  if (terms.every(tags.contains)) return 1;
  return 2;
}

int noteListTimestamp(Note note) =>
    note.updatedAt > 0 ? note.updatedAt : note.createdAt;

int _newestFirst(int a, int b, int? aId, int? bId) {
  final byDate = b.compareTo(a);
  if (byDate != 0) return byDate;
  return (bId ?? 0).compareTo(aId ?? 0);
}

int _byScripture(Note a, Note b) {
  final byBook = a.bookId.compareTo(b.bookId);
  if (byBook != 0) return byBook;
  final byChapter = a.chapter.compareTo(b.chapter);
  if (byChapter != 0) return byChapter;
  final byVerse = a.verse.compareTo(b.verse);
  if (byVerse != 0) return byVerse;
  return (a.id ?? 0).compareTo(b.id ?? 0);
}

String noteDateSection(int millis, DateTime now) {
  final date = DateTime.fromMillisecondsSinceEpoch(millis);
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final difference = today.difference(day).inDays;
  if (difference <= 0) return '今天';
  if (difference == 1) return '昨天';
  if (difference < 7) return '最近 7 天';
  if (date.year == now.year) return '${date.month} 月';
  return '${date.year} 年';
}

String compactNoteDate(int millis, DateTime now) {
  final date = DateTime.fromMillisecondsSinceEpoch(millis);
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final difference = today.difference(day).inDays;
  if (difference == 0) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
  if (difference == 1) return '昨天';
  if (date.year == now.year) return '${date.month}/${date.day}';
  return '${date.year}/${date.month}/${date.day}';
}
