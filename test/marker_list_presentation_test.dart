import 'package:bible_app/models/models.dart';
import 'package:bible_app/utils/marker_list_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('排序偏好可安全還原', () {
    expect(decodeMarkerSortOrder('scripture'), MarkerSortOrder.scripture);
    expect(decodeMarkerSortOrder('unknown'), MarkerSortOrder.recent);
    expect(decodeMarkerSortOrder(null), MarkerSortOrder.recent);
  });

  test('書籤可依最近加入或經文位置排序', () {
    final items = [
      const Bookmark(bookId: 43, chapter: 3, verse: 16, createdAt: 30),
      const Bookmark(bookId: 1, chapter: 1, verse: 1, createdAt: 10),
      const Bookmark(bookId: 19, chapter: 23, verse: 1, createdAt: 20),
    ];
    expect(
      sortBookmarksForList(items, MarkerSortOrder.recent).map((e) => e.bookId),
      [43, 19, 1],
    );
    expect(
      sortBookmarksForList(
        items,
        MarkerSortOrder.scripture,
      ).map((e) => e.bookId),
      [1, 19, 43],
    );
  });

  test('螢光筆可依最近加入或經文位置排序', () {
    final items = [
      const Highlight(
        bookId: 43,
        chapter: 3,
        verse: 16,
        color: HighlightColor.yellow,
        createdAt: 30,
      ),
      const Highlight(
        bookId: 1,
        chapter: 1,
        verse: 1,
        color: HighlightColor.green,
        createdAt: 10,
      ),
    ];
    expect(
      sortHighlightsForList(items, MarkerSortOrder.recent).map((e) => e.bookId),
      [43, 1],
    );
    expect(
      sortHighlightsForList(
        items,
        MarkerSortOrder.scripture,
      ).map((e) => e.bookId),
      [1, 43],
    );
  });
}
