import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/daily_verse_batch.dart';
import 'content_workflow_service.dart';
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
      cur.copyWith(candidates: candidates, approved: false).toJson(),
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
