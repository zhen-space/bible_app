import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/models.dart';
import 'database_service.dart';

/// 雲端同步：本地 SQLite 為主，Firestore 為備份。
///
/// 四張表（bookmarks/highlights/notes/reading_log）雙向合併，
/// 以 `created_at`/`updated_at` 做 last-write-wins。
/// 資料放在 `users/{uid}/...`，Firestore 規則限本人存取。
///
/// v1 限制：不同步「刪除」（刪掉的書籤若雲端還有，下次同步會回來）。
/// 之後要做刪除同步需加 tombstone 欄位。
class SyncService {
  final DatabaseService db;

  SyncService(this.db);

  FirebaseFirestore get _fs => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid, String name) =>
      _fs.collection('users').doc(uid).collection(name);

  String _refId(Map<String, dynamic> m) =>
      'b${m['book_id']}_c${m['chapter']}_v${m['verse'] ?? 0}';

  /// 完整雙向同步，回傳訊息（顯示在 UI）。
  Future<String> syncAll(String uid) async {
    var uploaded = 0;
    var downloaded = 0;

    // ---- 下載（雲端 → 本地，LWW 合併）----
    final cloudBookmarks = await _col(uid, 'bookmarks').get();
    for (final d in cloudBookmarks.docs) {
      final m = d.data();
      await db.upsertBookmark(m['book_id'] as int, m['chapter'] as int,
          m['verse'] as int, m['created_at'] as int);
      downloaded++;
    }
    final cloudHighlights = await _col(uid, 'highlights').get();
    for (final d in cloudHighlights.docs) {
      final m = d.data();
      await db.upsertHighlight(m['book_id'] as int, m['chapter'] as int,
          m['verse'] as int, m['color'] as int, m['created_at'] as int);
      downloaded++;
    }
    final cloudNotes = await _col(uid, 'notes').get();
    for (final d in cloudNotes.docs) {
      final m = d.data();
      await db.upsertNote(
          m['book_id'] as int,
          m['chapter'] as int,
          m['verse'] as int,
          m['content'] as String,
          m['created_at'] as int,
          m['updated_at'] as int,
          tags: (m['tags'] as String?) ?? '');
      downloaded++;
    }
    final cloudLog = await _col(uid, 'reading_log').get();
    for (final d in cloudLog.docs) {
      final m = d.data();
      await db.upsertReadingLog(
          m['book_id'] as int, m['chapter'] as int, m['read_at'] as int);
      downloaded++;
    }
    final cloudPlans = await _col(uid, 'plan_progress').get();
    for (final d in cloudPlans.docs) {
      final m = d.data();
      await db.upsertPlanProgress(
          m['plan_id'] as String, m['day'] as int, m['done_at'] as int);
      downloaded++;
    }
    // 證道筆記：以雲端 doc id 對應本地（較新的 updated_at 為準）
    final cloudSermons = await _col(uid, 'sermon_notes').get();
    final localSermons = await db.getSermonNotes();
    for (final d in cloudSermons.docs) {
      final m = d.data();
      final localMatch = localSermons
          .where((s) => s.createdAt == (m['created_at'] as int))
          .firstOrNull;
      if (localMatch == null ||
          (m['updated_at'] as int) > localMatch.updatedAt) {
        await db.saveSermonNote(SermonNote.fromMap({
          ...m,
          if (localMatch != null) 'id': localMatch.id,
        }));
        downloaded++;
      }
    }

    // ---- 上傳（本地 → 雲端，batch 寫入）----
    var batch = _fs.batch();
    var pending = 0;
    Future<void> commitIfFull() async {
      if (pending >= 400) {
        // Firestore batch 上限 500
        await batch.commit();
        batch = _fs.batch();
        pending = 0;
      }
    }

    for (final b in await db.getAllBookmarks()) {
      final m = b.toMap()..remove('id');
      batch.set(_col(uid, 'bookmarks').doc(_refId(m)), m);
      pending++;
      uploaded++;
      await commitIfFull();
    }
    for (final h in await db.getAllHighlights()) {
      final m = h.toMap()..remove('id');
      batch.set(_col(uid, 'highlights').doc(_refId(m)), m);
      pending++;
      uploaded++;
      await commitIfFull();
    }
    for (final n in await db.getAllNotes()) {
      final m = n.toMap()..remove('id');
      batch.set(_col(uid, 'notes').doc(_refId(m)), m);
      pending++;
      uploaded++;
      await commitIfFull();
    }
    for (final m in await db.getReadingLog()) {
      batch.set(
          _col(uid, 'reading_log')
              .doc('b${m['book_id']}_c${m['chapter']}'),
          {
            'book_id': m['book_id'],
            'chapter': m['chapter'],
            'read_at': m['read_at'],
          });
      pending++;
      uploaded++;
      await commitIfFull();
    }
    for (final s in await db.getSermonNotes()) {
      final m = s.toMap()..remove('id');
      // 用 created_at 當雲端 doc id（穩定、跨裝置一致）
      batch.set(_col(uid, 'sermon_notes').doc('s${s.createdAt}'), m);
      pending++;
      uploaded++;
      await commitIfFull();
    }
    for (final m in await db.getAllPlanProgress()) {
      batch.set(
          _col(uid, 'plan_progress')
              .doc('${m['plan_id']}_d${m['day']}'),
          {
            'plan_id': m['plan_id'],
            'day': m['day'],
            'done_at': m['done_at'],
          });
      pending++;
      uploaded++;
      await commitIfFull();
    }
    if (pending > 0) await batch.commit();

    return '已同步（上傳 $uploaded 筆、下載合併 $downloaded 筆）';
  }
}
