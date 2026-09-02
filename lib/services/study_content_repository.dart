import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/church.dart';
import '../models/study_content.dart';
import 'content_workflow_service.dart';

/// Study Content 的正式資料存取層。**下一輪 Student UI 直接依賴這個 contract。**
///
/// 兩個責任分明：
/// 1. **Student 讀取**：每個查詢都**主動**帶 `status==published && visibility==student`。
///    Firestore rules 是安全邊界、不是 query filter；即使 by-id 也不得取得 internal。
///    **絕對禁止 fallback knowledge/data**——沒有 student-visible 就回空，不回 legacy。
/// 2. **Admin workflow**：包裝既有 [ContentWorkflowService]（單一 workflow engine），
///    以 `study_content`/`study_topics` 兩個型別＋visibility＋versions 子集合運作。
class StudyContentRepository {
  StudyContentRepository(this._fs, this._workflow);
  final FirebaseFirestore _fs;
  final ContentWorkflowService _workflow;

  static const contentType = 'study_content';
  static const topicType = 'study_topics';

  CollectionReference<Map<String, dynamic>> get _content =>
      _fs.collection(contentType);
  CollectionReference<Map<String, dynamic>> get _topics =>
      _fs.collection(topicType);

  // ---- Student 讀取（published + student，硬性；無 legacy fallback）----

  /// 兩個條件缺一不可，寫進查詢本身（rules 再擋一次）。
  Query<Map<String, dynamic>> _studentQuery() => _content
      .where('status', isEqualTo: ContentStatus.published.name)
      .where('visibility', isEqualTo: Visibility.student.name);

  Future<List<StudyContentItem>> fetchStudentStudyContent() async {
    final s = await _studentQuery().get();
    return _mapVisibleContent(s.docs);
  }

  Future<StudyContentItem?> fetchStudentStudyContentById(
      String contentId) async {
    final d = await _content.doc(contentId).get();
    if (!d.exists) return null;
    final item = StudyContentItem.fromDoc(d.id, d.data()!);
    // 即使知道 id，也只在 published+student 時回傳（其餘 fail-closed）。
    return item.isStudentVisible ? item : null;
  }

  Future<List<StudyContentItem>> fetchStudentStudyContentByType(
      StudyContentType type) async {
    final s =
        await _studentQuery().where('content_type', isEqualTo: type.wire).get();
    return _mapVisibleContent(s.docs);
  }

  Future<List<StudyContentItem>> fetchStudentStudyContentByTopic(
      String topicId) async {
    final s = await _studentQuery()
        .where('topic_ids', arrayContains: topicId)
        .get();
    return _mapVisibleContent(s.docs);
  }

  Future<List<StudyTopic>> fetchStudentTopics() async {
    final s = await _topics
        .where('status', isEqualTo: ContentStatus.published.name)
        .where('visibility', isEqualTo: Visibility.student.name)
        .get();
    final list = [
      for (final d in s.docs)
        StudyTopic.fromDoc(d.id, d.data())
    ].where((t) => t.isStudentVisible).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  List<StudyContentItem> _mapVisibleContent(
          List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) =>
      [for (final d in docs) StudyContentItem.fromDoc(d.id, d.data())]
          // 防禦性：查詢已過濾，這裡再確認一次 domain 條件（fail-closed）。
          .where((i) => i.isStudentVisible)
          .toList();

  // ==================================================================
  // Church/Teacher R1：**Authorized Universe**（audience 授權；正式 Student authority）
  // ==================================================================
  // 每個查詢自帶授權述詞；rules 逐 doc 再驗。universe = public ∪ my-church；
  // byType/byTopic/search 一律在**已授權 universe** 上 client 端 narrow
  // （§12：authorization-first，never fetch-all-then-hide）。

  static const _pub = 'published';

  Query<Map<String, dynamic>> _pubQuery(
          CollectionReference<Map<String, dynamic>> col) =>
      col
          .where('status', isEqualTo: _pub)
          .where('audience', isEqualTo: Audience.public.name);

  Query<Map<String, dynamic>> _churchQuery(
          CollectionReference<Map<String, dynamic>> col, String churchId) =>
      col
          .where('status', isEqualTo: _pub)
          .where('audience', isEqualTo: Audience.church.name)
          .where('allowed_church_ids', arrayContains: churchId);

  /// 目前 User 有權讀的 study content universe（public ∪ active-church）。
  Future<List<StudyContentItem>> fetchAuthorizedStudyContent(
      StudentAuth auth) async {
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    docs.addAll((await _pubQuery(_content).get()).docs);
    if (auth.hasChurch) {
      docs.addAll(
          (await _churchQuery(_content, auth.activeChurchId!).get()).docs);
    }
    final seen = <String>{};
    final out = <StudyContentItem>[];
    for (final d in docs) {
      if (!seen.add(d.id)) continue;
      final it = StudyContentItem.fromDoc(d.id, d.data());
      if (it.authorizedFor(auth.activeChurchId)) out.add(it); // 防禦性再驗
    }
    return out;
  }

  /// by-id：即使知道 id，也只在 audience 授權通過時回傳（fail-closed）。
  Future<StudyContentItem?> fetchAuthorizedStudyContentById(
      String contentId, StudentAuth auth) async {
    final d = await _content.doc(contentId).get();
    if (!d.exists) return null;
    final it = StudyContentItem.fromDoc(d.id, d.data()!);
    return it.authorizedFor(auth.activeChurchId) ? it : null;
  }

  /// byType/byTopic：在**已授權 universe** 上 narrow（不另發未授權 query）。
  Future<List<StudyContentItem>> fetchAuthorizedByType(
          StudyContentType type, StudentAuth auth) async =>
      (await fetchAuthorizedStudyContent(auth))
          .where((i) => i.contentType == type)
          .toList();

  Future<List<StudyContentItem>> fetchAuthorizedByTopic(
          String topicId, StudentAuth auth) async =>
      (await fetchAuthorizedStudyContent(auth))
          .where((i) => i.topicIds.contains(topicId))
          .toList();

  /// 授權主題（Topic Option A：Topic 自帶 audience）。
  Future<List<StudyTopic>> fetchAuthorizedTopics(StudentAuth auth) async {
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    docs.addAll((await _pubQuery(_topics).get()).docs);
    if (auth.hasChurch) {
      docs.addAll(
          (await _churchQuery(_topics, auth.activeChurchId!).get()).docs);
    }
    final seen = <String>{};
    final out = <StudyTopic>[];
    for (final d in docs) {
      if (!seen.add(d.id)) continue;
      final t = StudyTopic.fromDoc(d.id, d.data());
      if (t.authorizedFor(auth.activeChurchId)) out.add(t);
    }
    out.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return out;
  }

  /// 老師專區 teaching（＝study content，掛某 chapter）：授權 universe 上 narrow。
  Future<List<StudyContentItem>> fetchAuthorizedTeachings(
          String chapterId, StudentAuth auth) async =>
      (await fetchAuthorizedStudyContent(auth))
          .where((i) => i.teacherChapterId == chapterId)
          .toList();

  // ---- Admin workflow（包裝既有 ContentWorkflowService；不另造 engine）----

  /// 新建／編輯草稿。新建預設 status=draft、visibility=internal（fail-closed 起點）。
  Future<void> saveContentDraft(
    String contentId, {
    required StudyContentType type,
    required Map<String, dynamic> payload,
    required String editorEmail,
    Visibility visibility = Visibility.internal,
    ContentProvenance provenance = const ContentProvenance(),
  }) =>
      _workflow.saveDraft(
        contentType,
        contentId,
        contentType: type.wire,
        payload: payload,
        editorEmail: editorEmail,
        provenance: provenance,
        visibility: visibility,
      );

  Future<void> submitContentForReview(String contentId, String editorEmail) =>
      _workflow.submitForReview(contentType, contentId, editorEmail);

  Future<void> rejectContent(String contentId, String reviewerEmail) =>
      _workflow.reject(contentType, contentId, reviewerEmail);

  /// 發佈（含 visibility）；舊版快照寫入 versions 子集合（admin-only）。
  Future<void> publishContent(String contentId, String publisherEmail) =>
      _workflow.approveAndPublish(contentType, contentId,
          publisherEmail: publisherEmail, snapshotToSubcollection: true);

  Future<void> archiveContent(String contentId, String publisherEmail) =>
      _workflow.archive(contentType, contentId, publisherEmail);

  /// 「編輯已發佈內容」／「改 visibility」的**唯一**合法路徑：從 Published 建新草稿。
  /// migration review 的「建立 Student Review Draft」也走這裡（同一機制）。
  Future<void> createContentDraftFromPublished(
          String contentId, String editorEmail) =>
      _workflow.createDraftFromPublished(contentType, contentId,
          editorEmail: editorEmail);

  // Topic workflow（同一 engine、獨立型別）。
  Future<void> saveTopicDraft(
    String topicId, {
    required Map<String, dynamic> payload,
    required String editorEmail,
    Visibility visibility = Visibility.internal,
    ContentProvenance provenance = const ContentProvenance(),
  }) =>
      _workflow.saveDraft(
        topicType,
        topicId,
        contentType: 'study_topic',
        payload: payload,
        editorEmail: editorEmail,
        provenance: provenance,
        visibility: visibility,
      );

  Future<void> submitTopicForReview(String topicId, String editorEmail) =>
      _workflow.submitForReview(topicType, topicId, editorEmail);

  Future<void> rejectTopic(String topicId, String reviewerEmail) =>
      _workflow.reject(topicType, topicId, reviewerEmail);

  Future<void> publishTopic(String topicId, String publisherEmail) =>
      _workflow.approveAndPublish(topicType, topicId,
          publisherEmail: publisherEmail, snapshotToSubcollection: true);

  Future<void> archiveTopic(String topicId, String publisherEmail) =>
      _workflow.archive(topicType, topicId, publisherEmail);

  Future<void> createTopicDraftFromPublished(
          String topicId, String editorEmail) =>
      _workflow.createDraftFromPublished(topicType, topicId,
          editorEmail: editorEmail);

  // ---- Admin 讀取（管理端；含未發佈；rules 已限管理員）----

  StudyContentItem _itemFromDoc(
          QueryDocumentSnapshot<Map<String, dynamic>> d) =>
      StudyContentItem.fromDoc(d.id, d.data());

  /// 後台內容清單：union workspace（編輯真相）＋published mirror（migrated-only 項目
  /// 可能只存在於此）。同 id 以 workspace 為準，另標記是否有 live published。
  Future<List<AdminStudyRow>> adminListContent() async {
    final ws = await _fs.collection('${contentType}_workspace').get();
    final pub = await _content.get();
    final byId = <String, StudyContentItem>{};
    final published = <String, StudyContentItem>{};
    for (final d in pub.docs) {
      published[d.id] = _itemFromDoc(d);
    }
    for (final d in ws.docs) {
      byId[d.id] = _itemFromDoc(d);
    }
    final ids = {...byId.keys, ...published.keys};
    final rows = [
      for (final id in ids)
        AdminStudyRow(
          editorial: byId[id] ?? published[id]!,
          publishedLive: published[id],
        )
    ]..sort((a, b) => b.editorial.updatedAt.compareTo(a.editorial.updatedAt));
    return rows;
  }

  Future<StudyContentItem?> adminGetContentWorkspace(String id) async {
    final c = await _workflow.getWorkspace(contentType, id);
    return c == null ? null : StudyContentItem.fromManaged(c);
  }

  Future<StudyContentItem?> adminGetContentPublished(String id) async {
    final c = await _workflow.getPublished(contentType, id);
    return c == null ? null : StudyContentItem.fromManaged(c);
  }

  /// 唯讀版本歷史（published mirror 的 versions 子集合）。
  Future<List<Map<String, dynamic>>> adminContentVersions(String id) async {
    final s = await _content.doc(id).collection('versions').get();
    final list = [for (final d in s.docs) {...d.data(), '_vid': d.id}];
    list.sort((a, b) =>
        ((b['version'] as int?) ?? 0).compareTo((a['version'] as int?) ?? 0));
    return list;
  }

  /// Q&A 回答依據 picker 專用：**只回 status==published 的 study content**
  /// （Draft/Review/Rejected/Archived 不得成為 source）。含 internal（UI 標示 visibility）。
  Future<List<StudyContentItem>> adminListPublishedForSources() async {
    final pub = await _content
        .where('status', isEqualTo: ContentStatus.published.name)
        .get();
    return [for (final d in pub.docs) _itemFromDoc(d)];
  }

  /// 確認單一 content 目前是否為 published（Q&A 發佈時 re-validate source 用）。
  Future<bool> isPublishedNow(String id) async {
    final d = await _content.doc(id).get();
    return d.exists && d.data()?['status'] == ContentStatus.published.name;
  }

  // ---- Topic admin 讀取 ----

  Future<List<AdminTopicRow>> adminListTopics() async {
    final ws = await _fs.collection('${topicType}_workspace').get();
    final pub = await _topics.get();
    final published = <String, StudyTopic>{};
    for (final d in pub.docs) {
      published[d.id] = StudyTopic.fromDoc(d.id, d.data());
    }
    final byId = <String, StudyTopic>{};
    for (final d in ws.docs) {
      byId[d.id] = StudyTopic.fromDoc(d.id, d.data());
    }
    final ids = {...byId.keys, ...published.keys};
    final rows = [
      for (final id in ids)
        AdminTopicRow(
          editorial: byId[id] ?? published[id]!,
          publishedLive: published[id],
        )
    ]..sort((a, b) =>
        a.editorial.sortOrder.compareTo(b.editorial.sortOrder));
    return rows;
  }

  Future<StudyTopic?> adminGetTopicWorkspace(String id) async {
    final c = await _workflow.getWorkspace(topicType, id);
    return c == null ? null : StudyTopic.fromManaged(c);
  }

  Future<StudyTopic?> adminGetTopicPublished(String id) async {
    final c = await _workflow.getPublished(topicType, id);
    return c == null ? null : StudyTopic.fromManaged(c);
  }

  /// content editor 的 Topic picker：列出所有 topics（workspace 編輯真相優先）。
  Future<List<StudyTopic>> adminAllTopicsForPicker() async =>
      (await adminListTopics()).map((r) => r.editorial).toList();
}

/// 後台清單一列：editorial＝目前可編輯狀態（workspace 優先），publishedLive＝現行對外版本。
class AdminStudyRow {
  final StudyContentItem editorial;
  final StudyContentItem? publishedLive;
  const AdminStudyRow({required this.editorial, this.publishedLive});
  bool get hasPublished => publishedLive != null;
}

class AdminTopicRow {
  final StudyTopic editorial;
  final StudyTopic? publishedLive;
  const AdminTopicRow({required this.editorial, this.publishedLive});
  bool get hasPublished => publishedLive != null;
}
