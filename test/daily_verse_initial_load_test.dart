import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/models/daily_verse_batch.dart';
import 'package:bible_app/services/content_service.dart';
import 'package:bible_app/services/content_workflow_service.dart';
import 'package:bible_app/services/daily_verse_batch_service.dart';

/// 初始載入 blocker 的 regression：候選池／清單讀取「永不回傳」必須逾時轉為明確錯誤
/// （可重試、不永久 spinner），且 malformed／失敗 payload 不得讓解析崩潰。
void main() {
  group('防禦性解析：malformed payload 不丟例外', () {
    test('Pool 欄位型別全錯 → 安全預設', () {
      final p = DailyVerseCandidatePool.fromJson({
        'version': 'x',
        'approved': 'y',
        'candidates': 'not-a-list',
        'catalog_version': 'z',
        'algo_version': [],
        'generated_at': 'nope',
        'source': 123,
      });
      expect(p.version, 0);
      expect(p.approved, isFalse);
      expect(p.candidates, isEmpty);
      expect(p.catalogVersion, 0);
      expect(p.algoVersion, 0);
      expect(p.generatedAt, isNull);
      expect(p.source, 'manual');
    });

    test('candidates 內含損壞項 → 保留合法項但整池撤銷核准', () {
      final p = DailyVerseCandidatePool.fromJson({
        'approved': true,
        'candidates': [
          1,
          'bad',
          {'ref': '約3:16', 'date': '2026-09-22'},
          {'ref': 123},
        ],
      });
      expect(p.approved, isFalse);
      expect(p.isSchedulable, isFalse);
      expect(p.candidates, hasLength(1));
      expect(p.candidates.single.ref, '約3:16');
      expect(p.candidates.single.date, '2026-09-22');
    });

    test('合法候選缺少選填欄位 → 可維持核准', () {
      final p = DailyVerseCandidatePool.fromJson({
        'approved': true,
        'candidates': [
          {'ref': '約3:16'},
        ],
      });
      expect(p.approved, isTrue);
      expect(p.isSchedulable, isTrue);
      expect(p.candidates.single.ref, '約3:16');
    });

    test('候選選填欄位型別錯誤 → 整池撤銷核准', () {
      final p = DailyVerseCandidatePool.fromJson({
        'approved': true,
        'candidates': [
          {'ref': '約3:16', 'date': 20260922},
        ],
      });
      expect(p.approved, isFalse);
      expect(p.isSchedulable, isFalse);
      expect(p.candidates, isEmpty);
    });

    test('Candidate 欄位型別錯 → 安全預設，不丟例外', () {
      final c = DailyVerseCandidate.fromJson({
        'ref': 42,
        'title': ['x'],
        'content': null,
        'date': 99,
      });
      expect(c.ref, '');
      expect(c.title, '');
      expect(c.content, '');
      expect(c.date, isNull);
    });
  });

  group('guardedRead：逾時保護（永不回傳 → 明確錯誤）', () {
    late DailyVerseBatchService svc;
    setUp(() {
      final fs = FakeFirebaseFirestore();
      svc = DailyVerseBatchService(fs, ContentWorkflowService(fs),
          operationTimeout: const Duration(milliseconds: 60));
    });

    test('永不完成的讀取 → 於 operationTimeout 內轉為 StateError（不永久等待）', () async {
      await expectLater(
        svc.guardedRead<int>(() => Completer<int>().future, '測試讀取'),
        throwsA(isA<StateError>()),
      );
    });

    test('正常讀取 → 直接回傳值', () async {
      final v = await svc.guardedRead<int>(() async => 7, 'ok');
      expect(v, 7);
    });

    test('讀取本身丟例外 → 原例外向上傳遞（非逾時）', () async {
      await expectLater(
        svc.guardedRead<int>(() => Future.error(ArgumentError('boom')), 'x'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('loadPool（fake firestore）：happy / empty / malformed 皆不 hang、不 crash', () {
    test('無候選池 doc → 空池（不 hang）', () async {
      final fs = FakeFirebaseFirestore();
      final svc = DailyVerseBatchService(fs, ContentWorkflowService(fs));
      final p = await svc.loadPool();
      expect(p.candidates, isEmpty);
      expect(p.approved, isFalse);
    });

    test('合法候選池 doc → 正確解析', () async {
      final fs = FakeFirebaseFirestore();
      await fs.collection('daily_verse_pool').doc('current').set({
        'version': 1,
        'approved': true,
        'source': 'auto',
        'candidates': [
          {'ref': '約3:16', 'date': '2026-09-22'},
        ],
      });
      final svc = DailyVerseBatchService(fs, ContentWorkflowService(fs));
      final p = await svc.loadPool();
      expect(p.version, 1);
      expect(p.approved, isTrue);
      expect(p.source, 'auto');
      expect(p.candidates.single.ref, '約3:16');
    });

    test('malformed 候選池 doc → 防禦性預設，不丟例外、不 hang', () async {
      final fs = FakeFirebaseFirestore();
      await fs.collection('daily_verse_pool').doc('current').set({
        'version': 'oops',
        'approved': 'yes',
        'candidates': {'not': 'a list'},
      });
      final svc = DailyVerseBatchService(fs, ContentWorkflowService(fs));
      final p = await svc.loadPool();
      expect(p.version, 0);
      expect(p.approved, isFalse);
      expect(p.candidates, isEmpty);
    });
  });

  group('adminListDailyVerses（fake firestore）：讀取完成、含 workspace/published 合併', () {
    test('workspace + published 合併，含 _date/_has_published', () async {
      final fs = FakeFirebaseFirestore();
      await fs.collection('daily_verses_workspace').doc('2026-09-22').set({
        'content_id': '2026-09-22',
        'status': 'draft',
        'version': 0,
      });
      await fs.collection('daily_verses').doc('2026-09-23').set({
        'status': 'published',
        'version': 1,
        'date': '2026-09-23',
      });
      final rows = await ContentService(fs).adminListDailyVerses();
      final byDate = {for (final r in rows) r['_date'] as String: r};
      expect(byDate.keys, containsAll(['2026-09-22', '2026-09-23']));
      expect(byDate['2026-09-22']!['_has_published'], isFalse);
      expect(byDate['2026-09-23']!['_has_published'], isTrue);
    });
  });
}
