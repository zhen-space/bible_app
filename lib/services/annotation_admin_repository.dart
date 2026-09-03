import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/managed_content.dart';
import 'content_workflow_service.dart';

/// 後台「節註解（多版本／audience）」的管理層（Church/Teacher R1 annotation coexistence）。
///
/// **正式 annotation identity 與 verseKey 解耦**：
/// - `annotations/{annotationId}`＝一筆受管理註解（managed content），有自己的 id。
/// - `verse_key`（"book_chapter_verse"）＝scripture lookup 欄位（**非** doc id）。
/// - **同一節可有零到多筆**：public 與 church、Church A 與 Church B 各自獨立 doc，互不覆寫。
///
/// workflow 重用 [ContentWorkflowService]（單一 status truth；type=`annotations`）：
/// Draft→Review→Published→Rejected/Archived、createDraftFromPublished（改內容/改 audience 皆走新草稿）。
/// church audience 的 **trusted 發佈驗證**（allowedChurchIds 非空、皆存在且 active）在此 service 邊界。
class AnnotationAdminRepository {
  AnnotationAdminRepository(this._fs, this._workflow);
  final FirebaseFirestore _fs;
  final ContentWorkflowService _workflow;

  static const _type = 'annotations';
  static const contentType = 'verse_commentary';

  CollectionReference<Map<String, dynamic>> get _pub => _fs.collection(_type);
  CollectionReference<Map<String, dynamic>> get _ws =>
      _fs.collection('${_type}_workspace');

  /// scripture lookup key（節註解的正式節位欄位）。
  static String verseKey(int book, int chapter, int verse) =>
      '${book}_${chapter}_$verse';

  /// 產生新的 annotation id（**與 verseKey 解耦**；scope + 微秒級 unique 保證同節多筆、
  /// public/church、Church A/B 皆不 collision；id 內含節位＋scope 便於除錯）。
  static String newAnnotationId(int book, int chapter, int verse,
      Audience audience, {String? churchId}) {
    final scope =
        audience == Audience.church ? 'ch${churchId ?? 'x'}' : audience.name;
    final uniq = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 'ann_${book}_${chapter}_${verse}_${scope}_$uniq';
  }

  // ---- workflow（草稿只動 workspace；發佈才進 published mirror）----

  Future<void> saveDraft(
    String annotationId, {
    required int book,
    required int chapter,
    required int verse,
    required Map<String, dynamic> payload,
    required Audience audience,
    List<String> allowedChurchIds = const [],
    required String editorEmail,
  }) =>
      _workflow.saveDraft(
        _type,
        annotationId,
        contentType: contentType,
        payload: {...payload, 'verse_key': verseKey(book, chapter, verse)},
        editorEmail: editorEmail,
        audience: audience,
        allowedChurchIds: allowedChurchIds,
      );

  Future<void> submitForReview(String id, String editorEmail) async {
    await _assertChurchPublishable(id);
    return _workflow.submitForReview(_type, id, editorEmail);
  }

  Future<void> reject(String id, String reviewerEmail) =>
      _workflow.reject(_type, id, reviewerEmail);

  Future<void> publish(String id, String publisherEmail) async {
    await _assertChurchPublishable(id);
    // annotations 沿用 `versions` 陣列快照（與既有 ContentService.saveVerse 一致）。
    return _workflow.approveAndPublish(_type, id,
        publisherEmail: publisherEmail);
  }

  /// 「編輯已發佈註解」／「改 audience」的**唯一**合法路徑：從 Published 建新草稿。
  Future<void> createDraftFromPublished(String id, String editorEmail) =>
      _workflow.createDraftFromPublished(_type, id, editorEmail: editorEmail);

  Future<void> archive(String id, String publisherEmail) =>
      _workflow.archive(_type, id, publisherEmail);

  Future<ManagedContent?> getWorkspace(String id) =>
      _workflow.getWorkspace(_type, id);
  Future<ManagedContent?> getPublished(String id) =>
      _workflow.getPublished(_type, id);

  /// **church 發佈對象 enforcement**（trusted boundary，不靠 UI）：
  /// audience==church 時，allowedChurchIds 非空、每個都是存在且 active 的 church。
  Future<void> _assertChurchPublishable(String id) async {
    final ws = await _workflow.getWorkspace(_type, id);
    if (ws == null || ws.audience != Audience.church) return;
    final ids = ws.allowedChurchIds;
    if (ids.isEmpty) {
      throw StateError('audience=church 但 allowedChurchIds 為空，不可送審／發佈');
    }
    for (final cid in ids) {
      final c = await _fs.collection('churches').doc(cid).get();
      if (!c.exists) throw StateError('church «$cid» 不存在，不可作為發佈對象');
      if (c.data()?['active'] != true) {
        throw StateError('church «$cid» 非 active，不可作為新發佈對象');
      }
    }
  }

  // ---- Admin 讀取：某節的所有 annotation（含 legacy verseKey doc）----

  /// union：workspace（編輯真相）＋ published mirror ＋ legacy `verse_{b}_{c}_{v}` doc
  /// （migration 前無 `verse_key` 的舊公開節註解）。同 id 以 workspace 為編輯真相。
  Future<List<AnnotationAdminRow>> listForVerse(
      int book, int chapter, int verse) async {
    final key = verseKey(book, chapter, verse);
    final legacyId = 'verse_${book}_${chapter}_$verse';

    final published = <String, Map<String, dynamic>>{};
    final workspace = <String, Map<String, dynamic>>{};

    for (final d in (await _pub.where('verse_key', isEqualTo: key).get()).docs) {
      published[d.id] = d.data();
    }
    for (final d in (await _ws.where('verse_key', isEqualTo: key).get()).docs) {
      workspace[d.id] = d.data();
    }
    // legacy by-id（可能無 verse_key 欄位，不會被上面查到）。
    final lp = await _pub.doc(legacyId).get();
    if (lp.exists) published.putIfAbsent(lp.id, () => lp.data()!);
    final lw = await _ws.doc(legacyId).get();
    if (lw.exists) workspace.putIfAbsent(lw.id, () => lw.data()!);

    final ids = {...published.keys, ...workspace.keys};
    return [
      for (final id in ids)
        AnnotationAdminRow(
            id: id, published: published[id], workspace: workspace[id])
    ]..sort((a, b) => a.id.compareTo(b.id));
  }
}

/// 後台每筆註解列：editorial＝workspace 優先（無則 published）；另記是否有 live published。
class AnnotationAdminRow {
  final String id;
  final Map<String, dynamic>? published;
  final Map<String, dynamic>? workspace;
  const AnnotationAdminRow({required this.id, this.published, this.workspace});

  Map<String, dynamic> get _editorial => workspace ?? published!;
  bool get hasPublished =>
      published != null && published!['status'] == 'published';
  String get status => (_editorial['status'] as String?) ?? 'draft';
  String? get audienceName => _editorial['audience'] as String?;
  List<String> get allowedChurchIds =>
      ((_editorial['allowed_church_ids'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList();
  Map<String, dynamic> get payload => ContentWorkflowService.payloadOf(_editorial);
}
