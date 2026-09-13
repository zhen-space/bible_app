import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/models/study_content.dart';

/// Teacher Area 產品功能已退休（Student + Admin UI 皆移除；TeacherRepository /
/// fetchAuthorizedTeachings / adminListTeachings 已刪）。
///
/// 但 StudyContentItem 的「兩類經文（teacherScriptureRefs vs scriptureRefs）＋來源位置
/// （sourceLocation）」是 **additive、backward-compatible 的一般資料欄位**，仍被一般
/// Student 研讀內容詳情呈現、且既有 doc 依賴，故保留。這裡守住其 round-trip 與不污染既有欄位。
void main() {
  group('Study Content 兩類經文 + 來源位置（additive、backward-compatible）', () {
    test('teacherScriptureRefs / sourceLocation 與既有 scriptureRefs 各自獨立、round-trip', () {
      final it = StudyContentItem(
        id: 't1',
        status: ContentStatus.published,
        visibility: Visibility.student,
        contentType: StudyContentType.topicArticle,
        scriptureRefs: const ['約3:16'], // 整理者相關經文
        teacherScriptureRefs: const ['羅5:8', '弗2:8'], // 老師原文引用
        sourceLocation: '第 42 頁',
      );
      final back = StudyContentItem.fromManaged(it.toManaged());
      expect(back.scriptureRefs, ['約3:16']);
      expect(back.teacherScriptureRefs, ['羅5:8', '弗2:8']);
      expect(back.sourceLocation, '第 42 頁');
      // 兩類彼此不污染。
      expect(back.scriptureRefs, isNot(contains('羅5:8')));
    });

    test('無這些欄位時 payload 不含該 key（維持既有 doc 形狀），舊 doc 解析為空不報錯', () {
      final it = StudyContentItem(
        id: 't2',
        status: ContentStatus.draft,
        visibility: Visibility.internal,
        contentType: StudyContentType.parallel,
        scriptureRefs: const ['創1:1'],
      );
      final p = it.payload;
      expect(p.containsKey('teacher_scripture_refs'), isFalse);
      expect(p.containsKey('source_location'), isFalse);
      expect(p['scripture_refs'], ['創1:1']);

      final legacy = StudyContentItem.fromDoc('t2', {
        'content_id': 't2',
        'content_type': 'topic_article',
        'status': 'published',
        'visibility': 'student',
        'scripture_refs': ['創1:1'],
      });
      expect(legacy.teacherScriptureRefs, isEmpty);
      expect(legacy.sourceLocation, '');
      expect(legacy.scriptureRefs, ['創1:1']);
    });
  });
}
