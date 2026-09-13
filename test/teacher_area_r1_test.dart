import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/models/church.dart';
import 'package:bible_app/models/study_content.dart';
import 'package:bible_app/services/content_workflow_service.dart';
import 'package:bible_app/services/study_content_repository.dart';

StudyContentRepository _repo(FakeFirebaseFirestore fs) =>
    StudyContentRepository(fs, ContentWorkflowService(fs));

/// 種一個 study_content（published mirror），可帶 teacher book/chapter + 兩類經文。
Future<void> _seed(
  FakeFirebaseFirestore fs,
  String id, {
  required String status,
  String? audience,
  List<String> churches = const [],
  String teacherBookId = '',
  String teacherChapterId = '',
  String title = '',
  String body = '',
  List<String> teacherScriptureRefs = const [],
  String sourceLocation = '',
}) async {
  await fs.collection('study_content').doc(id).set({
    'content_id': id,
    'content_type': 'topic_article',
    'status': status,
    if (audience != null) 'audience': audience,
    'allowed_church_ids': churches,
    'title': title.isEmpty ? id : title,
    'body': body,
    'topic_ids': const [],
    if (teacherBookId.isNotEmpty) 'teacher_book_id': teacherBookId,
    if (teacherChapterId.isNotEmpty) 'teacher_chapter_id': teacherChapterId,
    if (teacherScriptureRefs.isNotEmpty)
      'teacher_scripture_refs': teacherScriptureRefs,
    if (sourceLocation.isNotEmpty) 'source_location': sourceLocation,
    'data': const {},
    'version': 1,
  });
}

void main() {
  group('Teacher teaching 兩類經文 + provenance（additive、backward-compatible）', () {
    test('teacherScriptureRefs / sourceLocation 與既有 scriptureRefs 各自獨立、round-trip', () {
      final it = StudyContentItem(
        id: 't1',
        status: ContentStatus.published,
        visibility: Visibility.student,
        contentType: StudyContentType.topicArticle,
        scriptureRefs: const ['約3:16'], // 整理者相關經文
        teacherScriptureRefs: const ['羅5:8', '弗2:8'], // 老師原文引用
        sourceLocation: '第 42 頁',
        teacherBookId: 'bookA',
        teacherChapterId: 'chA',
      );
      final back = StudyContentItem.fromManaged(it.toManaged());
      expect(back.scriptureRefs, ['約3:16']);
      expect(back.teacherScriptureRefs, ['羅5:8', '弗2:8']);
      expect(back.sourceLocation, '第 42 頁');
      // 兩類彼此不污染。
      expect(back.scriptureRefs, isNot(contains('羅5:8')));
    });

    test('無老師欄位時 payload 不含這些 key（維持既有 doc 形狀）', () {
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
      // 既有欄位不受影響。
      expect(p['scripture_refs'], ['創1:1']);
      // 舊 doc（無新 key）解析後為空，不報錯。
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

  group('授權 Teacher teachings（per-chapter，authorization-first）', () {
    late FakeFirebaseFirestore fs;
    setUp(() async {
      fs = FakeFirebaseFirestore();
      await _seed(fs, 'pub', status: 'published', audience: 'public',
          teacherBookId: 'bookA', teacherChapterId: 'chA', body: '恩典');
      await _seed(fs, 'chA_church', status: 'published', audience: 'church',
          churches: ['A'], teacherBookId: 'bookA', teacherChapterId: 'chA');
      await _seed(fs, 'chB_church', status: 'published', audience: 'church',
          churches: ['B'], teacherBookId: 'bookA', teacherChapterId: 'chA');
      await _seed(fs, 'internal', status: 'published', audience: 'internal',
          teacherBookId: 'bookA', teacherChapterId: 'chA');
    });

    // shared backend（未隨 Student Teacher Area UI 移除）：per-chapter 授權取用仍正確。
    test('fetchAuthorizedTeachings(chA) 對 Church B 使用者不含 Church A 專屬', () async {
      final b = await _repo(fs).fetchAuthorizedTeachings('chA', const StudentAuth('B'));
      final ids = b.map((i) => i.id).toSet();
      expect(ids, contains('pub'));
      expect(ids, contains('chB_church'));
      expect(ids, isNot(contains('chA_church')));
      expect(ids, isNot(contains('internal')));
    });

    test('無教會：per-chapter 只回 public teaching', () async {
      final none =
          await _repo(fs).fetchAuthorizedTeachings('chA', const StudentAuth(null));
      expect(none.map((i) => i.id).toSet(), {'pub'});
    });
  });

  group('Admin：某章教導清單（不論狀態/對象，僅該章）', () {
    test('adminListTeachings(chA) 只回該章 teaching（含 draft/internal），排除他章與非teacher',
        () async {
      final fs = FakeFirebaseFirestore();
      await _seed(fs, 'a1', status: 'published', audience: 'public',
          teacherBookId: 'bookA', teacherChapterId: 'chA');
      await _seed(fs, 'a2', status: 'draft', audience: 'internal',
          teacherBookId: 'bookA', teacherChapterId: 'chA');
      await _seed(fs, 'other', status: 'published', audience: 'public',
          teacherBookId: 'bookA', teacherChapterId: 'chB');
      await _seed(fs, 'nonteach', status: 'published', audience: 'public');
      final rows = await _repo(fs).adminListTeachings('chA');
      expect(rows.map((r) => r.editorial.id).toSet(), {'a1', 'a2'});
    });
  });
}
