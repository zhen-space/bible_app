import 'package:cloud_firestore/cloud_firestore.dart';

/// 註解內容的雲端層（管理後台寫入、所有讀者讀取）。
///
/// Firestore `annotations` collection，doc id：
/// - `book_{書卷id}`：整卷導讀＋統整
/// - `chapter_{書卷id}_{章}`：章導讀＋章重點
/// - `verse_{書卷id}_{章}_{節}`：節註解
/// 資料形狀與 assets/annotations/annotations.json 的對應區塊一致，
/// 讀經端以「雲端優先、asset 為底」合併顯示。
/// 內容文字一律由管理者（使用者本人）在 App 內撰寫。
class ContentService {
  FirebaseFirestore get _fs => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _fs.collection('annotations');

  /// 一次抓全部內容 doc（管理端用；含未發佈）。
  Future<Map<String, Map<String, dynamic>>> fetchAll() async {
    final snap = await _col.get();
    return {for (final d in snap.docs) d.id: d.data()};
  }

  /// **學生端專用：只抓 Published 內容。** 未標記 status=='published' 的 legacy／
  /// 草稿一律不回（fail-closed）。以單一欄位查詢，免複合索引。
  Future<Map<String, Map<String, dynamic>>> fetchAllPublished() async {
    final snap = await _col.where('status', isEqualTo: 'published').get();
    return {for (final d in snap.docs) d.id: d.data()};
  }

  /// 版本化存檔（**直接發佈**：管理員本人親撰內容，寫入 published mirror）。
  /// 更新前把「舊內容」快照推進 `versions`，並蓋上 status='published' + version+1 +
  /// published_at/publisher/updated_at，讓文件成為合法的 Published mirror doc
  /// （#8 rules 依 `status=='published'` 放行公開讀；缺 status 者一律 fail-closed）。
  /// 需要 Draft→Review→Published 分階段時改用 ContentWorkflowService。
  Future<void> _setVersioned(
      DocumentReference<Map<String, dynamic>> doc,
      String contentId,
      String contentType,
      Map<String, dynamic> data,
      {String publisher = '', String provenanceSource = '管理員親撰'}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await doc.get();
    final prevVersion = (existing.data()?['version'] as int?) ?? 0;
    final payload = <String, dynamic>{
      ...data,
      'content_id': contentId,
      'content_type': contentType,
      'status': 'published',
      'version': prevVersion + 1,
      'updated_at': now,
      'updated_by': publisher,
      'published_by': publisher,
      'published_at': now,
      'provenance': {'source': provenanceSource, 'note': ''},
    };
    if (existing.exists) {
      payload['created_at'] = existing.data()?['created_at'] ?? now;
      payload['created_by'] = existing.data()?['created_by'] ?? publisher;
      final old = Map<String, dynamic>.from(existing.data()!)
        ..remove('versions'); // 快照不含歷史，避免巢狀膨脹
      payload['versions'] = FieldValue.arrayUnion([
        {...old, 'edited_at': now}
      ]);
      await doc.update(payload);
    } else {
      payload['created_at'] = now;
      payload['created_by'] = publisher;
      await doc.set(payload);
    }
  }

  Future<void> saveBook(int bookId, Map<String, dynamic> data,
          {String publisher = ''}) =>
      _setVersioned(
          _col.doc('book_$bookId'), 'book_$bookId', 'book_guide', data,
          publisher: publisher);

  Future<void> saveChapter(int bookId, int chapter, Map<String, dynamic> data,
          {String publisher = ''}) =>
      _setVersioned(_col.doc('chapter_${bookId}_$chapter'),
          'chapter_${bookId}_$chapter', 'chapter_guide', data,
          publisher: publisher);

  Future<void> saveVerse(
          int bookId, int chapter, int verse, Map<String, dynamic> data,
          {String publisher = ''}) =>
      _setVersioned(_col.doc('verse_${bookId}_${chapter}_$verse'),
          'verse_${bookId}_${chapter}_$verse', 'verse_commentary', data,
          publisher: publisher);

  // ---- 知識架構（時間軸/人物/平行/預表）----
  //
  // 存成單一 doc `knowledge/data`（4 個陣列），後台編輯即讀改寫整份，
  // 讀經端「雲端優先、asset 為底」。內容一律由管理者（使用者本人）撰寫。

  DocumentReference<Map<String, dynamic>> get _knowledgeDoc =>
      _fs.collection('knowledge').doc('data');

  /// 讀雲端知識資料（管理端；含未發佈）。
  Future<Map<String, dynamic>?> fetchKnowledge() async {
    final d = await _knowledgeDoc.get();
    return d.exists ? d.data() : null;
  }

  /// **學生端專用：只在 knowledge/data 為 Published 時回傳。** 否則 null（fail-closed）。
  Future<Map<String, dynamic>?> fetchPublishedKnowledge() async {
    final d = await _knowledgeDoc.get();
    if (!d.exists) return null;
    final m = d.data()!;
    if (m['status'] != 'published') return null;
    return m;
  }

  /// 後台：寫回整份知識資料（直接發佈；stamp Published mirror meta）。
  Future<void> saveKnowledge(Map<String, dynamic> data,
      {String publisher = ''}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await _knowledgeDoc.get();
    final prevVersion = (existing.data()?['version'] as int?) ?? 0;
    await _knowledgeDoc.set({
      ...data,
      'content_id': 'knowledge_data',
      'content_type': 'knowledge',
      'status': 'published',
      'version': prevVersion + 1,
      'created_at': existing.data()?['created_at'] ?? now,
      'created_by': existing.data()?['created_by'] ?? publisher,
      'updated_at': now,
      'updated_by': publisher,
      'published_by': publisher,
      'published_at': now,
      'provenance': {'source': '管理員親撰', 'note': ''},
    });
  }

  // ---- 每日經文（官方，管理者發佈）----
  //
  // Firestore `daily_verses` collection，doc id = 'YYYY-MM-DD'，
  // 欄位 `{book_id, chapter, verse, published}`。**只有 published==true 才算數。**
  // 讀經端只讀不寫；發佈由後台（管理者）處理。內容＝管理者的編輯選擇。

  CollectionReference<Map<String, dynamic>> get _dailyVerses =>
      _fs.collection('daily_verses');

  /// 讀經端：取某日（YYYY-MM-DD）的官方每日經文。**只回 status=='published'**；
  /// 未發佈或不存在回 null（fail-closed，前端顯示「今日尚無經文」，不得 fallback）。
  /// （managed collections 經唯讀 audit 確認為空，故不再相容 legacy published==true。）
  Future<Map<String, dynamic>?> fetchPublishedDailyVerse(String ymd) async {
    final d = await _dailyVerses.doc(ymd).get();
    if (!d.exists) return null;
    final m = d.data()!;
    if (m['status'] != 'published') return null;
    return m;
  }

  /// 管理者：發佈某日的官方每日經文（直接發佈；stamp managed envelope）。
  /// 學生端只讀 status=='published'（見 fetchPublishedDailyVerse）。
  Future<void> publishDailyVerse(
    String ymd, {
    required int bookId,
    required int chapter,
    required int verse,
    String publisher = '',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final ref = _dailyVerses.doc(ymd);
    final existing = await ref.get();
    final prevVersion = (existing.data()?['version'] as int?) ?? 0;
    await ref.set({
      'content_id': 'daily_$ymd',
      'content_type': 'daily_verse',
      'date': ymd,
      'book_id': bookId,
      'chapter': chapter,
      'verse': verse,
      'status': 'published',
      'version': prevVersion + 1,
      'created_at': existing.data()?['created_at'] ?? now,
      'created_by': existing.data()?['created_by'] ?? publisher,
      'updated_at': now,
      'updated_by': publisher,
      'published_by': publisher,
      'published_at': now,
      'provenance': {'source': '管理員發佈', 'note': ''},
    });
  }

  /// 管理者：撤下某日每日經文（archive；學生端立即讀不到）。
  Future<void> archiveDailyVerse(String ymd, {String publisher = ''}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final ref = _dailyVerses.doc(ymd);
    if ((await ref.get()).exists) {
      await ref.update({
        'status': 'archived',
        'archived_at': now,
        'updated_at': now,
        'updated_by': publisher,
      });
    }
  }

  // ---- 公開註解（使用者投稿 → 管理者審核）----
  //
  // `submissions`：待審／已審的投稿（只有作者本人與管理者可讀）。
  // `public_notes`：審核通過後的公開註解（所有人可讀），審核時由管理者寫入。
  // 兩者用 loc = '書卷id_章' 便於單欄位查詢（免 Firestore 複合索引）。

  CollectionReference<Map<String, dynamic>> get _submissions =>
      _fs.collection('submissions');
  CollectionReference<Map<String, dynamic>> get _publicNotes =>
      _fs.collection('public_notes');

  /// 使用者投稿一則公開註解（進待審）。
  Future<void> submitPublicNote({
    required String uid,
    required String author,
    required int bookId,
    required int chapter,
    required int verse,
    required String content,
  }) {
    return _submissions.add({
      'uid': uid,
      'author': author,
      'book_id': bookId,
      'chapter': chapter,
      'verse': verse,
      'loc': '${bookId}_$chapter',
      'content': content,
      'status': 'pending',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 管理者：取全部待審投稿。
  Future<List<PublicSubmission>> pendingSubmissions() async {
    final snap =
        await _submissions.where('status', isEqualTo: 'pending').get();
    final list = snap.docs
        .map((d) => PublicSubmission.fromDoc(d.id, d.data()))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  /// 管理者：通過（寫入公開集合並標記）。寫入時 stamp status='published' 等
  /// Published mirror meta，rules 才會放行公開讀（#8）；溯源記為「使用者投稿」。
  Future<void> approveSubmission(PublicSubmission s,
      {String publisher = ''}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _publicNotes.add({
      'author': s.author,
      'book_id': s.bookId,
      'chapter': s.chapter,
      'verse': s.verse,
      'loc': '${s.bookId}_${s.chapter}',
      'content': s.content,
      'approved_at': now,
      'content_id': 'public_note_${s.id}',
      'content_type': 'public_note',
      'status': 'published',
      'version': 1,
      'created_at': now,
      'created_by': s.author,
      'updated_at': now,
      'updated_by': publisher,
      'reviewed_by': publisher,
      'reviewed_at': now,
      'published_by': publisher,
      'published_at': now,
      'provenance': {'source': '使用者投稿', 'note': 'submission:${s.id}'},
    });
    await _submissions.doc(s.id).update({'status': 'approved'});
  }

  /// 管理者：退回。
  Future<void> rejectSubmission(String id) =>
      _submissions.doc(id).update({'status': 'rejected'});

  /// 讀經端：某章已通過的公開註解（verse → 多則）。所有人可讀。
  Future<Map<int, List<PublicNote>>> approvedNotes(
      int bookId, int chapter) async {
    // #8：只讀 Published。loc+status 複合查詢需 composite index（見
    // firestore.indexes.json），使 rules 可證明查詢只回 Published 文件。
    final snap = await _publicNotes
        .where('loc', isEqualTo: '${bookId}_$chapter')
        .where('status', isEqualTo: 'published')
        .get();
    final out = <int, List<PublicNote>>{};
    for (final d in snap.docs) {
      final m = d.data();
      final v = m['verse'] as int;
      (out[v] ??= []).add(
          PublicNote(author: m['author'] as String? ?? '', content: m['content'] as String));
    }
    return out;
  }
}

/// 一則待審投稿。
class PublicSubmission {
  final String id;
  final String author;
  final int bookId;
  final int chapter;
  final int verse;
  final String content;
  final int createdAt;

  const PublicSubmission({
    required this.id,
    required this.author,
    required this.bookId,
    required this.chapter,
    required this.verse,
    required this.content,
    required this.createdAt,
  });

  factory PublicSubmission.fromDoc(String id, Map<String, dynamic> m) =>
      PublicSubmission(
        id: id,
        author: m['author'] as String? ?? '',
        bookId: m['book_id'] as int,
        chapter: m['chapter'] as int,
        verse: m['verse'] as int,
        content: m['content'] as String? ?? '',
        createdAt: m['created_at'] as int? ?? 0,
      );
}

/// 一則已通過的公開註解。
class PublicNote {
  final String author;
  final String content;

  const PublicNote({required this.author, required this.content});
}
