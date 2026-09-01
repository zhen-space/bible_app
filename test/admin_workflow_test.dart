import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/models/study_content.dart';
import 'package:bible_app/services/content_service.dart';
import 'package:bible_app/services/content_workflow_service.dart';
import 'package:bible_app/services/qa_service.dart';
import 'package:bible_app/services/study_content_repository.dart';

const _admin = 'admin@example.com';

StudyContentRepository _repo(FakeFirebaseFirestore fs) =>
    StudyContentRepository(fs, ContentWorkflowService(fs));

/// 建立一則已發佈的 study content（走正式工作流），回傳 repo。
Future<StudyContentRepository> _seedPublished(
  FakeFirebaseFirestore fs,
  String id, {
  required Visibility visibility,
}) async {
  final repo = _repo(fs);
  await repo.saveContentDraft(id,
      type: StudyContentType.topicArticle,
      payload: {'title': '題目 $id', 'body': '內文', 'data': {}},
      editorEmail: _admin,
      visibility: visibility);
  await repo.submitContentForReview(id, _admin);
  await repo.publishContent(id, _admin);
  return repo;
}

void main() {
  group('Study Content workflow', () {
    test('1. 新內容預設 Draft + Internal', () async {
      final fs = FakeFirebaseFirestore();
      final repo = _repo(fs);
      await repo.saveContentDraft('c1',
          type: StudyContentType.topicArticle,
          payload: {'title': 'x', 'data': {}},
          editorEmail: _admin);
      final ws = await repo.adminGetContentWorkspace('c1');
      expect(ws!.status, ContentStatus.draft);
      expect(ws.visibility, Visibility.internal);
    });

    test('2. Draft 階段可改 student visibility', () async {
      final fs = FakeFirebaseFirestore();
      final repo = _repo(fs);
      await repo.saveContentDraft('c1',
          type: StudyContentType.topicArticle,
          payload: {'title': 'x', 'data': {}},
          editorEmail: _admin,
          visibility: Visibility.student);
      final ws = await repo.adminGetContentWorkspace('c1');
      expect(ws!.visibility, Visibility.student);
    });

    test('3. 送審後狀態為 review（作者端 UI 不可再直接編輯）', () async {
      final fs = FakeFirebaseFirestore();
      final repo = _repo(fs);
      await repo.saveContentDraft('c1',
          type: StudyContentType.topicArticle,
          payload: {'title': 'x', 'data': {}},
          editorEmail: _admin);
      await repo.submitContentForReview('c1', _admin);
      final ws = await repo.adminGetContentWorkspace('c1');
      expect(ws!.status, ContentStatus.review);
    });

    test('4. Published + Internal：學生取不到', () async {
      final fs = FakeFirebaseFirestore();
      await _seedPublished(fs, 'c1', visibility: Visibility.internal);
      final repo = _repo(fs);
      final pub = await repo.adminGetContentPublished('c1');
      expect(pub!.status, ContentStatus.published);
      expect(pub.visibility, Visibility.internal);
      final student = await repo.fetchStudentStudyContent();
      expect(student, isEmpty);
      expect(await repo.fetchStudentStudyContentById('c1'), isNull);
    });

    test('5. Published + Student：學生取得得到', () async {
      final fs = FakeFirebaseFirestore();
      await _seedPublished(fs, 'c1', visibility: Visibility.student);
      final repo = _repo(fs);
      final student = await repo.fetchStudentStudyContent();
      expect(student.map((e) => e.id), contains('c1'));
      expect((await repo.fetchStudentStudyContentById('c1'))!.isStudentVisible,
          isTrue);
    });

    test('6. Published 編輯＝建立新草稿；Published live 不變', () async {
      final fs = FakeFirebaseFirestore();
      final repo = await _seedPublished(fs, 'c1',
          visibility: Visibility.internal);
      final pubBefore = await repo.adminGetContentPublished('c1');
      await repo.createContentDraftFromPublished('c1', _admin);
      final draft = await repo.adminGetContentWorkspace('c1');
      expect(draft!.status, ContentStatus.draft);
      // 新草稿沿用 Published 的 visibility（可在草稿改）。
      expect(draft.visibility, Visibility.internal);
      // Published live 版本未被更動。
      final pubAfter = await repo.adminGetContentPublished('c1');
      expect(pubAfter!.status, ContentStatus.published);
      expect(pubAfter.version, pubBefore!.version);
    });

    test('7. 改 visibility 須經新草稿→發佈；Published 不被直接改', () async {
      final fs = FakeFirebaseFirestore();
      final repo =
          await _seedPublished(fs, 'c1', visibility: Visibility.internal);
      // 建新草稿、把 visibility 改 student、重新發佈 → 版本 +1、學生可見。
      await repo.createContentDraftFromPublished('c1', _admin);
      await repo.saveContentDraft('c1',
          type: StudyContentType.topicArticle,
          payload: {'title': '題目 c1', 'body': '內文', 'data': {}},
          editorEmail: _admin,
          visibility: Visibility.student);
      await repo.submitContentForReview('c1', _admin);
      await repo.publishContent('c1', _admin);
      final pub = await repo.adminGetContentPublished('c1');
      expect(pub!.visibility, Visibility.student);
      expect(pub.version, 2);
      expect(await repo.fetchStudentStudyContentById('c1'), isNotNull);
    });

    test('8. 版本紀錄可讀（子集合快照）', () async {
      final fs = FakeFirebaseFirestore();
      final repo =
          await _seedPublished(fs, 'c1', visibility: Visibility.internal);
      await repo.createContentDraftFromPublished('c1', _admin);
      await repo.publishContent('c1', _admin); // v2，v1 快照入 versions 子集合
      final versions = await repo.adminContentVersions('c1');
      expect(versions, isNotEmpty);
      expect(versions.first['version'], 1);
    });
  });

  group('Topic workflow', () {
    test('9. 新 Topic 預設 Draft + Internal', () async {
      final fs = FakeFirebaseFirestore();
      final repo = _repo(fs);
      await repo.saveTopicDraft('t1',
          payload: {'title': '恩典', 'sort_order': 0}, editorEmail: _admin);
      final ws = await repo.adminGetTopicWorkspace('t1');
      expect(ws!.status, ContentStatus.draft);
      expect(ws.visibility, Visibility.internal);
    });

    test('10. Published/Internal vs Published/Student 正確', () async {
      final fs = FakeFirebaseFirestore();
      final repo = _repo(fs);
      for (final e in {
        'ti': Visibility.internal,
        'ts': Visibility.student
      }.entries) {
        await repo.saveTopicDraft(e.key,
            payload: {'title': e.key, 'sort_order': 0},
            editorEmail: _admin,
            visibility: e.value);
        await repo.submitTopicForReview(e.key, _admin);
        await repo.publishTopic(e.key, _admin);
      }
      final student = await repo.fetchStudentTopics();
      expect(student.map((t) => t.id), contains('ts'));
      expect(student.map((t) => t.id), isNot(contains('ti')));
    });

    test('11. Published Topic 編輯建立新草稿', () async {
      final fs = FakeFirebaseFirestore();
      final repo = _repo(fs);
      await repo.saveTopicDraft('t1',
          payload: {'title': 'x', 'sort_order': 0}, editorEmail: _admin);
      await repo.submitTopicForReview('t1', _admin);
      await repo.publishTopic('t1', _admin);
      await repo.createTopicDraftFromPublished('t1', _admin);
      final ws = await repo.adminGetTopicWorkspace('t1');
      expect(ws!.status, ContentStatus.draft);
    });
  });

  group('Q&A sources', () {
    test('12/17. answer.sources 儲存＋載回＋順序保留', () async {
      final fs = FakeFirebaseFirestore();
      // 先種一個問題 doc。
      await fs.collection('questions').doc('q1').set({
        'uid': 'u', 'title': '問題', 'body': 'b', 'status': 'pending',
        'published': false, 'created_at': 1,
      });
      final qa = QaService(fs);
      final q = await qa.getQuestion('q1');
      const sources = [
        AnswerSource(
            contentId: 'sc_a', version: 1, kind: 'study_content', evidence: 'A'),
        AnswerSource(
            contentId: 'sc_b', version: 2, kind: 'study_content', evidence: 'B'),
      ];
      await qa.saveAnswer(
          question: q!, content: '回答', scriptures: ['約3:16'], tags: [],
          sources: sources);
      final back = await qa.getQuestion('q1');
      final got = back!.answer!.sources;
      expect(got.map((s) => s.contentId).toList(), ['sc_a', 'sc_b']);
      expect(got[1].version, 2);
      expect(back.answer!.scriptures, ['約3:16']);
    });

    test('16. Draft/Archived study content 不是有效 source（發佈前驗證）', () async {
      final fs = FakeFirebaseFirestore();
      final repo = _repo(fs);
      // published + internal：可作 source。
      await _seedPublished(fs, 'pub_int', visibility: Visibility.internal);
      // draft：不可作 source。
      await repo.saveContentDraft('draft1',
          type: StudyContentType.topicArticle,
          payload: {'title': 'd', 'data': {}},
          editorEmail: _admin);
      expect(await repo.isPublishedNow('pub_int'), isTrue);
      expect(await repo.isPublishedNow('draft1'), isFalse);
      // 已發佈後又封存 → 失效。
      await repo.archiveContent('pub_int', _admin);
      expect(await repo.isPublishedNow('pub_int'), isFalse);
    });

    test('14/15. source picker 只列 published（含 internal）', () async {
      final fs = FakeFirebaseFirestore();
      final repo = _repo(fs);
      await _seedPublished(fs, 'pub_int', visibility: Visibility.internal);
      await _seedPublished(fs, 'pub_stu', visibility: Visibility.student);
      await repo.saveContentDraft('draft1',
          type: StudyContentType.topicArticle,
          payload: {'title': 'd', 'data': {}},
          editorEmail: _admin);
      final sources = await repo.adminListPublishedForSources();
      final ids = sources.map((e) => e.id).toSet();
      expect(ids, containsAll(['pub_int', 'pub_stu']));
      expect(ids.contains('draft1'), isFalse); // draft 不得成為 source
    });
  });

  group('Daily Verse workflow', () {
    const type = 'daily_verses';
    test('18. Draft → Review → Published（doc id＝日期）', () async {
      final fs = FakeFirebaseFirestore();
      final wf = ContentWorkflowService(fs);
      await wf.saveDraft(type, '2026-09-10',
          contentType: 'daily_verse',
          payload: {'date': '2026-09-10', 'book_id': 43, 'chapter': 3, 'verse': 16},
          editorEmail: _admin);
      await wf.submitForReview(type, '2026-09-10', _admin);
      await wf.approveAndPublish(type, '2026-09-10', publisherEmail: _admin);
      final doc = await fs.collection('daily_verses').doc('2026-09-10').get();
      expect(doc.data()!['status'], 'published');
      expect(doc.data()!['book_id'], 43);
    });

    test('19. 未來已發布不會提前顯示；今天才顯示（純預測）', () {
      expect(
          ContentService.dailyVerseVisibleToday(
              'published', '2026-09-10', '2026-09-01'),
          isFalse);
      expect(
          ContentService.dailyVerseVisibleToday(
              'published', '2026-09-10', '2026-09-10'),
          isTrue);
    });

    test('20/21. 同日期只有一筆對外版本；替代路徑保持 one-active', () async {
      final fs = FakeFirebaseFirestore();
      final wf = ContentWorkflowService(fs);
      // 首次發佈。
      await wf.saveDraft(type, '2026-09-10',
          contentType: 'daily_verse',
          payload: {'date': '2026-09-10', 'book_id': 43, 'chapter': 3, 'verse': 16},
          editorEmail: _admin);
      await wf.approveAndPublish(type, '2026-09-10', publisherEmail: _admin);
      // 替代：建新草稿→改內容→再發佈（版本 +1，仍是同一 doc）。
      await wf.createDraftFromPublished(type, '2026-09-10', editorEmail: _admin);
      await wf.saveDraft(type, '2026-09-10',
          contentType: 'daily_verse',
          payload: {'date': '2026-09-10', 'book_id': 43, 'chapter': 3, 'verse': 17},
          editorEmail: _admin);
      await wf.approveAndPublish(type, '2026-09-10', publisherEmail: _admin);
      // 該日期在 mirror 中只有一筆（one active per date 由 doc id 結構保證）。
      final all = await fs
          .collection('daily_verses')
          .where('date', isEqualTo: '2026-09-10')
          .get();
      expect(all.docs.length, 1);
      expect(all.docs.first.data()['verse'], 17); // 已被替代版取代
      expect(all.docs.first.data()['version'], 2);
    });

    test('22. 今天沒有 published → fail closed（不顯示）', () {
      expect(ContentService.dailyVerseVisibleToday(null, '2026-09-01', '2026-09-01'),
          isFalse);
      expect(
          ContentService.dailyVerseVisibleToday('draft', '2026-09-01', '2026-09-01'),
          isFalse);
    });
  });

  group('Legacy Knowledge 隔離', () {
    test('24. 動 knowledge/data 不會使 study_content 變 student-visible', () async {
      final fs = FakeFirebaseFirestore();
      final repo = _repo(fs);
      await _seedPublished(fs, 'c1', visibility: Visibility.internal);
      // 模擬 legacy publish（只寫 knowledge/data）。
      await fs.collection('knowledge').doc('data').set({
        'status': 'published', 'version': 9, 'parallels': [], 'people': []
      });
      // study_content 的 visibility 未受影響。
      final pub = await repo.adminGetContentPublished('c1');
      expect(pub!.visibility, Visibility.internal);
      expect(await repo.fetchStudentStudyContentById('c1'), isNull);
    });
  });
}
