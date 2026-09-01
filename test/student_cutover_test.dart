import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/models/study_content.dart';
import 'package:bible_app/services/content_workflow_service.dart';
import 'package:bible_app/services/qa_service.dart';
import 'package:bible_app/services/study_content_repository.dart';

const _admin = 'admin@example.com';

StudyContentRepository _repo(FakeFirebaseFirestore fs) =>
    StudyContentRepository(fs, ContentWorkflowService(fs));

Future<void> _publish(StudyContentRepository repo, String id, Visibility v,
    {List<String> topics = const []}) async {
  await repo.saveContentDraft(id,
      type: StudyContentType.topicArticle,
      payload: {'title': id, 'body': 'b', 'topic_ids': topics, 'data': {}},
      editorEmail: _admin,
      visibility: v);
  await repo.submitContentForReview(id, _admin);
  await repo.publishContent(id, _admin);
}

void main() {
  group('Student Study Content cutover（無 knowledge/data fallback）', () {
    test('空 study_content 即使 knowledge/data 已發布也回空（不 fallback）', () async {
      final fs = FakeFirebaseFirestore();
      // legacy aggregate 存在且 published。
      await fs.collection('knowledge').doc('data').set({
        'status': 'published',
        'version': 1,
        'parallels': [
          {'title': 'x', 'refs': ['約1:1']}
        ],
      });
      final repo = _repo(fs);
      expect(await repo.fetchStudentStudyContent(), isEmpty);
      expect(await repo.fetchStudentTopics(), isEmpty);
    });

    test('只回 published+student；internal 不出現', () async {
      final fs = FakeFirebaseFirestore();
      final repo = _repo(fs);
      await _publish(repo, 'stu', Visibility.student);
      await _publish(repo, 'int', Visibility.internal);
      final ids = (await repo.fetchStudentStudyContent()).map((e) => e.id);
      expect(ids, contains('stu'));
      expect(ids, isNot(contains('int')));
    });

    test('主題 → 內容只回 published+student（即使 internal 帶同 topicId）', () async {
      final fs = FakeFirebaseFirestore();
      final repo = _repo(fs);
      await _publish(repo, 'stu', Visibility.student, topics: ['t1']);
      await _publish(repo, 'int', Visibility.internal, topics: ['t1']);
      final byTopic = await repo.fetchStudentStudyContentByTopic('t1');
      expect(byTopic.map((e) => e.id), ['stu']);
    });
  });

  group('AnswerSource（Q&A 回答依據快照）', () {
    test('access/ref round-trip', () {
      const s = AnswerSource(
          contentId: 'c',
          version: 2,
          kind: 'study_content',
          evidence: '標題',
          access: 'internal',
          ref: '');
      final back = AnswerSource.fromMap(s.toMap());
      expect(back.access, 'internal');
      expect(back.kind, 'study_content');
      expect(back.evidence, '標題');
    });

    test('isStudentOpenable：scripture 與 study+student 可開；study+internal 不可', () {
      expect(
          const AnswerSource(contentId: '約3:16', version: 0, kind: 'scripture', ref: '約3:16')
              .isStudentOpenable,
          isTrue);
      expect(
          const AnswerSource(contentId: 'c', version: 1, kind: 'study_content', access: 'student')
              .isStudentOpenable,
          isTrue);
      expect(
          const AnswerSource(contentId: 'c', version: 1, kind: 'study_content', access: 'internal')
              .isStudentOpenable,
          isFalse);
    });
  });

  group('Q&A 結構化 sources 持久化', () {
    Future<QaService> makeQa(FakeFirebaseFirestore fs) async {
      await fs.collection('questions').doc('q1').set({
        'uid': 'u', 'title': 't', 'body': 'b', 'status': 'pending',
        'published': false, 'created_at': 1,
      });
      return QaService(fs);
    }

    test('scripture + study sources 儲存＋載回＋順序＋access', () async {
      final fs = FakeFirebaseFirestore();
      final qa = await makeQa(fs);
      final q = await qa.getQuestion('q1');
      const sources = [
        AnswerSource(contentId: '約3:16-18', version: 0, kind: 'scripture', ref: '約3:16-18', evidence: '約3:16-18'),
        AnswerSource(contentId: 'sc_stu', version: 1, kind: 'study_content', evidence: 'A', access: 'student'),
        AnswerSource(contentId: 'sc_int', version: 1, kind: 'study_content', evidence: 'B', access: 'internal'),
      ];
      await qa.saveAnswer(
          question: q!, content: '答', scriptures: ['約3:16-18'], tags: [], sources: sources);
      final back = (await qa.getQuestion('q1'))!.answer!.sources;
      expect(back.map((s) => s.contentId).toList(),
          ['約3:16-18', 'sc_stu', 'sc_int']);
      expect(back[0].kind, 'scripture');
      expect(back[0].ref, '約3:16-18');
      expect(back[1].access, 'student');
      expect(back[2].access, 'internal');
    });

    test('legacy answer.scriptures 相容（只有舊欄位仍可讀）', () async {
      final fs = FakeFirebaseFirestore();
      // 直接種一個只有 legacy scriptures 的已回答問題。
      await fs.collection('questions').doc('q2').set({
        'uid': 'u', 'title': 't', 'body': 'b', 'status': 'approved',
        'published': true, 'created_at': 1,
        'answer': {
          'content': '答', 'scriptures': ['羅5:8'], 'tags': [], 'sources': [],
          'answered_at': 1, 'updated_at': 1,
        },
      });
      final qa = QaService(fs);
      final a = (await qa.getQuestion('q2'))!.answer!;
      expect(a.scriptures, ['羅5:8']);
      expect(a.sources, isEmpty);
    });
  });
}
