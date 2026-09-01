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

/// 內容「可見度」維度——**與 status 完全獨立**（Published ≠ Student-visible）。
///
/// 學生端可直接讀取 ⇔ `status == published` **且** `visibility == student`。
/// 這是 Study Content 的 **required domain field**；**缺失／未知一律 fail-closed**
/// （[fromName] 回 null，呼叫端與 Firestore rules 皆視為「學生不可見」）。
/// 不得由 status 或 contentType 推導 visibility；不得新增 studentVisible/isPublic/
/// audience 等重疊欄位——visibility 是這個維度唯一的 authority。
enum Visibility {
  internal, // 僅內部；即使 Published 學生也讀不到
  student; // 對學生公開（仍需 status==published 才生效）

  /// Firestore 序列化值即 [name]（"internal"/"student"）。
  /// 未知／缺失 → null（**fail-closed**：不得預設成 student）。
  static Visibility? fromName(String? s) {
    for (final v in Visibility.values) {
      if (v.name == s) return v;
    }
    return null;
  }

  bool get isStudentVisible => this == Visibility.student;

  String get label => switch (this) {
        Visibility.internal => '內部',
        Visibility.student => '學生可見',
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
  final String contentType; // 型別：annotation/book_guide/chapter_guide/verse_commentary/knowledge/daily_verse/public_note/reading_plan
  final ContentStatus status;
  final int version; // 從 1 起；每次發佈 +1
  final int createdAt;
  final String createdBy;
  final int updatedAt;
  final String updatedBy;
  final String reviewedBy;
  final int reviewedAt;
  final String publishedBy;
  final int publishedAt;
  final int archivedAt; // 封存時間（0＝未封存）
  final ContentProvenance provenance;
  // 可見度維度（見 [Visibility]）。**null ＝此內容型別不使用 visibility**
  // （annotations/knowledge/daily_verses… 走 isPublished-only 規則），
  // 序列化時省略、不污染既有型別。Study Content 一律非 null。
  final Visibility? visibility;
  final Map<String, dynamic> payload;

  const ManagedContent({
    required this.contentId,
    this.contentType = '',
    required this.status,
    required this.version,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
    this.reviewedBy = '',
    this.reviewedAt = 0,
    this.publishedBy = '',
    this.publishedAt = 0,
    this.archivedAt = 0,
    this.provenance = const ContentProvenance(),
    this.visibility,
    this.payload = const {},
  });

  bool get isPublished => status.isPublished;

  factory ManagedContent.fromMap(String docId, Map<String, dynamic> m) =>
      ManagedContent(
        contentId: (m['content_id'] as String?) ?? docId,
        contentType: (m['content_type'] as String?) ?? '',
        status: ContentStatus.fromName(m['status'] as String?),
        version: (m['version'] as int?) ?? 1,
        createdAt: (m['created_at'] as int?) ?? 0,
        createdBy: (m['created_by'] as String?) ?? '',
        updatedAt: (m['updated_at'] as int?) ?? 0,
        updatedBy: (m['updated_by'] as String?) ?? '',
        // 讀取相容 legacy 舊欄名 reviewer/publisher。
        reviewedBy:
            (m['reviewed_by'] as String?) ?? (m['reviewer'] as String?) ?? '',
        reviewedAt: (m['reviewed_at'] as int?) ?? 0,
        publishedBy:
            (m['published_by'] as String?) ?? (m['publisher'] as String?) ?? '',
        publishedAt: (m['published_at'] as int?) ?? 0,
        archivedAt: (m['archived_at'] as int?) ?? 0,
        provenance:
            ContentProvenance.fromMap((m['provenance'] as Map?)?.cast()),
        visibility: Visibility.fromName(m['visibility'] as String?),
        payload: ((m['payload'] as Map?)?.cast<String, dynamic>()) ?? const {},
      );

  Map<String, dynamic> toMap() => {
        'content_id': contentId,
        'content_type': contentType,
        'status': status.name,
        'version': version,
        'created_at': createdAt,
        'created_by': createdBy,
        'updated_at': updatedAt,
        'updated_by': updatedBy,
        'reviewed_by': reviewedBy,
        'reviewed_at': reviewedAt,
        'published_by': publishedBy,
        'published_at': publishedAt,
        'archived_at': archivedAt,
        'provenance': provenance.toMap(),
        // visibility 僅在使用該維度時序列化（null 省略，維持既有型別 doc 形狀）。
        if (visibility != null) 'visibility': visibility!.name,
        'payload': payload,
      };
}

/// Q&A 回答引用的內容依據（source content ids + **immutable** versions + evidence）。
/// 回答保存它，前台可取得「回答依據」。retrieval 只能用 Published approved 內容；
/// version 為回答當下取得之 Published 版本的快照，供追溯（immutable / traceable）。
class AnswerSource {
  final String contentId;
  final int version;
  final String kind; // 'study_content'、'scripture'、'question'、'annotation'…
  final String evidence; // 顯示標題／命中片段（**建立當時的公開快照 label**，可空）
  // 建立當時的存取狀態快照：study_content 為 'student'/'internal'；scripture 為 ''。
  // **學生端據此決定可否點開，不必去讀 internal 文件即可顯示 title**（見交接 12）。
  final String access;
  // scripture source 的節位字串（kind=='scripture' 時；點了跳臨時 Reader）。
  final String ref;

  const AnswerSource(
      {required this.contentId,
      required this.version,
      this.kind = '',
      this.evidence = '',
      this.access = '',
      this.ref = ''});

  bool get isStudentOpenable =>
      kind == 'scripture' || (kind == 'study_content' && access == 'student');

  factory AnswerSource.fromMap(Map<String, dynamic> m) => AnswerSource(
        contentId: (m['content_id'] as String?) ?? '',
        version: (m['version'] as int?) ?? 0,
        kind: (m['kind'] as String?) ?? '',
        evidence: (m['evidence'] as String?) ?? '',
        access: (m['access'] as String?) ?? '',
        ref: (m['ref'] as String?) ?? '',
      );

  Map<String, dynamic> toMap() => {
        'content_id': contentId,
        'version': version,
        'kind': kind,
        'evidence': evidence,
        'access': access,
        'ref': ref,
      };
}
