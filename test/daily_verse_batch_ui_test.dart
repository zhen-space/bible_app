import 'dart:convert';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/models/models.dart';
import 'package:bible_app/models/daily_verse_batch.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/services/content_workflow_service.dart';
import 'package:bible_app/services/daily_verse_batch_service.dart';
import 'package:bible_app/screens/admin_daily_verse_batch_screen.dart';

List<Book> loadBooks() {
  final raw = File('assets/bible/cuv.json').readAsStringSync();
  final data = json.decode(raw) as Map<String, dynamic>;
  return (data['books'] as List)
      .map((b) => Book.fromJson(b as Map<String, dynamic>))
      .toList();
}

/// 可程式化控制的假服務：只覆寫畫面用到的方法，讓 UI/state 行為可被斷言。
class _FakeBatchService extends DailyVerseBatchService {
  _FakeBatchService(super.fs, super.wf);

  DailyVerseDraftBatchResult draftResult = const DailyVerseDraftBatchResult([
    DailyVerseDraftItemResult(
        date: '2026-09-22', outcome: DailyVerseDraftOutcome.created),
    DailyVerseDraftItemResult(
        date: '2026-09-23', outcome: DailyVerseDraftOutcome.created),
  ]);
  bool reconcileThrows = false;
  DailyVerseReconciliationResult reconcileResult =
      const DailyVerseReconciliationResult([]);
  int reconcileCalls = 0;

  @override
  Future<
      ({
        Map<String, ({int bookId, int chapter, int verse})> publishedByDate,
        List<({String date, int bookId, int chapter, int verse})> history,
      })> loadPublishedHistory() async => (
        publishedByDate: const <String, ({int bookId, int chapter, int verse})>{},
        history: const <({String date, int bookId, int chapter, int verse})>[],
      );

  @override
  Future<DailyVerseDraftBatchResult> applyDraftBatch(
    List<DailyVerseDraftSpec> specs, {
    required String editorEmail,
  }) async =>
      draftResult;

  @override
  Future<DailyVerseReconciliationResult> reconcileDates(
      Iterable<String> dates) async {
    reconcileCalls++;
    if (reconcileThrows) throw StateError('recon-fail');
    return reconcileResult;
  }

  @override
  Future<DailyVerseStageBatchResult> submitBatchForReview(
    List<String> dates, {
    required String editorEmail,
  }) async =>
      const DailyVerseStageBatchResult([]);

  @override
  Future<DailyVerseStageBatchResult> publishBatch(
    List<String> dates, {
    required String publisherEmail,
  }) async =>
      const DailyVerseStageBatchResult([]);
}

DailyVerseReconciliationItem _item(String date, String status) =>
    DailyVerseReconciliationItem(
      date: date,
      workspaceExists: true,
      workspaceStatus: status,
      publishedExists: status == 'published',
      publishedStatus: status == 'published' ? 'published' : null,
    );

bool _btnEnabled(WidgetTester tester, String label) {
  final f = find.ancestor(
    of: find.text(label),
    matching: find.bySubtype<OutlinedButton>(),
  );
  final w = tester.widget<OutlinedButton>(f);
  return w.onPressed != null;
}

DailyVerseCandidatePool _approvedAutoPool() => const DailyVerseCandidatePool(
      version: 1,
      approved: true,
      source: 'auto',
      catalogVersion: 1,
      algoVersion: 1,
      candidates: [
        DailyVerseCandidate(ref: '約3:16', date: '2026-09-22'),
        DailyVerseCandidate(ref: '詩23:1', date: '2026-09-23'),
      ],
    );

void main() {
  final books = loadBooks();

  Future<_FakeBatchService> pump(
    WidgetTester tester, {
    required void Function(_FakeBatchService) configure,
  }) async {
    final fake = _FakeBatchService(FakeFirebaseFirestore(),
        ContentWorkflowService(FakeFirebaseFirestore()));
    configure(fake);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyVersePoolProvider.overrideWith((ref) async => _approvedAutoPool()),
          booksProvider.overrideWith((ref) async => books),
          adminEmailProvider.overrideWithValue('a@x'),
          dailyVerseBatchServiceProvider.overrideWithValue(fake),
        ],
        child: const MaterialApp(home: AdminDailyVerseBatchScreen()),
      ),
    );
    await tester.pumpAndSettle();
    // 載入先前產生的候選 → 由帶 date 的池建計畫（approved → 不 dirty → 可建立 Draft）。
    // 注意：按鈕以 *.icon 建立，其 runtime 型別是 OutlinedButton 的子型別，
    // find.byType（精確型別）無法匹配，故一律以文字定位點擊。
    await tester.tap(find.text('載入先前產生的候選'));
    await tester.pumpAndSettle();
    return fake;
  }

  Future<void> tapConfirm(WidgetTester tester, String buttonLabel) async {
    await tester.tap(find.text(buttonLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();
  }

  // *.icon 按鈕 → 以 bySubtype 找按鈕本體讀 onPressed 判斷是否啟用。
  bool reviewEnabled(WidgetTester tester) => _btnEnabled(tester, '批次送 Review');
  bool publishEnabled(WidgetTester tester) => _btnEnabled(tester, '批次 Publish');

  testWidgets('計畫載入後可見「建立 Draft」', (tester) async {
    await pump(tester, configure: (_) {});
    expect(find.text('建立 2 筆 Draft'), findsOneWidget);
  });

  testWidgets('Draft receipt 在後續 reconciliation 失敗後仍可見；佐證卡不出現', (tester) async {
    await pump(tester, configure: (f) => f.reconcileThrows = true);
    await tapConfirm(tester, '建立 2 筆 Draft');
    // receipt 卡仍在；reconciliation 卡不出現（佐證清空）。
    expect(find.text('最近一次 Draft 建立結果'), findsOneWidget);
    expect(find.text('Production 唯讀 reconciliation'), findsNothing);
  });

  testWidgets('操作開始清除過時 reconciliation：先有佐證，Draft reconcile 失敗後佐證消失', (tester) async {
    final fake = await pump(tester, configure: (f) {
      f.reconcileThrows = false;
      f.reconcileResult = DailyVerseReconciliationResult([
        _item('2026-09-22', 'draft'),
        _item('2026-09-23', 'draft'),
      ]);
    });
    // 先唯讀核對 → 佐證卡出現。
    await tester.tap(find.text('唯讀核對這 30 天'));
    await tester.pumpAndSettle();
    expect(find.text('Production 唯讀 reconciliation'), findsOneWidget);
    // 之後 Draft 的 reconcile 失敗 → 佐證卡消失、draft receipt 出現。
    fake.reconcileThrows = true;
    await tapConfirm(tester, '建立 2 筆 Draft');
    expect(find.text('Production 唯讀 reconciliation'), findsNothing);
    expect(find.text('最近一次 Draft 建立結果'), findsOneWidget);
  });

  testWidgets('mixed draft/review 佐證：只開放送 Review（Publish 仍鎖）', (tester) async {
    await pump(tester, configure: (f) {
      f.reconcileResult = DailyVerseReconciliationResult([
        _item('2026-09-22', 'draft'),
        _item('2026-09-23', 'review'),
      ]);
    });
    await tester.tap(find.text('唯讀核對這 30 天'));
    await tester.pumpAndSettle();
    expect(reviewEnabled(tester), isTrue);
    expect(publishEnabled(tester), isFalse);
  });

  testWidgets('review/published 佐證（部分發佈後）：只開放 Publish（Review 鎖）', (tester) async {
    await pump(tester, configure: (f) {
      f.reconcileResult = DailyVerseReconciliationResult([
        _item('2026-09-22', 'published'),
        _item('2026-09-23', 'review'),
      ]);
    });
    await tester.tap(find.text('唯讀核對這 30 天'));
    await tester.pumpAndSettle();
    expect(publishEnabled(tester), isTrue);
    expect(reviewEnabled(tester), isFalse);
  });

  testWidgets('reconciliation 失敗/未知 → Review 與 Publish 皆保持封鎖', (tester) async {
    await pump(tester, configure: (f) => f.reconcileThrows = true);
    await tester.tap(find.text('唯讀核對這 30 天'));
    await tester.pumpAndSettle();
    expect(reviewEnabled(tester), isFalse);
    expect(publishEnabled(tester), isFalse);
  });

  group('dailyVerseStageAdvisory（純函式）：不得在佐證 null 時宣稱已核對', () {
    test('needsReconciliation 且 reconciled → 已重新核對', () {
      final s = dailyVerseStageAdvisory(
          needsReconciliation: true, reconciled: true);
      expect(s.contains('已重新核對'), isTrue);
    });
    test('needsReconciliation 但 reconciled=false → 失敗/未知、封鎖，不宣稱已核對', () {
      final s = dailyVerseStageAdvisory(
          needsReconciliation: true, reconciled: false);
      expect(s.contains('已重新核對'), isFalse);
      expect(s.contains('失敗') || s.contains('未知'), isTrue);
    });
    test('不需要 reconciliation → 空字串', () {
      expect(
        dailyVerseStageAdvisory(needsReconciliation: false, reconciled: true),
        '',
      );
    });
  });
}
