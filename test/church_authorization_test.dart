import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/models/church.dart';
import 'package:bible_app/models/study_content.dart';
import 'package:bible_app/models/teacher.dart';
import 'package:bible_app/services/church_repository.dart';
import 'package:bible_app/services/content_workflow_service.dart';
import 'package:bible_app/services/study_content_repository.dart';

const _admin = 'admin@example.com';

StudyContentRepository _repo(FakeFirebaseFirestore fs) =>
    StudyContentRepository(fs, ContentWorkflowService(fs));

/// 直接種一個 published study_content（繞過 workflow，直接控 audience）。
Future<void> _seed(FakeFirebaseFirestore fs, String id,
    {required String status,
    String? audience,
    List<String> churches = const [],
    List<String> topics = const [],
    String contentType = 'topic_article',
    String teacherChapterId = ''}) async {
  await fs.collection('study_content').doc(id).set({
    'content_id': id,
    'content_type': contentType,
    'status': status,
    if (audience != null) 'audience': audience,
    'allowed_church_ids': churches,
    'title': id,
    'topic_ids': topics,
    if (teacherChapterId.isNotEmpty) 'teacher_chapter_id': teacherChapterId,
    'data': {},
    'version': 1,
  });
}

void main() {
  group('audienceAuthorized（純授權函式）', () {
    test('published public → 任何人可讀', () {
      expect(
          audienceAuthorized(
              status: ContentStatus.published,
              audience: Audience.public,
              allowedChurchIds: const [],
              activeChurchId: null),
          isTrue);
    });
    test('draft public → 否', () {
      expect(
          audienceAuthorized(
              status: ContentStatus.draft,
              audience: Audience.public,
              allowedChurchIds: const [],
              activeChurchId: null),
          isFalse);
    });
    test('published internal → 否', () {
      expect(
          audienceAuthorized(
              status: ContentStatus.published,
              audience: Audience.internal,
              allowedChurchIds: const [],
              activeChurchId: null),
          isFalse);
    });
    test('church A + active A → 可；+ 無 church → 否；+ active B → 否', () {
      base(String? c) => audienceAuthorized(
          status: ContentStatus.published,
          audience: Audience.church,
          allowedChurchIds: const ['A'],
          activeChurchId: c);
      expect(base('A'), isTrue);
      expect(base(null), isFalse);
      expect(base('B'), isFalse);
    });
    test('church + 空 allowedChurchIds → 否（fail-closed）', () {
      expect(
          audienceAuthorized(
              status: ContentStatus.published,
              audience: Audience.church,
              allowedChurchIds: const [],
              activeChurchId: 'A'),
          isFalse);
    });
    test('缺 audience（null）→ 否（fail-closed）', () {
      expect(
          audienceAuthorized(
              status: ContentStatus.published,
              audience: null,
              allowedChurchIds: const [],
              activeChurchId: 'A'),
          isFalse);
    });
  });

  group('Authorized Universe（repository）', () {
    late FakeFirebaseFirestore fs;
    late StudyContentRepository repo;
    setUp(() async {
      fs = FakeFirebaseFirestore();
      repo = _repo(fs);
      await _seed(fs, 'pub', status: 'published', audience: 'public', topics: ['t']);
      await _seed(fs, 'pub_draft', status: 'draft', audience: 'public');
      await _seed(fs, 'internal', status: 'published', audience: 'internal');
      await _seed(fs, 'chA', status: 'published', audience: 'church', churches: ['A'], topics: ['t']);
      await _seed(fs, 'chB', status: 'published', audience: 'church', churches: ['B'], topics: ['t']);
      await _seed(fs, 'noaud', status: 'published'); // 缺 audience
    });

    test('無 membership：只見 public', () async {
      final ids = (await repo.fetchAuthorizedStudyContent(StudentAuth.none)).map((e) => e.id);
      expect(ids, ['pub']);
    });
    test('active A：見 public + church A（不見 B/internal/draft/缺 audience）', () async {
      final ids = (await repo.fetchAuthorizedStudyContent(const StudentAuth('A')))
          .map((e) => e.id).toSet();
      expect(ids, {'pub', 'chA'});
    });
    test('byId 不可 bypass：church A doc + active B → null；+ active A → 命中', () async {
      expect(await repo.fetchAuthorizedStudyContentById('chA', const StudentAuth('B')), isNull);
      expect(await repo.fetchAuthorizedStudyContentById('chA', const StudentAuth('A')), isNotNull);
      expect(await repo.fetchAuthorizedStudyContentById('internal', const StudentAuth('A')), isNull);
      expect(await repo.fetchAuthorizedStudyContentById('noaud', const StudentAuth('A')), isNull);
    });
    test('byTopic 不洩漏 church B：active A 查 topic t → pub + chA only', () async {
      final ids = (await repo.fetchAuthorizedByTopic('t', const StudentAuth('A')))
          .map((e) => e.id).toSet();
      expect(ids, {'pub', 'chA'});
      expect(ids.contains('chB'), isFalse);
    });
    test('byType 不洩漏 church B', () async {
      final ids = (await repo.fetchAuthorizedByType(StudyContentType.topicArticle, const StudentAuth('A')))
          .map((e) => e.id).toSet();
      expect(ids.contains('chB'), isFalse);
      expect(ids.containsAll({'pub', 'chA'}), isTrue);
    });
  });

  group('Topic authorization（Option A）', () {
    test('published church A topic：active A 見、active B 不見', () async {
      final fs = FakeFirebaseFirestore();
      final repo = _repo(fs);
      await fs.collection('study_topics').doc('tp').set({
        'content_id': 'tp', 'status': 'published', 'audience': 'church',
        'allowed_church_ids': ['A'], 'title': '主題A', 'sort_order': 0,
      });
      expect((await repo.fetchAuthorizedTopics(const StudentAuth('A'))).map((t) => t.id), ['tp']);
      expect(await repo.fetchAuthorizedTopics(const StudentAuth('B')), isEmpty);
      expect(await repo.fetchAuthorizedTopics(StudentAuth.none), isEmpty);
    });
  });

  group('Teacher hierarchy authorization', () {
    test('church A book：active B 讀不到（無結構洩漏）', () async {
      final fs = FakeFirebaseFirestore();
      final tr = TeacherRepository(fs);
      await fs.collection('teacher_books').doc('b1').set({
        'title': '書', 'order': 0, 'status': 'published',
        'audience': 'church', 'allowed_church_ids': ['A'],
      });
      expect((await tr.fetchAuthorizedBooks(const StudentAuth('A'))).map((b) => b.id), ['b1']);
      expect(await tr.fetchAuthorizedBooks(const StudentAuth('B')), isEmpty);
      expect(await tr.fetchAuthorizedBooks(StudentAuth.none), isEmpty);
    });

    test('teaching(chapter) authorized：study_content 掛 chapter，audience 授權過濾', () async {
      final fs = FakeFirebaseFirestore();
      final repo = _repo(fs);
      await _seed(fs, 'teach_pub', status: 'published', audience: 'public', teacherChapterId: 'c1');
      await _seed(fs, 'teach_chB', status: 'published', audience: 'church', churches: ['B'], teacherChapterId: 'c1');
      final ids = (await repo.fetchAuthorizedTeachings('c1', const StudentAuth('A'))).map((e) => e.id).toSet();
      expect(ids, {'teach_pub'}); // 不含 church B teaching
    });

    test('TeacherBook/Chapter.authorizedFor 契約', () {
      const book = TeacherBook(id: 'b', status: ContentStatus.published, audience: Audience.church, allowedChurchIds: ['A']);
      expect(book.authorizedFor('A'), isTrue);
      expect(book.authorizedFor('B'), isFalse);
      const ch = TeacherChapter(id: 'c', bookId: 'b', status: ContentStatus.published, audience: Audience.internal);
      expect(ch.authorizedFor('A'), isFalse);
    });
  });

  group('Membership contract', () {
    test('request → pending；activeChurchId 只有 active 才有值', () async {
      final fs = FakeFirebaseFirestore();
      final repo = ChurchRepository(fs);
      await fs.collection('churches').doc('A').set({'name': 'A教會', 'active': true});
      await repo.requestMembership('u1', 'A');
      var m = await repo.fetchMembership('u1');
      expect(m!.status, MembershipStatus.pending);
      expect(m.activeChurchId, isNull); // pending 不授權
      await repo.approveMembership('u1', _admin);
      m = await repo.fetchMembership('u1');
      expect(m!.status, MembershipStatus.active);
      expect(m.activeChurchId, 'A');
      await repo.revokeMembership('u1', _admin);
      m = await repo.fetchMembership('u1');
      expect(m!.status, MembershipStatus.revoked);
      expect(m.activeChurchId, isNull); // revoke 後失去授權
    });

    test('doc-id=uid → 一人一 membership（至多一個 active）', () async {
      final fs = FakeFirebaseFirestore();
      final repo = ChurchRepository(fs);
      await fs.collection('churches').doc('A').set({'active': true});
      await fs.collection('churches').doc('B').set({'active': true});
      await repo.requestMembership('u1', 'A');
      await repo.requestMembership('u1', 'B'); // 覆蓋同一 doc（換教會需重新申請）
      final snap = await fs.collection('memberships').where('uid', isEqualTo: 'u1').get();
      expect(snap.docs.length, 1);
      expect(snap.docs.first.data()['church_id'], 'B');
    });

    test('active churches 只列 active', () async {
      final fs = FakeFirebaseFirestore();
      final repo = ChurchRepository(fs);
      await fs.collection('churches').doc('A').set({'name': 'A', 'active': true});
      await fs.collection('churches').doc('X').set({'name': 'X', 'active': false});
      expect((await repo.fetchActiveChurches()).map((c) => c.id), ['A']);
    });
  });

  group('Saved relationship 不授予 access', () {
    test('save church item + 無 membership → live resolve 仍 null', () async {
      final fs = FakeFirebaseFirestore();
      final repo = _repo(fs);
      final saved = SavedStudyContentRepository(fs);
      await _seed(fs, 'chA', status: 'published', audience: 'church', churches: ['A']);
      await saved.save('u1', 'chA');
      expect(await saved.savedIds('u1'), ['chA']); // relationship 保留
      // 但 open 走授權 repo：無 membership → null（不回 payload）。
      expect(await repo.fetchAuthorizedStudyContentById('chA', StudentAuth.none), isNull);
    });
  });
}
