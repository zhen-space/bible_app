import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/daily_verse_batch.dart';
import '../models/models.dart';
import '../utils/date_key.dart';
import 'content_workflow_service.dart';
import 'daily_verse_auto_selector.dart';
import 'daily_verse_scheduler.dart';

/// 每日經文批次的 Firestore 存取 + workflow 包裝層。
///
/// - 候選池存於 `daily_verse_pool/current`（單一 doc；使用者親自建立/核准，不 fabricate）。
/// - 批次草稿/送審/發佈**沿用既有 [ContentWorkflowService]**（type='daily_verses'、
///   contentId=日期），不另造 workflow engine；one-active-per-date 由 doc-id=date 保證。
/// - **fail-closed**：批次 apply 前若有任何 ref 無法解析，整批拒絕（不寫入部分髒資料）。
///
/// ⚠️ 這些方法會寫 Firestore；正式 production 執行需管理員 + 憑證環境。單元測試以
/// fake_cloud_firestore 驗證，不對 production 寫入。
class DailyVerseBatchService {
  DailyVerseBatchService(this._fs, this._workflow);
  final FirebaseFirestore _fs;
  final ContentWorkflowService _workflow;

  static const type = 'daily_verses';
  static const _contentType = 'daily_verse';

  DocumentReference<Map<String, dynamic>> get _poolDoc =>
      _fs.collection('daily_verse_pool').doc('current');

  // ---- 候選池（版本化、人工核准）----

  Future<DailyVerseCandidatePool> loadPool() async {
    final d = await _poolDoc.get();
    if (!d.exists) return const DailyVerseCandidatePool();
    return DailyVerseCandidatePool.fromJson(d.data()!);
  }

  /// 更新候選清單。**任何編輯都會使 approved 重置為 false**（需重新人工核准才可排程）。
  /// version 不變（核准時才 +1）。候選內容由呼叫端提供，本層不 fabricate。
  Future<void> saveCandidates(List<DailyVerseCandidate> candidates) async {
    final cur = await loadPool();
    await _poolDoc.set(
      cur
          .copyWith(
            candidates: candidates,
            approved: false,
            source: 'manual',
            catalogVersion: 0,
            algoVersion: 0,
          )
          .toJson(),
    );
  }

  /// 人工核准候選池：approved=true 且 version+1。空候選不得核准（fail-closed）。
  Future<DailyVerseCandidatePool> approvePool() async {
    final cur = await loadPool();
    if (cur.candidates.isEmpty) {
      throw StateError('候選池為空，不可核准（fail-closed）。');
    }
    final next = cur.copyWith(approved: true, version: cur.version + 1);
    await _poolDoc.set(next.toJson());
    return next;
  }

  // ---- 自動選取（curated catalog + corpus 正文，deterministic、fail-closed）----

  /// 讀取現行已 Published 的每日經文，供自動選取「鎖定已發布日期」與「365 天防重複」。
  /// 回傳 (publishedByDate, history)：前者只含**排程視窗涵蓋日期**，後者為全部已發布使用紀錄。
  Future<
      ({
        Map<String, ({int bookId, int chapter, int verse})> publishedByDate,
        List<({String date, int bookId, int chapter, int verse})> history,
      })> loadPublishedHistory() async {
    final snap = await _dailyVerses.get();
    final byDate = <String, ({int bookId, int chapter, int verse})>{};
    final history = <({String date, int bookId, int chapter, int verse})>[];
    for (final d in snap.docs) {
      final m = d.data();
      if (m['status'] != 'published') continue;
      final date = (m['date'] as String?) ?? d.id;
      final bookId = m['book_id'] as int?;
      final chapter = m['chapter'] as int?;
      final verse = m['verse'] as int?;
      if (bookId == null || chapter == null || verse == null) continue;
      byDate[date] = (bookId: bookId, chapter: chapter, verse: verse);
      history.add((date: date, bookId: bookId, chapter: chapter, verse: verse));
    }
    return (publishedByDate: byDate, history: history);
  }

  CollectionReference<Map<String, dynamic>> get _dailyVerses =>
      _fs.collection('daily_verses');

  /// 系統自動產生未來 [days] 天計畫（deterministic；正文由 corpus；已發布日期鎖定；
  /// 候選不足 fail-closed 留白）。[startYmd] 預設「明天（台北）」。
  Future<DailyVerseAutoPlan> generateAutoPlan({
    required List<Book> books,
    String? startYmd,
    int days = 30,
  }) async {
    final start = startYmd ?? DailyVerseScheduler.addDaysYmd(taipeiTodayYmd(), 1);
    final hist = await loadPublishedHistory();
    return DailyVerseAutoSelector.generate(
      books: books,
      startYmd: start,
      days: days,
      publishedByDate: hist.publishedByDate,
      history: hist.history,
    );
  }

  /// 把自動計畫的**可建立日**存入候選池（approved=false，需人工核准），
  /// 帶 date 與 provenance（source='auto'、catalog/algo 版本、generatedAt）。
  /// ⛔ 只存節位（ref/date），正文不落池（讀取端由 corpus 解析）。
  Future<DailyVerseCandidatePool> saveAutoPlan(DailyVerseAutoPlan plan) async {
    final candidates = [
      for (final d in plan.draftableDays)
        DailyVerseCandidate(ref: d.ref, date: d.date),
    ];
    if (candidates.isEmpty) {
      throw StateError('計畫中沒有可建立的日期（全部已發布或 fail-closed）。');
    }
    final cur = await loadPool();
    final next = cur.copyWith(
      candidates: candidates,
      approved: false,
      source: 'auto',
      catalogVersion: plan.catalogVersion,
      algoVersion: plan.algoVersion,
      generatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _poolDoc.set(next.toJson());
    return next;
  }

  // ---- 批次 workflow（沿用 ContentWorkflowService）----

  /// 建立整批 Draft。**fail-closed**：任一 spec ref 無法解析或有重複日期 → 整批拒絕、不寫入。
  /// 回傳實際建立的日期清單。
  Future<List<String>> applyDraftBatch(
    List<DailyVerseDraftSpec> specs, {
    required String editorEmail,
  }) async {
    final v = DailyVerseScheduler.validate(specs);
    if (specs.isEmpty) throw StateError('沒有可建立的草稿（空批次）。');
    if (!v.allResolve) {
      throw StateError('有 ref 無法解析，整批拒絕（fail-closed）：${v.unresolvedDates.join(", ")}');
    }
    if (v.hasDuplicateDates) throw StateError('批次含重複日期，拒絕。');
    for (final s in specs) {
      await _workflow.saveDraft(
        type,
        s.date, // contentId = 日期
        contentType: _contentType,
        payload: s.toPayload(),
        editorEmail: editorEmail,
      );
    }
    return [for (final s in specs) s.date];
  }

  /// 批次送審（逐日 submitForReview）。
  Future<void> submitBatchForReview(List<String> dates, {required String editorEmail}) async {
    for (final ymd in dates) {
      await _workflow.submitForReview(type, ymd, editorEmail);
    }
  }

  /// 批次發佈（逐日 approveAndPublish）。one-active-per-date 由 doc-id=date 保證。
  Future<void> publishBatch(List<String> dates, {required String publisherEmail}) async {
    for (final ymd in dates) {
      await _workflow.approveAndPublish(type, ymd, publisherEmail: publisherEmail);
    }
  }
}
