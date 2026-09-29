import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/models/daily_verse_batch.dart';
import 'package:bible_app/services/content_workflow_service.dart';
import 'package:bible_app/services/daily_verse_batch_service.dart';

/// 批次 Review/Publish 部分失敗復原的 regression（PR #18 follow-up review）：
/// 逐日 receipt、單筆失敗不中斷、逾時→unknown、跳過已完成、**絕不重新發佈**、
/// 純函式閘門（mixed status 續作、stale/anomaly blocked），以及不自動觸發 Review/Publish。

/// 在指定日期讓 submitForReview 丟例外（模擬第 N 筆失敗）。
class _FailSubmitWorkflow extends ContentWorkflowService {
  _FailSubmitWorkflow(super.fs, this.failDate);
  final String failDate;
  @override
  Future<void> submitForReview(String type, String id, String email) async {
    if (id == failDate) throw StateError('boom @$id');
    return super.submitForReview(type, id, email);
  }
}

/// 在指定日期讓 submitForReview 永不返回（模擬 web 長連線卡死 → unknown）。
class _HangSubmitWorkflow extends ContentWorkflowService {
  _HangSubmitWorkflow(super.fs, this.hangDate);
  final String hangDate;
  @override
  Future<void> submitForReview(String type, String id, String email) {
    if (id == hangDate) return Completer<void>().future;
    return super.submitForReview(type, id, email);
  }
}

Future<void> seedWorkspace(
  FakeFirebaseFirestore fs,
  String date,
  String status,
) =>
    fs.collection('daily_verses_workspace').doc(date).set({
      'content_id': date,
      'content_type': 'daily_verse',
      'status': status,
      'version': 0,
    });

DailyVerseReconciliationItem recItem(String date, String? status) =>
    DailyVerseReconciliationItem(
      date: date,
      workspaceExists: status != null,
      workspaceStatus: status,
      publishedExists: status == 'published',
      publishedStatus: status == 'published' ? 'published' : null,
    );

void main() {
  group('submitBatchForReview：逐筆、跳過、衝突、不中斷', () {
    late FakeFirebaseFirestore fs;
    setUp(() => fs = FakeFirebaseFirestore());

    test('全 draft → 全 transitioned，workspace 變 review', () async {
      for (final d in ['2026-09-22', '2026-09-23']) {
        await seedWorkspace(fs, d, 'draft');
      }
      final svc = DailyVerseBatchService(fs, ContentWorkflowService(fs));
      final r = await svc.submitBatchForReview(
        ['2026-09-22', '2026-09-23'],
        editorEmail: 'a@x',
      );
      expect(r.transitioned, 2);
      expect(r.needsReconciliation, isFalse);
      final s = await fs
          .collection('daily_verses_workspace')
          .doc('2026-09-22')
          .get();
      expect(s.data()!['status'], 'review');
    });

    test('已 review → skipped（idempotent，不重做）；已 published → conflict（不倒退）', () async {
      await seedWorkspace(fs, 'd1', 'review');
      await seedWorkspace(fs, 'd2', 'published');
      await seedWorkspace(fs, 'd3', 'draft');
      final svc = DailyVerseBatchService(fs, ContentWorkflowService(fs));
      final r = await svc.submitBatchForReview(
        ['d1', 'd2', 'd3'],
        editorEmail: 'a@x',
      );
      expect(r.skipped, 1); // d1
      expect(r.conflicts, 1); // d2
      expect(r.transitioned, 1); // d3
      // d2 未被倒退
      final d2 = await fs.collection('daily_verses_workspace').doc('d2').get();
      expect(d2.data()!['status'], 'published');
    });

    test('第 N 筆失敗不中斷：其餘仍處理，失敗筆狀態不變', () async {
      for (final d in ['d1', 'd2', 'd3']) {
        await seedWorkspace(fs, d, 'draft');
      }
      final svc = DailyVerseBatchService(fs, _FailSubmitWorkflow(fs, 'd2'));
      final r = await svc.submitBatchForReview(
        ['d1', 'd2', 'd3'],
        editorEmail: 'a@x',
      );
      expect(r.transitioned, 2); // d1, d3
      expect(r.failed, 1); // d2
      final byDate = {for (final i in r.items) i.date: i.outcome};
      expect(byDate['d2'], DailyVerseStageOutcome.failed);
      final d2 = await fs.collection('daily_verses_workspace').doc('d2').get();
      expect(d2.data()!['status'], 'draft'); // 未轉移
      final d3 = await fs.collection('daily_verses_workspace').doc('d3').get();
      expect(d3.data()!['status'], 'review'); // 失敗筆之後仍處理
    });

    test('逾時 → unknown（結果未知），不中斷其他筆', () async {
      for (final d in ['d1', 'd2']) {
        await seedWorkspace(fs, d, 'draft');
      }
      final svc = DailyVerseBatchService(
        fs,
        _HangSubmitWorkflow(fs, 'd1'),
        operationTimeout: const Duration(milliseconds: 60),
      );
      final r = await svc.submitBatchForReview(['d1', 'd2'], editorEmail: 'a@x');
      final byDate = {for (final i in r.items) i.date: i.outcome};
      expect(byDate['d1'], DailyVerseStageOutcome.unknown);
      expect(byDate['d2'], DailyVerseStageOutcome.transitioned);
      expect(r.needsReconciliation, isTrue);
    });

    test('workspace 不存在 → conflict（不動作）', () async {
      final svc = DailyVerseBatchService(fs, ContentWorkflowService(fs));
      final r = await svc.submitBatchForReview(['missing'], editorEmail: 'a@x');
      expect(r.conflicts, 1);
    });
  });

  group('publishBatch：絕不重新發佈、未 review 不發佈', () {
    late FakeFirebaseFirestore fs;
    setUp(() => fs = FakeFirebaseFirestore());

    test('review → 發佈；published → skipped（絕不重新發佈、不 bump version）；draft → conflict', () async {
      await seedWorkspace(fs, 'r', 'review');
      await seedWorkspace(fs, 'p', 'published');
      await seedWorkspace(fs, 'd', 'draft');
      // p 已有 published mirror（version 7）——確認不被重發、version 不變。
      await fs.collection('daily_verses').doc('p').set({
        'status': 'published',
        'version': 7,
        'date': 'p',
      });
      final svc = DailyVerseBatchService(fs, ContentWorkflowService(fs));
      final r = await svc.publishBatch(['r', 'p', 'd'], publisherEmail: 'admin@x');
      final byDate = {for (final i in r.items) i.date: i.outcome};
      expect(byDate['r'], DailyVerseStageOutcome.transitioned);
      expect(byDate['p'], DailyVerseStageOutcome.skipped);
      expect(byDate['d'], DailyVerseStageOutcome.conflict);
      // p 的 published version 未變（未重新發佈）
      final p = await fs.collection('daily_verses').doc('p').get();
      expect(p.data()!['version'], 7);
      // d（draft）沒有被發佈到 mirror
      final d = await fs.collection('daily_verses').doc('d').get();
      expect(d.exists, isFalse);
    });

    test('不自動觸發：對全 draft 執行 publishBatch → 全 conflict，無任何 published mirror', () async {
      for (final d in ['d1', 'd2']) {
        await seedWorkspace(fs, d, 'draft');
      }
      final svc = DailyVerseBatchService(fs, ContentWorkflowService(fs));
      final r = await svc.publishBatch(['d1', 'd2'], publisherEmail: 'admin@x');
      expect(r.conflicts, 2);
      final pub = await fs.collection('daily_verses').get();
      expect(pub.docs, isEmpty);
    });

    test('部分發佈失敗後重試：published 略過、review 補發（安全重試）', () async {
      await seedWorkspace(fs, 'a', 'published'); // 上一輪已成功
      await seedWorkspace(fs, 'b', 'review'); // 上一輪失敗，仍待發
      final svc = DailyVerseBatchService(fs, ContentWorkflowService(fs));
      final r = await svc.publishBatch(['a', 'b'], publisherEmail: 'admin@x');
      final byDate = {for (final i in r.items) i.date: i.outcome};
      expect(byDate['a'], DailyVerseStageOutcome.skipped);
      expect(byDate['b'], DailyVerseStageOutcome.transitioned);
    });
  });

  group('DailyVerseStageGate（純函式）：新鮮完整佐證才可續作', () {
    final dates = {'d1', 'd2'};

    test('無佐證 → blocked', () {
      final g = DailyVerseStageGate.evaluate(expectedDates: dates, evidence: null);
      expect(g.canReview, isFalse);
      expect(g.canPublish, isFalse);
    });

    test('全 draft → canReview，!canPublish', () {
      final g = DailyVerseStageGate.evaluate(
        expectedDates: dates,
        evidence: DailyVerseReconciliationResult([
          recItem('d1', 'draft'),
          recItem('d2', 'draft'),
        ]),
      );
      expect(g.canReview, isTrue);
      expect(g.canPublish, isFalse);
    });

    test('mixed draft+review → canReview（補落單），!canPublish（仍有 draft）', () {
      final g = DailyVerseStageGate.evaluate(
        expectedDates: dates,
        evidence: DailyVerseReconciliationResult([
          recItem('d1', 'draft'),
          recItem('d2', 'review'),
        ]),
      );
      expect(g.canReview, isTrue);
      expect(g.canPublish, isFalse);
    });

    test('全 review → canPublish，!canReview', () {
      final g = DailyVerseStageGate.evaluate(
        expectedDates: dates,
        evidence: DailyVerseReconciliationResult([
          recItem('d1', 'review'),
          recItem('d2', 'review'),
        ]),
      );
      expect(g.canPublish, isTrue);
      expect(g.canReview, isFalse);
    });

    test('review+published（部分發佈後）→ canPublish（發剩餘 review），!canReview', () {
      final g = DailyVerseStageGate.evaluate(
        expectedDates: dates,
        evidence: DailyVerseReconciliationResult([
          recItem('d1', 'published'),
          recItem('d2', 'review'),
        ]),
      );
      expect(g.canPublish, isTrue);
      expect(g.canReview, isFalse);
    });

    test('佐證缺一日 → blocked（不完整）', () {
      final g = DailyVerseStageGate.evaluate(
        expectedDates: dates,
        evidence: DailyVerseReconciliationResult([recItem('d1', 'draft')]),
      );
      expect(g.evidenceComplete, isFalse);
      expect(g.canReview, isFalse);
      expect(g.canPublish, isFalse);
    });

    test('佐證有異常 → blocked（狀態未知）', () {
      final g = DailyVerseStageGate.evaluate(
        expectedDates: dates,
        evidence: DailyVerseReconciliationResult([
          recItem('d1', 'draft'),
          const DailyVerseReconciliationItem(
            date: 'd2',
            workspaceExists: true,
            workspaceStatus: 'draft',
            publishedExists: false,
            anomalies: ['read failed/unknown'],
          ),
        ]),
      );
      expect(g.canReview, isFalse);
      expect(g.canPublish, isFalse);
    });
  });
}
