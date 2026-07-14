import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/reading_plans.dart';
import 'package:bible_app/models/models.dart';
import 'package:bible_app/providers/providers.dart';
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

  group('ReadingPlan schedule', () {
    // 5 卷假書：章數 3,1,4,2,5 = 共 15 章
    final books = [
      for (var i = 1; i <= 5; i++)
        Book(
          id: i,
          name: '書$i',
          abbr: '書$i',
          testament: i <= 3 ? 'ot' : 'nt',
          chapters: List.generate([3, 1, 4, 2, 5][i - 1],
              (c) => ['第 ${c + 1} 章']),
        ),
    ];

    test('平均切成 N 天且不漏不重', () {
      const plan = ReadingPlan(
          id: 't', name: '測試', subtitle: '', emoji: '📖', days: 4);
      final sched = plan.schedule(books);
      expect(sched.length, 4);
      // 展平後應剛好等於全部 15 章、順序不變
      final flat = sched.expand((d) => d).toList();
      expect(flat.length, 15);
      expect(flat.first.bookId, 1);
      expect(flat.first.chapter, 1);
      expect(flat.last.bookId, 5);
      expect(flat.last.chapter, 5);
      // 15/4 → 前 3 天各 4 章、最後 1 天 3 章
      expect(sched.map((d) => d.length).toList(), [4, 4, 4, 3]);
    });

    test('scope=nt 只含新約', () {
      const plan = ReadingPlan(
          id: 't',
          name: '測試',
          subtitle: '',
          emoji: '✝️',
          days: 2,
          scope: 'nt');
      final flat = plan.schedule(books).expand((d) => d).toList();
      // 書4(2章)+書5(5章)=7 章
      expect(flat.length, 7);
      expect(flat.every((c) => c.bookId >= 4), true);
    });
  });

  group('HighlightLabels 持久化', () {
    test('設定→存→重載回得到相同標籤', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});

      final c1 = ProviderContainer();
      await c1
          .read(highlightLabelsProvider.notifier)
          .setLabel(HighlightColor.yellow, '應許');
      await c1
          .read(highlightLabelsProvider.notifier)
          .setLabel(HighlightColor.green, '命令');
      expect(c1.read(highlightLabelsProvider)[HighlightColor.yellow], '應許');
      c1.dispose();

      // 新容器重新從 prefs 載入
      final c2 = ProviderContainer();
      c2.read(highlightLabelsProvider); // 觸發 build/_load
      await Future<void>.delayed(Duration.zero);
      final labels = c2.read(highlightLabelsProvider);
      expect(labels[HighlightColor.yellow], '應許');
      expect(labels[HighlightColor.green], '命令');
      c2.dispose();
    });

    test('清空字串會移除標籤', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      final n = c.read(highlightLabelsProvider.notifier);
      await n.setLabel(HighlightColor.blue, '智慧');
      await n.setLabel(HighlightColor.blue, '  ');
      expect(c.read(highlightLabelsProvider).containsKey(HighlightColor.blue),
          false);
      c.dispose();
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
