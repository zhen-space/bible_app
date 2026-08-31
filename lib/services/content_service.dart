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

  /// 一次抓全部內容 doc（內容量小，App 啟動抓一次即可）。
  Future<Map<String, Map<String, dynamic>>> fetchAll() async {
    final snap = await _col.get();
    return {for (final d in snap.docs) d.id: d.data()};
  }

  /// 版本化存檔：更新前把「舊內容」快照推進 `versions`（含編輯時間），
  /// 並蓋上 `updated_at`。讀者端顯示更新時間；歷史版本留在雲端可回溯。
  Future<void> _setVersioned(
      DocumentReference<Map<String, dynamic>> doc,
      Map<String, dynamic> data) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await doc.get();
    final payload = {...data, 'updated_at': now};
    if (existing.exists) {
      final old = Map<String, dynamic>.from(existing.data()!)
        ..remove('versions'); // 快照不含歷史，避免巢狀膨脹
      payload['versions'] = FieldValue.arrayUnion([
        {...old, 'edited_at': now}
      ]);
      await doc.update(payload);
    } else {
      await doc.set(payload);
    }
  }

  Future<void> saveBook(int bookId, Map<String, dynamic> data) =>
      _setVersioned(_col.doc('book_$bookId'), data);

  Future<void> saveChapter(
          int bookId, int chapter, Map<String, dynamic> data) =>
      _setVersioned(_col.doc('chapter_${bookId}_$chapter'), data);

  Future<void> saveVerse(
          int bookId, int chapter, int verse, Map<String, dynamic> data) =>
      _setVersioned(_col.doc('verse_${bookId}_${chapter}_$verse'), data);

  // ---- 知識架構（時間軸/人物/平行/預表）----
  //
  // 存成單一 doc `knowledge/data`（4 個陣列），後台編輯即讀改寫整份，
  // 讀經端「雲端優先、asset 為底」。內容一律由管理者（使用者本人）撰寫。

  DocumentReference<Map<String, dynamic>> get _knowledgeDoc =>
      _fs.collection('knowledge').doc('data');

  /// 讀雲端知識資料（不存在回 null，讀經端就退回 asset）。
  Future<Map<String, dynamic>?> fetchKnowledge() async {
    final d = await _knowledgeDoc.get();
    return d.exists ? d.data() : null;
  }

  /// 後台：寫回整份知識資料。
  Future<void> saveKnowledge(Map<String, dynamic> data) =>
      _knowledgeDoc.set(data);

  // ---- 每日經文（官方，管理者發佈）----
  //
  // Firestore `daily_verses` collection，doc id = 'YYYY-MM-DD'，
  // 欄位 `{book_id, chapter, verse, published}`。**只有 published==true 才算數。**
  // 讀經端只讀不寫；發佈由後台（管理者）處理。內容＝管理者的編輯選擇。

  CollectionReference<Map<String, dynamic>> get _dailyVerses =>
      _fs.collection('daily_verses');

  /// 讀經端：取某日（YYYY-MM-DD）的官方每日經文。未發佈或不存在回 null。
  Future<Map<String, dynamic>?> fetchPublishedDailyVerse(String ymd) async {
    final d = await _dailyVerses.doc(ymd).get();
    if (!d.exists) return null;
    final m = d.data()!;
    if (m['published'] != true) return null;
    return m;
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

  /// 管理者：通過（寫入公開集合並標記）。
  Future<void> approveSubmission(PublicSubmission s) async {
    await _publicNotes.add({
      'author': s.author,
      'book_id': s.bookId,
      'chapter': s.chapter,
      'verse': s.verse,
      'loc': '${s.bookId}_${s.chapter}',
      'content': s.content,
      'approved_at': DateTime.now().millisecondsSinceEpoch,
    });
    await _submissions.doc(s.id).update({'status': 'approved'});
  }

  /// 管理者：退回。
  Future<void> rejectSubmission(String id) =>
      _submissions.doc(id).update({'status': 'rejected'});

  /// 讀經端：某章已通過的公開註解（verse → 多則）。所有人可讀。
  Future<Map<int, List<PublicNote>>> approvedNotes(
      int bookId, int chapter) async {
    final snap =
        await _publicNotes.where('loc', isEqualTo: '${bookId}_$chapter').get();
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
