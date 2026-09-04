import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/models/church.dart';
import 'package:bible_app/models/managed_content.dart';
import 'package:bible_app/services/qa_service.dart';

AnswerSource _study(String id, String access,
        {int version = 1, List<String> churches = const []}) =>
    AnswerSource(
        contentId: id,
        version: version,
        kind: 'study_content',
        access: access,
        allowedChurchIds: churches);

AnswerSource _scripture(String ref) =>
    AnswerSource(contentId: ref, version: 0, kind: 'scripture', ref: ref);

Future<void> _seedQ(FakeFirebaseFirestore fs, String id,
    {required bool published,
    String? audience,
    List<String> churches = const []}) async {
  await fs.collection('questions').doc(id).set({
    'uid': 'author',
    'title': 't',
    'body': 'b',
    'category': '神學',
    'status': 'approved',
    'published': published,
    if (audience != null) 'audience': audience,
    'allowed_church_ids': churches,
    'answer': {'content': 'ans', 'scriptures': [], 'tags': [], 'answered_at': 1, 'updated_at': 1},
    'created_at': 1,
    'updated_at': 1,
  });
}

void main() {
  group('DerivedAnswerAudience.derive（B9/B10 純函式）', () {
    test('1 scripture-only → Public', () {
      final d = DerivedAnswerAudience.derive([_scripture('約3:16')]);
      expect(d.publishable, isTrue);
      expect(d.audience, Audience.public);
    });
    test('2 public study source → Public', () {
      final d = DerivedAnswerAudience.derive([_study('x', 'public')]);
      expect(d.audience, Audience.public);
      expect(d.publishable, isTrue);
    });
    test('3 church A source → Church A only', () {
      final d = DerivedAnswerAudience.derive([_study('x', 'church', churches: ['A'])]);
      expect(d.audience, Audience.church);
      expect(d.allowedChurchIds, ['A']);
      expect(d.publishable, isTrue);
    });
    test('7 church A+B ∩ church B+C → Church B', () {
      final d = DerivedAnswerAudience.derive([
        _study('x', 'church', churches: ['A', 'B']),
        _study('y', 'church', churches: ['B', 'C']),
      ]);
      expect(d.audience, Audience.church);
      expect(d.allowedChurchIds, ['B']);
      expect(d.publishable, isTrue);
    });
    test('8 church A ∩ church B → empty → 不可發布', () {
      final d = DerivedAnswerAudience.derive([
        _study('x', 'church', churches: ['A']),
        _study('y', 'church', churches: ['B']),
      ]);
      expect(d.publishable, isFalse);
      expect(d.allowedChurchIds, isEmpty);
    });
    test('9 internal source → 不可發布', () {
      final d = DerivedAnswerAudience.derive([_study('x', 'internal')]);
      expect(d.publishable, isFalse);
    });
    test('church + public 混合 → 仍 Church（縮小）', () {
      final d = DerivedAnswerAudience.derive([
        _study('p', 'public'),
        _study('c', 'church', churches: ['A']),
        _scripture('約3:16'),
      ]);
      expect(d.audience, Audience.church);
      expect(d.allowedChurchIds, ['A']);
    });
  });

  group('Question.studentReadable（B18 audience gate）', () {
    Question q(String? audience, List<String> churches) => Question.fromDoc('id', {
          'status': 'approved',
          'published': true,
          if (audience != null) 'audience': audience,
          'allowed_church_ids': churches,
          'answer': {'content': 'a', 'answered_at': 1, 'updated_at': 1},
        });
    test('public → 任何人可讀', () {
      expect(q('public', const []).studentReadable(null), isTrue);
      expect(q('public', const []).studentReadable('A'), isTrue);
    });
    test('church → 僅 activeChurch ∈ allowed', () {
      expect(q('church', ['A']).studentReadable('A'), isTrue);
      expect(q('church', ['A']).studentReadable('B'), isFalse);
      expect(q('church', ['A']).studentReadable(null), isFalse);
    });
    test('missing/internal audience → fail-closed', () {
      expect(q(null, const []).studentReadable('A'), isFalse);
      expect(q('internal', const []).studentReadable('A'), isFalse);
    });
    test('未發布 → 不可讀', () {
      final unpub = Question.fromDoc('id', {
        'published': false,
        'audience': 'public',
        'answer': {'content': 'a', 'answered_at': 1, 'updated_at': 1},
      });
      expect(unpub.studentReadable(null), isFalse);
    });
  });

  group('publishedQuestions 授權過濾（B20 defense-in-depth）', () {
    test('4/5/6 public 全可；church A 僅 A；church B 排除 public user 與 A', () async {
      final fs = FakeFirebaseFirestore();
      final svc = QaService(fs);
      await _seedQ(fs, 'pub', published: true, audience: 'public');
      await _seedQ(fs, 'chA', published: true, audience: 'church', churches: ['A']);
      // 未發布 & 缺 audience 對照
      await _seedQ(fs, 'chNoAud', published: true); // 缺 audience → fail-closed

      final asNone = await svc.publishedQuestions(auth: StudentAuth.none);
      expect(asNone.map((q) => q.id).toSet(), {'pub'});

      final asA = await svc.publishedQuestions(auth: const StudentAuth('A'));
      expect(asA.map((q) => q.id).toSet(), {'pub', 'chA'});

      final asB = await svc.publishedQuestions(auth: const StudentAuth('B'));
      expect(asB.map((q) => q.id).toSet(), {'pub'}); // 看不到 chA
    });
  });

  group('publishAnswer 寫入推導 audience', () {
    test('church answer 寫入 audience=church + allowed_church_ids', () async {
      final fs = FakeFirebaseFirestore();
      final svc = QaService(fs);
      await _seedQ(fs, 'q1', published: false);
      await svc.publishAnswer('q1',
          audience: Audience.church, allowedChurchIds: ['A', 'B']);
      final doc = await fs.collection('questions').doc('q1').get();
      expect(doc.data()!['published'], true);
      expect(doc.data()!['audience'], 'church');
      expect(doc.data()!['allowed_church_ids'], ['A', 'B']);
    });
    test('public answer 不寫 church ids', () async {
      final fs = FakeFirebaseFirestore();
      final svc = QaService(fs);
      await _seedQ(fs, 'q2', published: false);
      await svc.publishAnswer('q2',
          audience: Audience.public, allowedChurchIds: const []);
      final doc = await fs.collection('questions').doc('q2').get();
      expect(doc.data()!['audience'], 'public');
      expect(doc.data()!['allowed_church_ids'], isEmpty);
    });
    test('setPublished(true) 被封鎖（必須走 publishAnswer）', () async {
      final fs = FakeFirebaseFirestore();
      final svc = QaService(fs);
      await _seedQ(fs, 'q3', published: false);
      expect(() => svc.setPublished('q3', true), throwsA(isA<StateError>()));
      // 取消發布仍可
      await svc.setPublished('q3', false);
      expect((await fs.collection('questions').doc('q3').get()).data()!['published'], false);
    });
  });

  group('QaService.sourceProblem 發布前重新驗證（B13/B27，cases 10-14）', () {
    String? p({required bool livePublished, int? liveVersion, Audience? liveAudience, int cited = 3}) =>
        DerivedAnswerAudience.sourceProblem(
            label: 'X',
            citedVersion: cited,
            livePublished: livePublished,
            liveVersion: liveVersion,
            liveAudience: liveAudience);
    test('10-13 非 Published（draft/review/rejected/archived/刪除）→ 阻止', () {
      expect(p(livePublished: false), isNotNull);
    });
    test('14 版本漂移（引用 v3、現 v4）→ 阻止', () {
      expect(p(livePublished: true, liveVersion: 4, liveAudience: Audience.public), isNotNull);
    });
    test('Internal → 阻止', () {
      expect(p(livePublished: true, liveVersion: 3, liveAudience: Audience.internal), isNotNull);
      expect(p(livePublished: true, liveVersion: 3, liveAudience: null), isNotNull);
    });
    test('exact version + public/church → 通過（null）', () {
      expect(p(livePublished: true, liveVersion: 3, liveAudience: Audience.public), isNull);
      expect(p(livePublished: true, liveVersion: 3, liveAudience: Audience.church), isNull);
    });
  });

  group('AnswerSource 序列化保留 allowedChurchIds（B12）', () {
    test('round-trip', () {
      final s = _study('x', 'church', version: 3, churches: ['A', 'B']);
      final back = AnswerSource.fromMap(s.toMap());
      expect(back.contentId, 'x');
      expect(back.version, 3);
      expect(back.access, 'church');
      expect(back.allowedChurchIds, ['A', 'B']);
    });
  });
}
