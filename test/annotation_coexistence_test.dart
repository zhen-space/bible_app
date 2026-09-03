import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/models/church.dart';
import 'package:bible_app/models/managed_content.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/services/annotation_admin_repository.dart';
import 'package:bible_app/services/content_service.dart';
import 'package:bible_app/services/content_workflow_service.dart';

/// Annotation same-verse public + church coexistence（Church/Teacher R1 最後 blocker）。
void main() {
  // ---- Reader 端：同節多筆 grouping（public 先、church 後、穩定排序）----
  group('chapterAnnotationProvider grouping', () {
    ProviderContainer withCloud(Map<String, Map<String, dynamic>> cloud) =>
        ProviderContainer(overrides: [
          cloudAnnotationsProvider.overrideWith((ref) async => cloud),
        ]);

    test('CASE B/D/E：同節 public(含 legacy id)＋church 多筆，public 先 church 後、id 穩定',
        () async {
      final c = withCloud({
        // legacy id（無 verse_key，靠 doc-id 解析）
        'verse_1_1_1': {
          'status': 'published',
          'audience': 'public',
          'commentary': 'pub-legacy'
        },
        'ann_1_1_1_public_a': {
          'status': 'published',
          'audience': 'public',
          'verse_key': '1_1_1',
          'commentary': 'pub-2'
        },
        'ann_1_1_1_chA_y': {
          'status': 'published',
          'audience': 'church',
          'allowed_church_ids': ['A'],
          'verse_key': '1_1_1',
          'commentary': 'church-2'
        },
        'ann_1_1_1_chA_x': {
          'status': 'published',
          'audience': 'church',
          'allowed_church_ids': ['A'],
          'verse_key': '1_1_1',
          'commentary': 'church-1'
        },
        // 別章，不該入本章
        'ann_1_2_1_public_z': {
          'status': 'published',
          'audience': 'public',
          'verse_key': '1_2_1',
          'commentary': 'other-chapter'
        },
      });
      final res = await c.read(
          chapterAnnotationProvider((bookId: 1, chapter: 1)).future);
      final list = res.verses[1]!;
      expect(list.length, 4);
      // public 先（2 筆），church 後（2 筆）
      expect(list.map((v) => v.isChurch).toList(),
          [false, false, true, true]);
      // 同 audience 內以 annotationId 穩定升冪
      expect(list[0].annotationId, 'ann_1_1_1_public_a');
      expect(list[1].annotationId, 'verse_1_1_1');
      expect(list[2].annotationId, 'ann_1_1_1_chA_x');
      expect(list[3].annotationId, 'ann_1_1_1_chA_y');
      // 別章不混入
      expect(res.verses.containsKey(1), isTrue);
      expect(res.verses[1]!.every((v) => v.verse == 1), isTrue);
      c.dispose();
    });

    test('CASE A：只有 public → 單一 public 區塊', () async {
      final c = withCloud({
        'verse_1_1_1': {
          'status': 'published',
          'audience': 'public',
          'commentary': 'p'
        },
      });
      final res = await c.read(
          chapterAnnotationProvider((bookId: 1, chapter: 1)).future);
      expect(res.verses[1]!.length, 1);
      expect(res.verses[1]!.single.isChurch, isFalse);
      c.dispose();
    });

    test('CASE C：只有 church（已授權才會在 cloud）→ 單一 church 區塊', () async {
      final c = withCloud({
        'ann_1_1_1_chA_x': {
          'status': 'published',
          'audience': 'church',
          'allowed_church_ids': ['A'],
          'verse_key': '1_1_1',
          'commentary': 'ch'
        },
      });
      final res = await c.read(
          chapterAnnotationProvider((bookId: 1, chapter: 1)).future);
      expect(res.verses[1]!.single.isChurch, isTrue);
      c.dispose();
    });
  });

  // ---- 授權 universe：同 verse_key 的 public + church 共存，依 active church 過濾 ----
  group('fetchAuthorizedAnnotations coexistence', () {
    Future<ContentService> seed() async {
      final fs = FakeFirebaseFirestore();
      final cs = ContentService(fs);
      final col = fs.collection('annotations');
      await col.doc('verse_1_1_1').set(
          {'status': 'published', 'audience': 'public', 'verse_key': '1_1_1'});
      await col.doc('ann_1_1_1_chA').set({
        'status': 'published',
        'audience': 'church',
        'allowed_church_ids': ['A'],
        'verse_key': '1_1_1'
      });
      await col.doc('ann_1_1_1_chB').set({
        'status': 'published',
        'audience': 'church',
        'allowed_church_ids': ['B'],
        'verse_key': '1_1_1'
      });
      await col.doc('ann_1_1_1_intn').set(
          {'status': 'published', 'audience': 'internal', 'verse_key': '1_1_1'});
      return cs;
    }

    test('active A → public + church A（同節共存），不得 church B / internal', () async {
      final cs = await seed();
      final a = await cs.fetchAuthorizedAnnotations(const StudentAuth('A'));
      expect(a.keys.toSet(), {'verse_1_1_1', 'ann_1_1_1_chA'});
      expect(a.containsKey('ann_1_1_1_chB'), isFalse);
      expect(a.containsKey('ann_1_1_1_intn'), isFalse);
    });

    test('no membership → 只 public（同節 church 一律不回）', () async {
      final cs = await seed();
      final none = await cs.fetchAuthorizedAnnotations(StudentAuth.none);
      expect(none.keys.toSet(), {'verse_1_1_1'});
    });

    test('active B → public + church B（不得 church A）', () async {
      final cs = await seed();
      final b = await cs.fetchAuthorizedAnnotations(const StudentAuth('B'));
      expect(b.keys.toSet(), {'verse_1_1_1', 'ann_1_1_1_chB'});
      expect(b.containsKey('ann_1_1_1_chA'), isFalse);
    });
  });

  // ---- Admin：同節 public + church 各自獨立、互不覆寫；church 發佈對象驗證 ----
  group('AnnotationAdminRepository', () {
    AnnotationAdminRepository repo(FakeFirebaseFirestore fs) =>
        AnnotationAdminRepository(fs, ContentWorkflowService(fs));

    test('同節建立 public 與 church 兩筆 → 各自獨立 doc，listForVerse 回兩筆', () async {
      final fs = FakeFirebaseFirestore();
      final r = repo(fs);
      final pubId = 'ann_1_1_1_public_1';
      final chId = 'ann_1_1_1_chA_1';
      await r.saveDraft(pubId,
          book: 1,
          chapter: 1,
          verse: 1,
          payload: {'commentary': 'PUB'},
          audience: Audience.public,
          editorEmail: 'a@e.com');
      await r.saveDraft(chId,
          book: 1,
          chapter: 1,
          verse: 1,
          payload: {'commentary': 'CHURCH'},
          audience: Audience.church,
          allowedChurchIds: ['A'],
          editorEmail: 'a@e.com');
      final rows = await r.listForVerse(1, 1, 1);
      expect(rows.map((e) => e.id).toSet(), {pubId, chId});
      final pub = rows.firstWhere((e) => e.id == pubId);
      final ch = rows.firstWhere((e) => e.id == chId);
      expect(pub.audienceName, 'public');
      expect(ch.audienceName, 'church');
      expect(ch.allowedChurchIds, ['A']);
    });

    test('編輯 public 不覆寫 church（反之亦然）', () async {
      final fs = FakeFirebaseFirestore();
      final r = repo(fs);
      await r.saveDraft('pub1',
          book: 1,
          chapter: 1,
          verse: 1,
          payload: {'commentary': 'PUB-v1'},
          audience: Audience.public,
          editorEmail: 'a@e.com');
      await r.saveDraft('chA1',
          book: 1,
          chapter: 1,
          verse: 1,
          payload: {'commentary': 'CHURCH-v1'},
          audience: Audience.church,
          allowedChurchIds: ['A'],
          editorEmail: 'a@e.com');
      // 編輯 public
      await r.saveDraft('pub1',
          book: 1,
          chapter: 1,
          verse: 1,
          payload: {'commentary': 'PUB-v2'},
          audience: Audience.public,
          editorEmail: 'a@e.com');
      final ch = await r.getWorkspace('chA1');
      expect(ch!.payload['commentary'], 'CHURCH-v1'); // church 未被動到
      final pub = await r.getWorkspace('pub1');
      expect(pub!.payload['commentary'], 'PUB-v2');
    });

    test('church 發佈對象驗證：空 allowedChurchIds / inactive church → 送審 throw', () async {
      final fs = FakeFirebaseFirestore();
      final r = repo(fs);
      // 空 church
      await r.saveDraft('c1',
          book: 1,
          chapter: 1,
          verse: 1,
          payload: {'commentary': 'x'},
          audience: Audience.church,
          allowedChurchIds: const [],
          editorEmail: 'a@e.com');
      expect(() => r.submitForReview('c1', 'a@e.com'),
          throwsA(isA<StateError>()));
      // inactive church
      await fs.collection('churches').doc('A').set({'name': 'A', 'active': false});
      await r.saveDraft('c2',
          book: 1,
          chapter: 1,
          verse: 1,
          payload: {'commentary': 'x'},
          audience: Audience.church,
          allowedChurchIds: ['A'],
          editorEmail: 'a@e.com');
      expect(() => r.submitForReview('c2', 'a@e.com'),
          throwsA(isA<StateError>()));
    });

    test('draft→送審→發佈（church active）→ published mirror 出現，可被授權讀', () async {
      final fs = FakeFirebaseFirestore();
      final r = repo(fs);
      await fs.collection('churches').doc('A').set({'name': 'A', 'active': true});
      await r.saveDraft('chA_pub',
          book: 1,
          chapter: 1,
          verse: 1,
          payload: {'commentary': 'CH'},
          audience: Audience.church,
          allowedChurchIds: ['A'],
          editorEmail: 'a@e.com');
      await r.submitForReview('chA_pub', 'a@e.com');
      await r.publish('chA_pub', 'a@e.com');
      // published mirror 可被 active A 授權讀到（同 fetchAuthorizedAnnotations 路徑）。
      final cs = ContentService(fs);
      final a = await cs.fetchAuthorizedAnnotations(const StudentAuth('A'));
      expect(a.containsKey('chA_pub'), isTrue);
      final none = await cs.fetchAuthorizedAnnotations(StudentAuth.none);
      expect(none.containsKey('chA_pub'), isFalse); // 無 membership 讀不到
    });
  });
}
