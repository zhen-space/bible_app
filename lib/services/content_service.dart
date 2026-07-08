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
}
