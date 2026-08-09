import 'package:flutter_test/flutter_test.dart';
import 'package:bible_app/models/models.dart';
import 'package:bible_app/services/sermon_notes_io.dart';

void main() {
  group('證道筆記匯出／匯入', () {
    test('匯出後再匯入，欄位一致（round-trip）', () {
      final original = [
        SermonNote(
          date: DateTime(2026, 8, 9).millisecondsSinceEpoch,
          title: '恩典夠用',
          scripture: '林後 12:9',
          content: '第一行筆記\n第二行筆記',
          trinityWho: '耶穌',
          trinityWord: '我的恩典夠你用的',
          practice: '每天禱告',
          reflection: '深受感動',
          createdAt: 123,
          updatedAt: 456,
        ),
      ];

      final text = sermonNotesToText(original);
      final parsed = parseSermonNotes(text);

      expect(parsed, hasLength(1));
      final n = parsed.first;
      expect(n.title, '恩典夠用');
      expect(n.scripture, '林後 12:9');
      expect(n.content, '第一行筆記\n第二行筆記'); // 保留多行
      expect(n.trinityWho, '耶穌');
      expect(n.trinityWord, '我的恩典夠你用的');
      expect(n.practice, '每天禱告');
      expect(n.reflection, '深受感動');
      expect(DateTime.fromMillisecondsSinceEpoch(n.date),
          DateTime(2026, 8, 9));
    });

    test('多則筆記以 --- 分隔都解析得到', () {
      final notes = [
        SermonNote(
            date: DateTime(2026, 1, 1).millisecondsSinceEpoch,
            title: 'A',
            content: 'a',
            createdAt: 0,
            updatedAt: 0),
        SermonNote(
            date: DateTime(2026, 2, 2).millisecondsSinceEpoch,
            title: 'B',
            content: 'b',
            createdAt: 0,
            updatedAt: 0),
      ];
      final parsed = parseSermonNotes(sermonNotesToText(notes));
      expect(parsed.map((e) => e.title), ['A', 'B']);
    });

    test('分類為自填，任何文字都保留（並相容舊「位格」標籤）', () {
      const withNew = '''
#### 主題
測試
#### 分類
牧師的話
---
''';
      expect(parseSermonNotes(withNew).first.trinityWho, '牧師的話');

      const withOld = '''
#### 主題
測試
#### 位格
會友的話
---
''';
      expect(parseSermonNotes(withOld).first.trinityWho, '會友的話');
    });

    test('認不出格式回空陣列', () {
      expect(parseSermonNotes('這只是一段普通文字\n沒有任何小標'), isEmpty);
    });

    test('缺日期時給預設（不丟例外）', () {
      const text = '''
#### 主題
無日期筆記
#### 筆記
內容
---
''';
      final parsed = parseSermonNotes(text);
      expect(parsed, hasLength(1));
      expect(parsed.first.title, '無日期筆記');
      expect(parsed.first.date, greaterThan(0));
    });
  });
}
