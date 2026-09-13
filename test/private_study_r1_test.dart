import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bible_app/models/private_study.dart';
import 'package:bible_app/services/private_study_repository.dart';

void main() {
  group('我的研讀 model', () {
    test('固定九個 topics，不把未分類當正式 topic', () {
      expect(kPrivateStudyTopics, [
        '神', '聖子', '聖靈', '耶穌', '經文', '作者的話語', '實踐', '月明洞', '其他'
      ]);
      expect(kPrivateStudyTopics, isNot(contains('未分類')));
    });

    test('display text 依 quote → reflection → practice → 未命名筆記 fallback', () {
      PrivateStudyNote note({String quote = '', String reflection = '', String practice = ''}) =>
          PrivateStudyNote(id: 'n1', bookId: 'b1', quote: quote, reflection: reflection,
              practice: practice, createdAt: 1, updatedAt: 1);
      expect(note(quote: '原文').displayText, '原文');
      expect(note(reflection: '心得').displayText, '心得');
      expect(note(practice: '實踐').displayText, '實踐');
      expect(note().displayText, '未命名筆記');
    });

    test('Scripture Reference 與經文 topic 彼此獨立', () {
      final withRef = PrivateStudyNote(
          id: 'n1', bookId: 'b1', scriptureRefs: const ['約翰福音 3:16'], createdAt: 1, updatedAt: 1);
      final withTopic = PrivateStudyNote(
          id: 'n2', bookId: 'b1', topics: const ['經文'], createdAt: 1, updatedAt: 1);
      expect(withRef.topics, isEmpty);
      expect(withTopic.scriptureRefs, isEmpty);
    });

    test('一則 note 可複選多 topic，仍是單一 note entity', () {
      final n = PrivateStudyNote(
          id: 'n1', bookId: 'b1', topics: const ['神', '耶穌', '實踐'], createdAt: 1, updatedAt: 1);
      expect(n.topics, ['神', '耶穌', '實踐']);
    });
  });

  group('sync/cascade 決策', () {
    test('tombstone 防復活，較新 restore 可通過', () {
      expect(PrivateStudyRepository.tombstoneBlocksResurrection(200, 100), isTrue);
      expect(PrivateStudyRepository.tombstoneBlocksResurrection(100, 100), isTrue);
      expect(PrivateStudyRepository.tombstoneBlocksResurrection(100, 200), isFalse);
    });

    test('Book restore 只恢復同次 cascade notes', () {
      expect(PrivateStudyRepository.shouldRestoreCascadedNote(0, 5000), isFalse);
      expect(PrivateStudyRepository.shouldRestoreCascadedNote(5000, 5000), isTrue);
      expect(PrivateStudyRepository.shouldRestoreCascadedNote(4000, 5000), isFalse);
    });

    test('帳號歸屬 adopt / same / switch', () {
      expect(PrivateStudyRepository.ownerAction(null, 'A'), 'adopt');
      expect(PrivateStudyRepository.ownerAction('', 'A'), 'adopt');
      expect(PrivateStudyRepository.ownerAction('A', 'A'), 'same');
      expect(PrivateStudyRepository.ownerAction('A', 'B'), 'switch');
    });
  });

  test('local-first 首屏與背景 sync 不互相阻塞', () {
    final repo = _code(File('lib/services/private_study_repository.dart').readAsStringSync());
    final screen = _code(File('lib/screens/private_study_screen.dart').readAsStringSync());
    expect(repo, isNot(contains('await syncCurrentUser()')));
    expect(repo, contains('Future<List<PrivateStudyBook>> getBooks'));
    expect(repo, contains('Future<List<PrivateStudyNote>> getNotes'));
    expect(screen, contains('addPostFrameCallback'));
    expect(screen, contains('_backgroundSync'));
    expect(screen, contains('StudentCompactLoading'));
    expect(screen, contains('StudentErrorState'));
    expect(screen, contains('開始你的第一本研讀書籍'));
    expect(screen, contains("actionLabel: '新增書籍'"));
  });

  test('Student IA：我的研讀在 Bible / My Content 共用；老師專區由 capability gate', () {
    final bible = File('lib/screens/bible_hub_screen.dart').readAsStringSync();
    final mine = File('lib/screens/my_content_screen.dart').readAsStringSync();
    final home = File('lib/screens/student_home_screen.dart').readAsStringSync();
    final search = File('lib/screens/search_screen.dart').readAsStringSync();
    expect(bible, contains("'我的研讀'"));
    expect(mine, contains("'我的研讀'"));
    expect(bible, contains('PrivateStudyHomeScreen'));
    expect(mine, contains('PrivateStudyHomeScreen'));
    expect(home, isNot(contains("'我的研讀'")));
    // Teacher Area 入口已補回 Bible Hub，但仍以 capability provider 把關。
    expect(bible, contains("'老師專區'"));
    expect(bible, contains('teacherEntryVisibleProvider'));
    // Search 不呈現 Teacher Area organization context。
    expect(search, isNot(contains("'老師專區'")));
    expect(File('lib/screens/teacher_area_screen.dart').existsSync(), isTrue);
    expect(File('lib/services/church_repository.dart').existsSync(), isTrue);
  });

  test('我的研讀 private/local-first，不接 managed Study Content 或 Q&A source', () {
    final repository = File('lib/services/private_study_repository.dart').readAsStringSync();
    final screen = File('lib/screens/private_study_screen.dart').readAsStringSync();
    final code = _code(repository);
    expect(repository, contains("collection('users')"));
    expect(repository, contains("'private_study_books'"));
    expect(repository, contains("'private_study_notes'"));
    expect(repository, contains('DatabaseService'));
    expect(repository, contains("'tombstones'"));
    expect(code, isNot(contains("collection('study_content')")));
    expect(code, isNot(contains('AnswerSource')));
    expect(code, isNot(contains('allowedChurchIds')));
    expect(screen, contains('AppLinks.openVerseRef'));
    expect(screen, contains('已儲存在此裝置'));
    expect(screen, contains('ScriptureReferenceField'));
  });
}

String _code(String src) {
  final noBlock = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return noBlock.split('\n').map((line) {
    final i = line.indexOf('//');
    return i >= 0 ? line.substring(0, i) : line;
  }).join('\n');
}
