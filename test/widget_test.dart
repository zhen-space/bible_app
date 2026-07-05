import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/models/models.dart';

void main() {
  group('Book.fromJson', () {
    test('parses asset schema', () {
      final book = Book.fromJson({
        'id': 1,
        'name': '創世記',
        'abbr': '創',
        'testament': 'ot',
        'chapters': [
          ['起初，　神創造天地。', '第二節'],
          ['第二章第一節'],
        ],
      });
      expect(book.id, 1);
      expect(book.chapterCount, 2);
      expect(book.chapters[0][0], contains('神創造天地'));
    });
  });

  group('Bookmark round-trip', () {
    test('toMap/fromMap', () {
      const b = Bookmark(
          id: 1, bookId: 43, chapter: 3, verse: 16, createdAt: 12345);
      final restored = Bookmark.fromMap(b.toMap());
      expect(restored.bookId, 43);
      expect(restored.chapter, 3);
      expect(restored.verse, 16);
    });
  });

  group('Highlight color stability', () {
    test('enum order must not change (persisted as index)', () {
      expect(HighlightColor.yellow.index, 0);
      expect(HighlightColor.green.index, 1);
      expect(HighlightColor.blue.index, 2);
      expect(HighlightColor.pink.index, 3);
      expect(HighlightColor.orange.index, 4);
    });
  });
}
