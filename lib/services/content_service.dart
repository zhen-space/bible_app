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

  Future<void> saveBook(int bookId, Map<String, dynamic> data) =>
      _col.doc('book_$bookId').set(data);

  Future<void> saveChapter(
          int bookId, int chapter, Map<String, dynamic> data) =>
      _col.doc('chapter_${bookId}_$chapter').set(data);

  Future<void> saveVerse(
          int bookId, int chapter, int verse, Map<String, dynamic> data) =>
      _col.doc('verse_${bookId}_${chapter}_$verse').set(data);

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
