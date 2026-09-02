import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/managed_content.dart';

/// 受管理內容的發佈工作流（Draft → Review → Published → Rejected/Archived）。
///
/// 每個內容型別有兩個 collection：
/// - **published mirror**（= 既有的公開 collection，如 `annotations`）：**只放 Published**，
///   學生端讀這裡；rules 要求 `status == 'published'` 才可公開讀。
/// - **workspace**（`<name>_workspace`）：Draft/Review/Rejected/Archived 的工作副本，
///   **僅管理員可讀寫**；學生端永遠讀不到。
///
/// 不變量：
/// - **新 Draft 不覆蓋目前 Published version**——草稿只寫 workspace；發佈才把快照複製到
///   published mirror 並 `version += 1`，舊 Published 快照推入 `versions`。
/// - 溯源與版本 metadata 一律寫齊（content_id/status/version/created/updated/reviewer/
///   reviewed_at/publisher/published_at/provenance）。
///
/// **序列化採「扁平」**（payload 欄位與 meta 欄位並存於 doc 頂層），以保留既有讀取端
/// （BookAnnotation.fromJson(doc) 等）相容；meta 為附加欄位，migration 為 additive。
class ContentWorkflowService {
  ContentWorkflowService(this._fs);
  final FirebaseFirestore _fs;

  /// meta 保留鍵：其餘頂層鍵視為 payload。
  static const reservedKeys = {
    'content_id',
    'content_type',
    'status',
    'version',
    'created_at',
    'created_by',
    'updated_at',
    'updated_by',
    'reviewed_by',
    'reviewed_at',
    'published_by',
    'published_at',
    'archived_at',
    'provenance',
    'visibility',
    'audience',
    'allowed_church_ids',
    'versions',
    // legacy 舊欄名（讀取相容；新寫入不再產生）
    'reviewer',
    'publisher',
  };

  CollectionReference<Map<String, dynamic>> _published(String type) =>
      _fs.collection(type);
  CollectionReference<Map<String, dynamic>> _workspace(String type) =>
      _fs.collection('${type}_workspace');

  static Map<String, dynamic> payloadOf(Map<String, dynamic> doc) => {
        for (final e in doc.entries)
          if (!reservedKeys.contains(e.key)) e.key: e.value,
      };

  Map<String, dynamic> _flat(ManagedContent c) => {
        ...c.payload,
        'content_id': c.contentId,
        'content_type': c.contentType,
        'status': c.status.name,
        'version': c.version,
        'created_at': c.createdAt,
        'created_by': c.createdBy,
        'updated_at': c.updatedAt,
        'updated_by': c.updatedBy,
        'reviewed_by': c.reviewedBy,
        'reviewed_at': c.reviewedAt,
        'published_by': c.publishedBy,
        'published_at': c.publishedAt,
        'archived_at': c.archivedAt,
        'provenance': c.provenance.toMap(),
        // visibility 僅在使用該維度（Study Content）時寫入，null 省略。
        if (c.visibility != null) 'visibility': c.visibility!.name,
        // audience/allowed_church_ids（Church/Teacher R1），null 省略。
        if (c.audience != null) 'audience': c.audience!.name,
        if (c.audience != null) 'allowed_church_ids': c.allowedChurchIds,
      };

  // ---- 讀取（管理端）----

  Future<ManagedContent?> getWorkspace(String type, String contentId) async {
    final d = await _workspace(type).doc(contentId).get();
    if (!d.exists) return null;
    final m = d.data()!;
    return ManagedContent.fromMap(d.id, {...m, 'payload': payloadOf(m)});
  }

  Future<ManagedContent?> getPublished(String type, String contentId) async {
    final d = await _published(type).doc(contentId).get();
    if (!d.exists) return null;
    final m = d.data()!;
    if (m['status'] != ContentStatus.published.name) return null;
    return ManagedContent.fromMap(d.id, {...m, 'payload': payloadOf(m)});
  }

  // ---- 工作流動作（管理員；uid/email 由呼叫端帶入，rules 再驗一次）----

  /// 建立/更新草稿（只動 workspace，不碰 published mirror）。
  /// 若目前是 review/rejected/published，編輯一律回到 draft（不影響已發佈的 live 版本）。
  Future<void> saveDraft(
    String type,
    String contentId, {
    required String contentType,
    required Map<String, dynamic> payload,
    required String editorEmail,
    ContentProvenance provenance = const ContentProvenance(),
    // Study Content 使用；其餘型別維持 null（不寫 visibility 欄位）。
    // 傳入時覆蓋既有；null 時沿用既有草稿的 visibility（新建則保持 null）。
    Visibility? visibility,
    // Church/Teacher R1：對象授權。傳入覆蓋既有；null 時沿用既有草稿（新建保持 null）。
    Audience? audience,
    List<String>? allowedChurchIds,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await getWorkspace(type, contentId);
    final published = await _published(type).doc(contentId).get();
    final baseVersion = existing?.version ??
        ((published.data()?['version'] as int?) ?? 0);
    final effAudience = audience ?? existing?.audience;
    final c = ManagedContent(
      contentId: contentId,
      contentType: contentType,
      status: ContentStatus.draft,
      version: baseVersion,
      createdAt: existing?.createdAt ?? now,
      createdBy: existing?.createdBy ?? editorEmail,
      updatedAt: now,
      updatedBy: editorEmail,
      reviewedBy: existing?.reviewedBy ?? '',
      reviewedAt: existing?.reviewedAt ?? 0,
      publishedBy: existing?.publishedBy ?? '',
      publishedAt: existing?.publishedAt ?? 0,
      provenance: provenance,
      visibility: visibility ?? existing?.visibility,
      audience: effAudience,
      allowedChurchIds:
          allowedChurchIds ?? existing?.allowedChurchIds ?? const [],
      payload: payload,
    );
    await _workspace(type).doc(contentId).set(_flat(c));
  }

  /// 從目前 Published version 建立新的 workspace 草稿（**不動 Published live 版本**）。
  /// 用於「編輯已發佈內容」與「改 visibility」——皆須走新草稿 → 審核 → 發佈，
  /// 不得直接修改 Published（見 spec E3/A8/A14）。複製 payload/contentType/
  /// **visibility**/provenance；version 沿用 Published 現值（發佈時才 +1）。
  Future<void> createDraftFromPublished(
    String type,
    String contentId, {
    required String editorEmail,
  }) async {
    final pub = await _published(type).doc(contentId).get();
    if (!pub.exists) {
      throw StateError('Published 內容不存在，無法建立草稿：$type/$contentId');
    }
    final m = pub.data()!;
    final src = ManagedContent.fromMap(pub.id, {...m, 'payload': payloadOf(m)});
    final now = DateTime.now().millisecondsSinceEpoch;
    final draft = ManagedContent(
      contentId: contentId,
      contentType: src.contentType,
      status: ContentStatus.draft,
      version: src.version, // 發佈時才 +1；草稿沿用目前 Published 版號
      createdAt: src.createdAt,
      createdBy: src.createdBy,
      updatedAt: now,
      updatedBy: editorEmail,
      reviewedBy: '',
      reviewedAt: 0,
      publishedBy: src.publishedBy,
      publishedAt: src.publishedAt,
      provenance: src.provenance,
      visibility: src.visibility,
      audience: src.audience,
      allowedChurchIds: src.allowedChurchIds,
      payload: src.payload,
    );
    await _workspace(type).doc(contentId).set(_flat(draft));
  }

  Future<void> submitForReview(
      String type, String contentId, String editorEmail) async {
    await _workspace(type).doc(contentId).update({
      'status': ContentStatus.review.name,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'updated_by': editorEmail,
    });
  }

  Future<void> reject(
      String type, String contentId, String reviewerEmail) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _workspace(type).doc(contentId).update({
      'status': ContentStatus.rejected.name,
      'reviewed_by': reviewerEmail,
      'reviewed_at': now,
      'updated_at': now,
      'updated_by': reviewerEmail,
    });
  }

  /// 核准並發佈：把 workspace 目前內容複製到 published mirror，version +1，
  /// 舊 Published 快照推入 `versions`。要求 workspace 目前為 review（或 draft）。
  Future<void> approveAndPublish(
    String type,
    String contentId, {
    required String publisherEmail,
    // Study Content 傳 true：把舊 Published 快照寫入 `versions/{version}` 子集合
    // （spec 明列 study_content/{id}/versions/{versionId}）。其餘型別維持既有
    // `versions` 陣列快照，行為不變。
    bool snapshotToSubcollection = false,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final ws = await getWorkspace(type, contentId);
    if (ws == null) {
      throw StateError('workspace 內容不存在：$type/$contentId');
    }
    final pubRef = _published(type).doc(contentId);
    final prev = await pubRef.get();
    final prevVersion = (prev.data()?['version'] as int?) ?? 0;
    final newVersion = prevVersion + 1;

    final publishedDoc = _flat(ManagedContent(
      contentId: contentId,
      contentType: ws.contentType,
      status: ContentStatus.published,
      version: newVersion,
      createdAt: ws.createdAt,
      createdBy: ws.createdBy,
      updatedAt: now,
      updatedBy: publisherEmail,
      reviewedBy: ws.reviewedBy,
      reviewedAt: ws.reviewedAt,
      publishedBy: publisherEmail,
      publishedAt: now,
      provenance: ws.provenance,
      visibility: ws.visibility,
      audience: ws.audience,
      allowedChurchIds: ws.allowedChurchIds,
      payload: ws.payload,
    ));
    // 舊 Published 快照留存
    if (prev.exists &&
        prev.data()?['status'] == ContentStatus.published.name) {
      final old = Map<String, dynamic>.from(prev.data()!)..remove('versions');
      if (snapshotToSubcollection) {
        // 唯讀歷史版本子集合：doc id = 舊版號。rules 設為 admin-only，
        // 學生不得經此繞過 current visibility。
        await pubRef
            .collection('versions')
            .doc('$prevVersion')
            .set({...old, 'snapshot_at': now});
      } else {
        publishedDoc['versions'] = FieldValue.arrayUnion([
          {...old, 'snapshot_at': now}
        ]);
      }
    }
    await pubRef.set(publishedDoc, SetOptions(merge: true));

    // workspace 標記為 published（反映 live 狀態；再編輯會回 draft）
    await _workspace(type).doc(contentId).update({
      'status': ContentStatus.published.name,
      'version': newVersion,
      'published_by': publisherEmail,
      'published_at': now,
      'updated_at': now,
      'updated_by': publisherEmail,
    });
  }

  /// 封存：把 published mirror 撤下（status → archived，學生端立即讀不到），
  /// workspace 也標記 archived。歷史 `versions` 保留。
  Future<void> archive(
      String type, String contentId, String publisherEmail) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final pubRef = _published(type).doc(contentId);
    if ((await pubRef.get()).exists) {
      await pubRef.update({
        'status': ContentStatus.archived.name,
        'archived_at': now,
        'updated_at': now,
        'updated_by': publisherEmail,
      });
    }
    final wsRef = _workspace(type).doc(contentId);
    if ((await wsRef.get()).exists) {
      await wsRef.update({
        'status': ContentStatus.archived.name,
        'archived_at': now,
        'updated_at': now,
        'updated_by': publisherEmail,
      });
    }
  }
}
