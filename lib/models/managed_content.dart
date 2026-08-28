/// 受管理內容（managed content）的通用外殼：Draft → Review → Published，
/// 以及 Rejected / Archived。用於所有「管理員發佈、學生端讀取」的內容：
/// annotations（卷/章導讀、節註解）、knowledge、daily_verses、reading_plans …
///
/// 設計原則（對應 #8/#9 需求）：
/// - **只有 Published 才能被學生端取得**；Draft/Review/Rejected/Archived 永遠不得外流，
///   且不能只靠 UI 隱藏——Firestore rules 真正阻擋（見 firestore.rules）。
/// - **新 Draft 不得覆蓋目前 Published version**：草稿寫在 workspace collection，
///   發佈才把快照複製到 published mirror 並 bump version；歷史版本保留在 `versions`。
/// - 版本 + 溯源（provenance）：stable content id、status、version、建立/更新/審核/
///   發佈 metadata、reviewer/publisher、source/provenance。
library;

/// 內容狀態機。字串值即 Firestore 儲存值（rules 依此判斷），順序/字面不可隨意改。
enum ContentStatus {
  draft, // 草稿（僅管理員）
  review, // 送審中（僅管理員）
  published, // 已發佈（唯一可被學生端取得）
  rejected, // 退回（僅管理員）
  archived; // 封存（曾發佈、現撤下；僅管理員）

  static ContentStatus fromName(String? s) => ContentStatus.values.firstWhere(
        (e) => e.name == s,
        orElse: () => ContentStatus.draft,
      );

  bool get isPublished => this == ContentStatus.published;

  String get label => switch (this) {
        ContentStatus.draft => '草稿',
        ContentStatus.review => '送審中',
        ContentStatus.published => '已發佈',
        ContentStatus.rejected => '已退回',
        ContentStatus.archived => '已封存',
      };
}

/// 內容溯源。
class ContentProvenance {
  final String source; // 來源說明（例：使用者親撰、公有領域、投稿轉入…）
  final String note; // 補充

  const ContentProvenance({this.source = '', this.note = ''});

  factory ContentProvenance.fromMap(Map<String, dynamic>? m) =>
      ContentProvenance(
        source: (m?['source'] as String?) ?? '',
        note: (m?['note'] as String?) ?? '',
      );

  Map<String, dynamic> toMap() => {'source': source, 'note': note};
}

/// 受管理內容的通用外殼。[payload] 為各內容型別自己的資料形狀。
///
/// Firestore 欄位名固定（rules 與工具依賴）：
/// content_id / status / version / created_at / created_by / updated_at /
/// updated_by / reviewer / reviewed_at / publisher / published_at /
/// provenance / payload / versions（歷史 Published 快照）。
class ManagedContent {
  final String contentId; // stable id（不隨 Firestore doc id 改變）
  final ContentStatus status;
  final int version; // 從 1 起；每次發佈 +1
  final int createdAt;
  final String createdBy;
  final int updatedAt;
  final String updatedBy;
  final String reviewer;
  final int reviewedAt;
  final String publisher;
  final int publishedAt;
  final ContentProvenance provenance;
  final Map<String, dynamic> payload;

  const ManagedContent({
    required this.contentId,
    required this.status,
    required this.version,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
    this.reviewer = '',
    this.reviewedAt = 0,
    this.publisher = '',
    this.publishedAt = 0,
    this.provenance = const ContentProvenance(),
    this.payload = const {},
  });

  bool get isPublished => status.isPublished;

  factory ManagedContent.fromMap(String docId, Map<String, dynamic> m) =>
      ManagedContent(
        contentId: (m['content_id'] as String?) ?? docId,
        status: ContentStatus.fromName(m['status'] as String?),
        version: (m['version'] as int?) ?? 1,
        createdAt: (m['created_at'] as int?) ?? 0,
        createdBy: (m['created_by'] as String?) ?? '',
        updatedAt: (m['updated_at'] as int?) ?? 0,
        updatedBy: (m['updated_by'] as String?) ?? '',
        reviewer: (m['reviewer'] as String?) ?? '',
        reviewedAt: (m['reviewed_at'] as int?) ?? 0,
        publisher: (m['publisher'] as String?) ?? '',
        publishedAt: (m['published_at'] as int?) ?? 0,
        provenance:
            ContentProvenance.fromMap((m['provenance'] as Map?)?.cast()),
        payload: ((m['payload'] as Map?)?.cast<String, dynamic>()) ?? const {},
      );

  Map<String, dynamic> toMap() => {
        'content_id': contentId,
        'status': status.name,
        'version': version,
        'created_at': createdAt,
        'created_by': createdBy,
        'updated_at': updatedAt,
        'updated_by': updatedBy,
        'reviewer': reviewer,
        'reviewed_at': reviewedAt,
        'publisher': publisher,
        'published_at': publishedAt,
        'provenance': provenance.toMap(),
        'payload': payload,
      };
}

/// Q&A 回答引用的內容依據（source content ids + versions）——回答保存它，
/// 前台可取得「回答依據」。retrieval 只能用 Published approved 內容。
class AnswerSource {
  final String contentId;
  final int version;
  final String kind; // 例：'question'、'annotation'、'knowledge'

  const AnswerSource(
      {required this.contentId, required this.version, this.kind = ''});

  factory AnswerSource.fromMap(Map<String, dynamic> m) => AnswerSource(
        contentId: (m['content_id'] as String?) ?? '',
        version: (m['version'] as int?) ?? 0,
        kind: (m['kind'] as String?) ?? '',
      );

  Map<String, dynamic> toMap() =>
      {'content_id': contentId, 'version': version, 'kind': kind};
}
