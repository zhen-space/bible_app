import 'dart:convert';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/models/models.dart';
import 'package:bible_app/models/daily_verse_batch.dart';
import 'package:bible_app/services/content_workflow_service.dart';
import 'package:bible_app/services/daily_verse_batch_service.dart';
import 'package:bible_app/services/daily_verse_scheduler.dart';

List<Book> loadBooks() {
  final raw = File('assets/bible/cuv.json').readAsStringSync();
  final data = json.decode(raw) as Map<String, dynamic>;
  return (data['books'] as List)
      .map((b) => Book.fromJson(b as Map<String, dynamic>))
      .toList();
}

DailyVerseCandidate cand(String ref, {String title = '', String content = ''}) =>
    DailyVerseCandidate(ref: ref, title: title, content: content);

void main() {
  group('addDaysYmd（純日曆，台北日界 UTC 錨定）', () {
    test('連續日、跨月、跨年', () {
      expect(DailyVerseScheduler.addDaysYmd('2026-09-15', 0), '2026-09-15');
      expect(DailyVerseScheduler.addDaysYmd('2026-09-15', 1), '2026-09-16');
      expect(DailyVerseScheduler.addDaysYmd('2026-09-30', 1), '2026-10-01');
      expect(DailyVerseScheduler.addDaysYmd('2026-12-31', 1), '2027-01-01');
      expect(DailyVerseScheduler.addDaysYmd('2028-02-28', 1), '2028-02-29'); // 閏年
    });
  });

  group('deterministic 排程 + fail-closed', () {
    final pool = DailyVerseCandidatePool(approved: true, version: 1, candidates: [
      cand('約3:16'),
      cand('詩23:1'),
      cand('羅5:8'),
    ]);

    test('已核准非空池：依池序逐日指派、日期連續、結果確定性', () {
      final r1 = DailyVerseScheduler.scheduleDays(pool, startYmd: '2026-09-16', days: 30);
      final r2 = DailyVerseScheduler.scheduleDays(pool, startYmd: '2026-09-16', days: 30);
      expect(r1.ok, isTrue);
      // 候選 3 < 30 且未允許重複 → 只排 3 天 + shortfall 警告。
      expect(r1.assignments.length, 3);
      expect(r1.warnings, contains('shortfall:27'));
      expect(r1.assignments.map((a) => a.date).toList(),
          ['2026-09-16', '2026-09-17', '2026-09-18']);
      expect(r1.assignments.map((a) => a.candidate.ref).toList(),
          ['約3:16', '詩23:1', '羅5:8']);
      // determinism：同輸入同輸出。
      expect(r2.assignments.map((a) => '${a.date}|${a.candidate.ref}'),
          r1.assignments.map((a) => '${a.date}|${a.candidate.ref}'));
    });

    test('allowRepeat=true：round-robin 確定性填滿 days', () {
      final r = DailyVerseScheduler.scheduleDays(pool,
          startYmd: '2026-09-16', days: 7, allowRepeat: true);
      expect(r.assignments.length, 7);
      expect(r.assignments.map((a) => a.candidate.ref).toList(),
          ['約3:16', '詩23:1', '羅5:8', '約3:16', '詩23:1', '羅5:8', '約3:16']);
      expect(r.warnings, isEmpty);
    });

    test('未核准池 → fail-closed（pool_not_approved），不排任何日', () {
      final r = DailyVerseScheduler.scheduleDays(
          pool.copyWith(approved: false), startYmd: '2026-09-16');
      expect(r.ok, isFalse);
      expect(r.failClosedReason, 'pool_not_approved');
      expect(r.assignments, isEmpty);
    });

    test('空池 → fail-closed（pool_empty），不從整本聖經補位', () {
      final r = DailyVerseScheduler.scheduleDays(
          const DailyVerseCandidatePool(approved: true, candidates: []),
          startYmd: '2026-09-16');
      expect(r.ok, isFalse);
      expect(r.failClosedReason, 'pool_empty');
      expect(r.assignments, isEmpty);
    });

    test('候選≥days：正好排滿 days、無 shortfall', () {
      final big = DailyVerseCandidatePool(
          approved: true,
          candidates: [for (var i = 0; i < 30; i++) cand('約3:16')]);
      final r = DailyVerseScheduler.scheduleDays(big, startYmd: '2026-09-16', days: 30);
      expect(r.assignments.length, 30);
      expect(r.warnings, isEmpty);
      expect(r.assignments.last.date, '2026-10-15');
    });
  });

  group('buildDraftSpecs：正文只由 corpus 解析，不 fabricate', () {
    final books = loadBooks();

    test('可解析 ref → 帶 book/chapter/verse + resolvedText，refResolves true', () {
      final sched = DailyVerseScheduler.scheduleDays(
          DailyVerseCandidatePool(
              approved: true, candidates: [cand('約3:16', title: '神的愛')]),
          startYmd: '2026-09-16');
      final specs = DailyVerseScheduler.buildDraftSpecs(sched, books);
      expect(specs.length, 1);
      final s = specs.single;
      expect(s.refResolves, isTrue);
      expect(s.bookId, 43); // 約翰福音
      expect(s.chapter, 3);
      expect(s.verse, 16);
      expect(s.resolvedText, isNotNull);
      expect(s.resolvedText!.isNotEmpty, isTrue);
      expect(s.title, '神的愛'); // 使用者親撰，原樣保留
      // payload 不含正文（讀取端由 corpus 取）。
      expect(s.toPayload().containsKey('content'), isTrue);
      expect(s.toPayload().values.contains(s.resolvedText), isFalse);
    });

    test('無法解析 ref → refResolves false，不猜測、不補位', () {
      final sched = DailyVerseScheduler.scheduleDays(
          DailyVerseCandidatePool(
              approved: true, candidates: [cand('不存在的書99:99')]),
          startYmd: '2026-09-16');
      final specs = DailyVerseScheduler.buildDraftSpecs(sched, books);
      expect(specs.single.refResolves, isFalse);
      expect(specs.single.resolvedText, isNull);
      expect(specs.single.bookId, isNull);
    });

    test('validate：全解析且日期唯一 → canSubmit；有未解析 → 不可送出', () {
      final ok = [
        const DailyVerseDraftSpec(date: '2026-09-16', ref: '約3:16', refResolves: true),
        const DailyVerseDraftSpec(date: '2026-09-17', ref: '詩23:1', refResolves: true),
      ];
      expect(DailyVerseScheduler.validate(ok).canSubmit, isTrue);
      final bad = [
        const DailyVerseDraftSpec(date: '2026-09-16', ref: 'x', refResolves: false),
      ];
      final v = DailyVerseScheduler.validate(bad);
      expect(v.allResolve, isFalse);
      expect(v.unresolvedDates, ['2026-09-16']);
      expect(v.canSubmit, isFalse);
    });
  });

  group('候選池 repository（fake firestore）：版本化 + 人工核准', () {
    late FakeFirebaseFirestore fs;
    late DailyVerseBatchService svc;
    setUp(() {
      fs = FakeFirebaseFirestore();
      svc = DailyVerseBatchService(fs, ContentWorkflowService(fs));
    });

    test('預設無池 → 空、未核准、不可排程', () async {
      final p = await svc.loadPool();
      expect(p.candidates, isEmpty);
      expect(p.approved, isFalse);
      expect(p.isSchedulable, isFalse);
    });

    test('saveCandidates 後未核准；approvePool → approved 且 version+1', () async {
      await svc.saveCandidates([cand('約3:16'), cand('詩23:1')]);
      var p = await svc.loadPool();
      expect(p.candidates.length, 2);
      expect(p.approved, isFalse); // 編輯後需重新核准
      expect(p.isSchedulable, isFalse);
      final approved = await svc.approvePool();
      expect(approved.approved, isTrue);
      expect(approved.version, 1);
      p = await svc.loadPool();
      expect(p.isSchedulable, isTrue);
    });

    test('編輯已核准池 → approved 重置 false（需再核准）', () async {
      await svc.saveCandidates([cand('約3:16')]);
      await svc.approvePool();
      await svc.saveCandidates([cand('約3:16'), cand('羅5:8')]);
      expect((await svc.loadPool()).approved, isFalse);
    });

    test('空池不可核准（fail-closed）', () async {
      await expectLater(svc.approvePool(), throwsStateError);
    });
  });

  group('批次 workflow（fake firestore）：draft→review→publish、one-active-per-date', () {
    late FakeFirebaseFirestore fs;
    late DailyVerseBatchService svc;
    setUp(() {
      fs = FakeFirebaseFirestore();
      svc = DailyVerseBatchService(fs, ContentWorkflowService(fs));
    });

    List<DailyVerseDraftSpec> specs() => const [
          DailyVerseDraftSpec(
              date: '2026-09-16', ref: '約3:16', bookId: 43, chapter: 3, verse: 16, refResolves: true),
          DailyVerseDraftSpec(
              date: '2026-09-17', ref: '詩23:1', bookId: 19, chapter: 23, verse: 1, refResolves: true),
        ];

    test('applyDraftBatch 建立每日一筆 workspace 草稿（doc id=date）', () async {
      final dates = await svc.applyDraftBatch(specs(), editorEmail: 'a@x');
      expect(dates, ['2026-09-16', '2026-09-17']);
      final ws = await fs.collection('daily_verses_workspace').get();
      expect(ws.docs.map((d) => d.id).toSet(), {'2026-09-16', '2026-09-17'});
      expect(ws.docs.first.data()['status'], 'draft');
      expect(ws.docs.first.data()['content_type'], 'daily_verse');
    });

    test('fail-closed：任一 ref 未解析 → 整批拒絕、完全不寫入', () async {
      final bad = [
        const DailyVerseDraftSpec(date: '2026-09-16', ref: 'ok', bookId: 43, chapter: 3, verse: 16, refResolves: true),
        const DailyVerseDraftSpec(date: '2026-09-17', ref: 'bad', refResolves: false),
      ];
      await expectLater(svc.applyDraftBatch(bad, editorEmail: 'a@x'), throwsStateError);
      final ws = await fs.collection('daily_verses_workspace').get();
      expect(ws.docs, isEmpty); // 沒有部分寫入
    });

    test('空批次拒絕', () async {
      await expectLater(svc.applyDraftBatch(const [], editorEmail: 'a@x'), throwsStateError);
    });

    test('draft → submit → publish：published mirror 出現、doc id=date（one-active-per-date）', () async {
      final dates = await svc.applyDraftBatch(specs(), editorEmail: 'a@x');
      await svc.submitBatchForReview(dates, editorEmail: 'a@x');
      final review = await fs.collection('daily_verses_workspace').doc('2026-09-16').get();
      expect(review.data()!['status'], 'review');
      await svc.publishBatch(dates, publisherEmail: 'admin@x');
      final pub = await fs.collection('daily_verses').get();
      expect(pub.docs.map((d) => d.id).toSet(), {'2026-09-16', '2026-09-17'});
      final one = await fs.collection('daily_verses').doc('2026-09-16').get();
      expect(one.data()!['status'], 'published');
      expect(one.data()!['version'], 1);
      expect(one.data()!['date'], '2026-09-16');
      // one-active-per-date：同日期只有單一 doc。
      expect(pub.docs.where((d) => d.id == '2026-09-16').length, 1);
    });
  });
}
