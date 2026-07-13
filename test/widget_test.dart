import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/models/models.dart';
import 'package:bible_app/utils/text_utils.dart';

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

  group('Note tags', () {
    test('tagList 解析空格/逗號/井號分隔', () {
      const n = Note(
        bookId: 1,
        chapter: 1,
        verse: 1,
        content: '內容',
        tags: '信心 禱告，#感恩',
        createdAt: 0,
        updatedAt: 0,
      );
      expect(n.tagList, ['信心', '禱告', '感恩']);
    });

    test('toMap/fromMap 保留 tags', () {
      const n = Note(
        id: 1,
        bookId: 1,
        chapter: 1,
        verse: 1,
        content: 'c',
        tags: '標籤',
        createdAt: 1,
        updatedAt: 2,
      );
      expect(Note.fromMap(n.toMap()).tags, '標籤');
    });
  });

  group('SermonNote round-trip', () {
    test('toMap/fromMap 保留所有欄位', () {
      const s = SermonNote(
        id: 3,
        date: 111,
        title: '主題',
        scripture: '約3:16',
        content: '筆記',
        trinityWho: '聖靈',
        trinityWord: '祂的話',
        practice: '實踐',
        reflection: '感想',
        createdAt: 1,
        updatedAt: 2,
      );
      final r = SermonNote.fromMap(s.toMap());
      expect(r.title, '主題');
      expect(r.trinityWho, '聖靈');
      expect(r.reflection, '感想');
      expect(r.date, 111);
    });
  });

  group('sentenceWithMatch', () {
    test('取出含關鍵詞的那一句', () {
      const content = '今天讀經很有收穫。神的愛真奇妙。要記得禱告。';
      expect(sentenceWithMatch(content, '愛'), '神的愛真奇妙。');
    });

    test('找不到詞回傳開頭', () {
      expect(sentenceWithMatch('短內容', '不存在'), '短內容');
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
