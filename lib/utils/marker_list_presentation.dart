import '../models/models.dart';

enum MarkerSortOrder { recent, scripture }

MarkerSortOrder decodeMarkerSortOrder(String? value) {
  for (final order in MarkerSortOrder.values) {
    if (order.name == value) return order;
  }
  return MarkerSortOrder.recent;
}

List<Bookmark> sortBookmarksForList(
  Iterable<Bookmark> values,
  MarkerSortOrder order,
) {
  final items = values.toList();
  items.sort(
    (a, b) => switch (order) {
      MarkerSortOrder.recent => _recent(
        a.createdAt,
        b.createdAt,
        a.bookId,
        b.bookId,
        a.chapter,
        b.chapter,
        a.verse,
        b.verse,
      ),
      MarkerSortOrder.scripture => _scripture(
        a.bookId,
        b.bookId,
        a.chapter,
        b.chapter,
        a.verse,
        b.verse,
      ),
    },
  );
  return items;
}

List<Highlight> sortHighlightsForList(
  Iterable<Highlight> values,
  MarkerSortOrder order,
) {
  final items = values.toList();
  items.sort(
    (a, b) => switch (order) {
      MarkerSortOrder.recent => _recent(
        a.createdAt,
        b.createdAt,
        a.bookId,
        b.bookId,
        a.chapter,
        b.chapter,
        a.verse,
        b.verse,
      ),
      MarkerSortOrder.scripture => _scripture(
        a.bookId,
        b.bookId,
        a.chapter,
        b.chapter,
        a.verse,
        b.verse,
      ),
    },
  );
  return items;
}

int _recent(
  int aCreated,
  int bCreated,
  int aBook,
  int bBook,
  int aChapter,
  int bChapter,
  int aVerse,
  int bVerse,
) {
  final byDate = bCreated.compareTo(aCreated);
  return byDate != 0
      ? byDate
      : _scripture(aBook, bBook, aChapter, bChapter, aVerse, bVerse);
}

int _scripture(
  int aBook,
  int bBook,
  int aChapter,
  int bChapter,
  int aVerse,
  int bVerse,
) {
  final byBook = aBook.compareTo(bBook);
  if (byBook != 0) return byBook;
  final byChapter = aChapter.compareTo(bChapter);
  if (byChapter != 0) return byChapter;
  return aVerse.compareTo(bVerse);
}
