import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bible_app/models/private_study.dart';

void main() {
  group('我的研讀 model', () {
    test('固定九個 topics，不把未分類當正式 topic', () {
      expect(kPrivateStudyTopics, [
        '神',
        '聖子',
        '聖靈',
        '耶穌',
        '經文',
        '作者的話語',
        '實踐',
        '月明洞',
        '其他',
      ]);
      expect(kPrivateStudyTopics, isNot(contains('未分類')));
    });

    test('display text 依 quote → reflection → practice → 未命名筆記 fallback', () {
      PrivateStudyNote note({
        String quote = '',
        String reflection = '',
        String practice = '',
      }) =>
          PrivateStudyNote(
            id: 'n1',
            bookId: 'b1',
            quote: quote,
            reflection: reflection,
            practice: practice,
            createdAt: 1,
            updatedAt: 1,
          );

      expect(note(quote: '原文').displayText, '原文');
      expect(note(reflection: '心得').displayText, '心得');
      expect(note(practice: '實踐').displayText, '實踐');
      expect(note().displayText, '未命名筆記');
    });

    test('Scripture Reference 與經文 topic 彼此獨立', () {
      final withRef = PrivateStudyNote(
        id: 'n1',
        bookId: 'b1',
        scriptureRefs: const ['約翰福音 3:16'],
        createdAt: 1,
        updatedAt: 1,
      );
      final withTopic = PrivateStudyNote(
        id: 'n2',
        bookId: 'b1',
        topics: const ['經文'],
        createdAt: 1,
        updatedAt: 1,
      );
      expect(withRef.topics, isEmpty);
      expect(withTopic.scriptureRefs, isEmpty);
    });
  });

  test('Student IA 移除老師專區並在 Bible / My Content 共用我的研讀入口', () {
    final bible = File('lib/screens/bible_hub_screen.dart').readAsStringSync();
    final mine = File('lib/screens/my_content_screen.dart').readAsStringSync();
    final home = File('lib/screens/student_home_screen.dart').readAsStringSync();
    final search = File('lib/screens/search_screen.dart').readAsStringSync();

    expect(bible, contains("'書卷／章節導讀'"));
    expect(bible, contains("'聖經／信仰問答'"));
    expect(bible, contains("'研讀內容'"));
    expect(bible, contains("'我的研讀'"));
    expect(bible, isNot(contains("'老師專區'")));
    expect(bible, isNot(contains('TeacherAreaScreen')));

    expect(mine, contains("'我的研讀'"));
    expect(mine, contains('PrivateStudyHomeScreen'));
    expect(home, isNot(contains("'我的研讀'")));
    expect(search, isNot(contains("'老師專區'")));
  });

  test('我的研讀保持 private/local-first，未接 study_content 或 Q&A source', () {
    final repository =
        File('lib/services/private_study_repository.dart').readAsStringSync();
    final screen = File('lib/screens/private_study_screen.dart').readAsStringSync();

    expect(repository, contains("collection('users')"));
    expect(repository, contains("'private_study_books'"));
    expect(repository, contains("'private_study_notes'"));
    expect(repository, contains('DatabaseService'));
    expect(repository, contains("'tombstones'"));
    expect(repository, isNot(contains("collection('study_content')")));
    expect(repository, isNot(contains('AnswerSource')));
    expect(repository, isNot(contains('allowedChurchIds')));

    expect(screen, contains('AppLinks.openVerseRef'));
    expect(screen, contains('已儲存在此裝置'));
    expect(screen, isNot(contains("labelText: '筆記標題'")));
  });
}
