/// Study Content（新版「研讀內容」）正式資料契約。
///
/// 核心不變量（見交接 spec）：
/// - **Published 與 Student-visible 完全分離**：學生可直接讀取 ⇔
///   `status == published` **且** `visibility == student`。Published+Internal 合法。
/// - **visibility 是唯一的可見度 authority**（[Visibility]，定義於 managed_content.dart）；
///   不得由 status／contentType 推導，缺失一律 fail-closed。
/// - **contentType 為 strongly-typed enum**（[StudyContentType]），未知值 safe-parse → null。
/// - 沿用既有 workflow（[ContentStatus]／ContentWorkflowService）＝單一 status truth。
///
/// 這個檔只定義**格式**與**legacy→item 的確定性映射**；不含 UI、不執行 migration。
library;

import 'dart:convert';

import 'knowledge.dart';
import 'managed_content.dart';

export 'managed_content.dart'
    show Visibility, Audience, ContentStatus, ContentProvenance, AnswerSource;

/// 對象授權判斷（Church/Teacher R1）——**受管理內容對 Student 可讀的唯一 authority**。
/// published 且（public，或 church 且 activeChurchId ∈ allowedChurchIds）。
/// internal／缺 audience／church 但無授權 → false（fail-closed）。
bool audienceAuthorized({
  required ContentStatus status,
  required Audience? audience,
  required List<String> allowedChurchIds,
  required String? activeChurchId,
}) {
  if (status != ContentStatus.published) return false;
  switch (audience) {
    case Audience.public:
      return true;
    case Audience.church:
      return activeChurchId != null &&
          allowedChurchIds.contains(activeChurchId);
    case Audience.internal:
    case null:
      return false;
  }
}

/// Study Content 型別（R1 正式允許值）。Firestore 序列化用 [wire]。
///
/// **未知／缺失 → null（fail-closed）**；正式 authority 不接受任意自由字串。
/// **不得由 contentType 推導 visibility。**
enum StudyContentType {
  parallel('parallel'), // 平行經文對照（承接 legacy parallels）
  type('type'), // 預表→應驗（承接 legacy types）
  timeline('timeline'), // 時間軸事件（承接 legacy timeline）
  person('person'), // 人物（承接 legacy people）
  topicArticle('topic_article'); // native：主題文章

  final String wire;
  const StudyContentType(this.wire);

  static StudyContentType? fromWire(String? s) {
    for (final t in StudyContentType.values) {
      if (t.wire == s) return t;
    }
    return null;
  }

  String get label => switch (this) {
        StudyContentType.parallel => '平行經文對照',
        StudyContentType.type => '預表與應驗',
        StudyContentType.timeline => '時間軸事件',
        StudyContentType.person => '人物',
        StudyContentType.topicArticle => '主題文章',
      };
}

/// 溯源來源分類。
enum StudyContentSource {
  native('native'),
  migratedLegacy('migrated_legacy');

  final String wire;
  const StudyContentSource(this.wire);

  static StudyContentSource fromWire(String? s) {
    for (final v in StudyContentSource.values) {
      if (v.wire == s) return v;
    }
    return StudyContentSource.native;
  }
}

/// 一則 Study Content。承載 workflow 外殼（透過 [toManaged]/[fromManaged] 橋接
/// [ManagedContent]）＋ 型別化 payload。
class StudyContentItem {
  final String id;
  final ContentStatus status;
  final Visibility? visibility; // required domain field；null＝fail-closed（不可見）
  final StudyContentType? contentType; // 未知 → null（fail-closed）
  final String title;
  final String body;
  final List<String> scriptureRefs;
  final List<String> topicIds;
  final List<String> tags;
  final int version;
  final ContentProvenance provenance;
  final int createdAt;
  final String createdBy;
  final int updatedAt;
  final String updatedBy;
  final int reviewedAt;
  final String reviewedBy;
  final int publishedAt;
  final String publishedBy;
  // Church/Teacher R1：對象授權（Student 唯一 authority）。
  final Audience? audience;
  final List<String> allowedChurchIds;
  // 老師專區 reference（teaching＝study content，掛到 book/chapter）。
  final String teacherBookId;
  final String teacherChapterId;

  /// 型別化結構資料（legacy 原形／native 專屬欄位），存於 payload 的 `data`。
  final Map<String, dynamic> data;

  const StudyContentItem({
    required this.id,
    required this.status,
    required this.visibility,
    required this.contentType,
    this.title = '',
    this.body = '',
    this.scriptureRefs = const [],
    this.topicIds = const [],
    this.tags = const [],
    this.version = 0,
    this.provenance = const ContentProvenance(),
    this.createdAt = 0,
    this.createdBy = '',
    this.updatedAt = 0,
    this.updatedBy = '',
    this.reviewedAt = 0,
    this.reviewedBy = '',
    this.publishedAt = 0,
    this.publishedBy = '',
    this.audience,
    this.allowedChurchIds = const [],
    this.teacherBookId = '',
    this.teacherChapterId = '',
    this.data = const {},
  });

  /// **Church/Teacher R1 授權**：對某 activeChurchId 是否可讀（唯一 Student authority）。
  bool authorizedFor(String? activeChurchId) => audienceAuthorized(
        status: status,
        audience: audience,
        allowedChurchIds: allowedChurchIds,
        activeChurchId: activeChurchId,
      );

  /// legacy（visibility 軸）——僅保留相容，不再是 Church 世界的 authority。
  bool get isStudentVisible =>
      status == ContentStatus.published && visibility == Visibility.student;

  Map<String, dynamic> get payload => {
        'title': title,
        'body': body,
        'scripture_refs': scriptureRefs,
        'topic_ids': topicIds,
        'tags': tags,
        if (teacherBookId.isNotEmpty) 'teacher_book_id': teacherBookId,
        if (teacherChapterId.isNotEmpty) 'teacher_chapter_id': teacherChapterId,
        'data': data,
      };

  /// 橋接到 workflow 外殼（供 ContentWorkflowService 讀寫）。
  ManagedContent toManaged() => ManagedContent(
        contentId: id,
        contentType: contentType?.wire ?? '',
        status: status,
        version: version,
        createdAt: createdAt,
        createdBy: createdBy,
        updatedAt: updatedAt,
        updatedBy: updatedBy,
        reviewedBy: reviewedBy,
        reviewedAt: reviewedAt,
        publishedBy: publishedBy,
        publishedAt: publishedAt,
        provenance: provenance,
        visibility: visibility,
        audience: audience,
        allowedChurchIds: allowedChurchIds,
        payload: payload,
      );

  factory StudyContentItem.fromManaged(ManagedContent c) {
    final p = c.payload;
    List<String> strs(Object? v) =>
        ((v as List?) ?? const []).map((e) => e.toString()).toList();
    return StudyContentItem(
      id: c.contentId,
      status: c.status,
      visibility: c.visibility, // 缺失 → null（fail-closed）
      contentType: StudyContentType.fromWire(c.contentType),
      title: (p['title'] as String?) ?? '',
      body: (p['body'] as String?) ?? '',
      scriptureRefs: strs(p['scripture_refs']),
      topicIds: strs(p['topic_ids']),
      tags: strs(p['tags']),
      version: c.version,
      provenance: c.provenance,
      createdAt: c.createdAt,
      createdBy: c.createdBy,
      updatedAt: c.updatedAt,
      updatedBy: c.updatedBy,
      reviewedAt: c.reviewedAt,
      reviewedBy: c.reviewedBy,
      publishedAt: c.publishedAt,
      publishedBy: c.publishedBy,
      audience: c.audience, // 缺失 → null（fail-closed）
      allowedChurchIds: c.allowedChurchIds,
      teacherBookId: (p['teacher_book_id'] as String?) ?? '',
      teacherChapterId: (p['teacher_chapter_id'] as String?) ?? '',
      data: ((p['data'] as Map?)?.cast<String, dynamic>()) ?? const {},
    );
  }

  factory StudyContentItem.fromDoc(String docId, Map<String, dynamic> m) =>
      StudyContentItem.fromManaged(
          ManagedContent.fromMap(docId, {...m, 'payload': _payloadOf(m)}));

  static const _reserved = {
    'content_id', 'content_type', 'status', 'version', 'created_at',
    'created_by', 'updated_at', 'updated_by', 'reviewed_by', 'reviewed_at',
    'published_by', 'published_at', 'archived_at', 'provenance', 'visibility',
    'versions', 'reviewer', 'publisher', //
  };
  static Map<String, dynamic> _payloadOf(Map<String, dynamic> m) => {
        for (final e in m.entries)
          if (!_reserved.contains(e.key)) e.key: e.value,
      };
}

/// 正式 Study Topic entity（雲端；取代 hard-coded lib/data/topics.dart 作為 admin source）。
/// 與 Content visibility **獨立**：Topic 為 student-visible 才會成為學生可瀏覽的主題入口。
class StudyTopic {
  final String id; // slug
  final String title;
  final String description;
  final int sortOrder;
  final ContentStatus status;
  final Visibility? visibility;
  final int version;
  final ContentProvenance provenance;
  final int createdAt;
  final String createdBy;
  final int updatedAt;
  final String updatedBy;
  final int reviewedAt;
  final String reviewedBy;
  final int publishedAt;
  final String publishedBy;
  // Church/Teacher R1（Topic 授權採 Option A：與 Study Content 對稱）。
  final Audience? audience;
  final List<String> allowedChurchIds;

  const StudyTopic({
    required this.id,
    required this.status,
    required this.visibility,
    this.title = '',
    this.description = '',
    this.sortOrder = 0,
    this.version = 0,
    this.provenance = const ContentProvenance(),
    this.createdAt = 0,
    this.createdBy = '',
    this.updatedAt = 0,
    this.updatedBy = '',
    this.reviewedAt = 0,
    this.reviewedBy = '',
    this.publishedAt = 0,
    this.publishedBy = '',
    this.audience,
    this.allowedChurchIds = const [],
  });

  /// Church/Teacher R1 授權（唯一 Student authority）。
  bool authorizedFor(String? activeChurchId) => audienceAuthorized(
        status: status,
        audience: audience,
        allowedChurchIds: allowedChurchIds,
        activeChurchId: activeChurchId,
      );

  bool get isStudentVisible =>
      status == ContentStatus.published && visibility == Visibility.student;

  Map<String, dynamic> get payload => {
        'title': title,
        'description': description,
        'sort_order': sortOrder,
      };

  ManagedContent toManaged() => ManagedContent(
        contentId: id,
        contentType: 'study_topic',
        status: status,
        version: version,
        createdAt: createdAt,
        createdBy: createdBy,
        updatedAt: updatedAt,
        updatedBy: updatedBy,
        reviewedBy: reviewedBy,
        reviewedAt: reviewedAt,
        publishedBy: publishedBy,
        publishedAt: publishedAt,
        provenance: provenance,
        visibility: visibility,
        audience: audience,
        allowedChurchIds: allowedChurchIds,
        payload: payload,
      );

  factory StudyTopic.fromManaged(ManagedContent c) => StudyTopic(
        id: c.contentId,
        status: c.status,
        visibility: c.visibility,
        audience: c.audience,
        allowedChurchIds: c.allowedChurchIds,
        title: (c.payload['title'] as String?) ?? '',
        description: (c.payload['description'] as String?) ?? '',
        sortOrder: (c.payload['sort_order'] as int?) ?? 0,
        version: c.version,
        provenance: c.provenance,
        createdAt: c.createdAt,
        createdBy: c.createdBy,
        updatedAt: c.updatedAt,
        updatedBy: c.updatedBy,
        reviewedAt: c.reviewedAt,
        reviewedBy: c.reviewedBy,
        publishedAt: c.publishedAt,
        publishedBy: c.publishedBy,
      );

  factory StudyTopic.fromDoc(String docId, Map<String, dynamic> m) =>
      StudyTopic.fromManaged(ManagedContent.fromMap(
          docId, {...m, 'payload': StudyContentItem._payloadOf(m)}));
}

/// Legacy `knowledge/data` → Study Content items 的**確定性**映射（純函式，可測）。
///
/// 規則（見 spec 12）：additive／deterministic／idempotent／collision-aware。
/// **任何 migrated item 一律 `visibility = internal`**（絕不自動 student）。
/// status：aggregate 可確認 Published → items 亦 published；否則 fail-closed → draft。
///
/// ⚠️ id 演算法（[stableId]／FNV-1a-64）必須與 `tools/migrate_knowledge.mjs` **完全一致**，
/// 兩邊同步修改，否則重跑 migration 會產生不同 id（破壞 idempotency）。
class StudyContentMigration {
  static const legacyAggregate = 'knowledge/data';

  /// FNV-1a 64-bit（over UTF-8 bytes），回 16 位 hex。Node 端需以相同演算法實作。
  static String fnv1a64(String s) {
    final mask = (BigInt.one << 64) - BigInt.one;
    var hash = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    for (final b in utf8.encode(s)) {
      hash = (hash ^ BigInt.from(b)) & mask;
      hash = (hash * prime) & mask;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  /// 確定性 id：人物沿用 legacy stable id；其餘用內容 canonical 字串的 hash。
  static String stableId(StudyContentType type, String canonical) =>
      '${type.wire}__${fnv1a64(canonical)}';

  static List<StudyContentItem> fromKnowledgeBase(
    KnowledgeBase kb, {
    required bool aggregatePublished,
  }) {
    final status =
        aggregatePublished ? ContentStatus.published : ContentStatus.draft;
    ContentProvenance prov(String category, String legacyIdentifier) =>
        ContentProvenance(
          source: StudyContentSource.migratedLegacy.wire,
          note: jsonEncode({
            'legacy_aggregate': legacyAggregate,
            'legacy_category': category,
            'legacy_identifier': legacyIdentifier,
          }),
        );
    StudyContentItem base(
            StudyContentType type, String id, ContentProvenance provenance,
            {String title = '',
            String body = '',
            List<String> refs = const [],
            Map<String, dynamic> data = const {}}) =>
        StudyContentItem(
          id: id,
          status: status,
          visibility: Visibility.internal, // ← 硬性：永遠 internal
          contentType: type,
          title: title,
          body: body,
          scriptureRefs: refs,
          version: aggregatePublished ? 1 : 0,
          provenance: provenance,
          data: data,
        );

    final items = <StudyContentItem>[];

    for (final p in kb.parallels) {
      final canonical = 'parallel|${p.title}|${p.refs.join(",")}';
      items.add(base(
        StudyContentType.parallel,
        stableId(StudyContentType.parallel, canonical),
        prov('parallels', canonical),
        title: p.title,
        refs: p.refs,
        data: p.toJson(),
      ));
    }
    for (final t in kb.types) {
      final canonical = 'type|${t.title}|${t.otRef}|${t.ntRef}';
      items.add(base(
        StudyContentType.type,
        stableId(StudyContentType.type, canonical),
        prov('types', canonical),
        title: t.title,
        body: t.note,
        refs: [
          if (t.otRef.isNotEmpty) t.otRef,
          if (t.ntRef.isNotEmpty) t.ntRef,
        ],
        data: t.toJson(),
      ));
    }
    for (final e in kb.timeline) {
      final canonical = 'timeline|${e.era}|${e.title}|${e.when}|${e.ref}';
      items.add(base(
        StudyContentType.timeline,
        stableId(StudyContentType.timeline, canonical),
        prov('timeline', canonical),
        title: e.title,
        body: e.when,
        refs: [if (e.ref.isNotEmpty) e.ref],
        data: e.toJson(),
      ));
    }
    for (final person in kb.people) {
      // 人物有 legacy stable id → 沿用；缺 id 才 fallback 內容 hash。
      final legacyId = person.id.isNotEmpty
          ? person.id
          : 'anon__${fnv1a64('person|${person.name}|${person.bio}')}';
      final id = 'person__$legacyId';
      items.add(base(
        StudyContentType.person,
        id,
        prov('people', legacyId),
        title: person.name,
        body: person.bio,
        refs: [for (final ev in person.events) ev.ref].where((r) => r.isNotEmpty).toList(),
        data: person.toJson(),
      ));
    }
    return items;
  }
}
