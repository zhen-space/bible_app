import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bible_app/models/private_study.dart';
import 'package:bible_app/services/private_study_repository.dart';

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

    test('一則 note 可複選多 topic，仍是單一 note entity', () {
      final n = PrivateStudyNote(
        id: 'n1',
        bookId: 'b1',
        topics: const ['神', '耶穌', '實踐'],
        createdAt: 1,
        updatedAt: 1,
      );
      expect(n.topics, ['神', '耶穌', '實踐']);
      // 序列化來回仍是一筆、topics 保留。
      final back = PrivateStudyNote(
        id: n.id,
        bookId: n.bookId,
        topics: List<String>.from(n.toCloudMap()['topics'] as List),
        bookDeletedAt: (n.toCloudMap()['book_deleted_at'] as int),
        createdAt: 1,
        updatedAt: 1,
      );
      expect(back.topics, ['神', '耶穌', '實踐']);
      expect(back.bookDeletedAt, 0);
    });
  });

  group('sync/cascade 決策純函式（多裝置正確性核心）', () {
    test('#8 較新/同時 tombstone 擋下較舊 remote live（防復活）', () {
      expect(PrivateStudyRepository.tombstoneBlocksResurrection(200, 100), isTrue);
      expect(PrivateStudyRepository.tombstoneBlocksResurrection(100, 100), isTrue);
    });
    test('#9 較新 restore/edit 覆蓋較舊 tombstone（不被壓住）', () {
      expect(PrivateStudyRepository.tombstoneBlocksResurrection(100, 200), isFalse);
    });
    test('#6 Book 刪除前個別刪除的 note，Book restore 不復活', () {
      // 個別刪除 → bookDeletedAt==0 → 不隨任何 book cascade 復活。
      expect(PrivateStudyRepository.shouldRestoreCascadedNote(0, 5000), isFalse);
    });
    test('#7 隨 Book 級聯刪除的 note（bookDeletedAt==bookDeletedAt）可隨 Book restore', () {
      expect(PrivateStudyRepository.shouldRestoreCascadedNote(5000, 5000), isTrue);
      // 不同批次（另一次刪除）不復活
      expect(PrivateStudyRepository.shouldRestoreCascadedNote(4000, 5000), isFalse);
      // book 未刪（0）不會誤復活任何 note
      expect(PrivateStudyRepository.shouldRestoreCascadedNote(0, 0), isFalse);
    });
    test('#16 帳號歸屬：adopt / same / switch', () {
      expect(PrivateStudyRepository.ownerAction(null, 'A'), 'adopt');
      expect(PrivateStudyRepository.ownerAction('', 'A'), 'adopt');
      expect(PrivateStudyRepository.ownerAction('A', 'A'), 'same');
      expect(PrivateStudyRepository.ownerAction('A', 'B'), 'switch');
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
    // 兩入口共用同一 PrivateStudyHomeScreen（#17）。
    expect(bible, contains('PrivateStudyHomeScreen'));
    expect(home, isNot(contains("'我的研讀'")));
    expect(search, isNot(contains("'老師專區'")));
    expect(search, isNot(contains('TeacherAreaScreen')));
    // Teacher Area Student UI 完全移除（#19）：畫面檔不存在。
    expect(File('lib/screens/teacher_area_screen.dart').existsSync(), isFalse);
    // 但共用 Teacher/Church backend 不得誤刪（Q&A/Church 授權仍在）。
    expect(File('lib/services/church_repository.dart').existsSync(), isTrue);
  });

  test('我的研讀保持 private/local-first，未接 study_content 或 Q&A source', () {
    final repository =
        File('lib/services/private_study_repository.dart').readAsStringSync();
    final screen = File('lib/screens/private_study_screen.dart').readAsStringSync();
    // 契約 #21＝**不得有程式引用**（import/型別/欄位）。說明性註解描述「不做什麼」不算引用，
    // 因此 must-not-contain 一律對「去註解後」的原始碼判斷（否則會誤傷邊界說明註解）。
    final repoCode = _stripDartComments(repository);

    expect(repository, contains("collection('users')"));
    expect(repository, contains("'private_study_books'"));
    expect(repository, contains("'private_study_notes'"));
    expect(repository, contains('DatabaseService'));
    expect(repository, contains("'tombstones'"));
    expect(repoCode, isNot(contains("collection('study_content')")));
    expect(repoCode, isNot(contains('AnswerSource')));
    expect(repoCode, isNot(contains('allowedChurchIds')));
    expect(repoCode, isNot(contains('study_content')));
    expect(repoCode, isNot(contains('study_topics')));

    expect(screen, contains('AppLinks.openVerseRef'));
    expect(screen, contains('已儲存在此裝置'));
    expect(screen, isNot(contains("labelText: '筆記標題'")));
  });
}

/// 去除 Dart 行註解（//…）與區塊註解（/* … */），供「不得有程式引用」契約判斷。
String _stripDartComments(String src) {
  final noBlock = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return noBlock
      .split('\n')
      .map((line) {
        final i = line.indexOf('//');
        return i >= 0 ? line.substring(0, i) : line;
      })
      .join('\n');
}
