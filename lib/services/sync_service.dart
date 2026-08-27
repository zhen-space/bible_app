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
  /// [onStep] 回報目前進行到哪一步（顯示在狀態列，方便診斷卡在哪）。
  Future<String> syncAll(String uid, {void Function(String step)? onStep}) async {
    var uploaded = 0;
    var downloaded = 0;

    onStep?.call('同步中…讀取刪除紀錄');
    // ---- 墓碑先合併（決定哪些雲端資料已被刪、不該下載回來）----
    final cloudTombs = await _col(uid, 'tombstones').get();
    for (final d in cloudTombs.docs) {
      final m = d.data();
      await db.upsertTombstone(
          m['kind'] as String, m['ref'] as String, m['deleted_at'] as int);
    }
    // 各類刪除對照：ref → deleted_at
    final tombB = await db.getTombstoneMap('bookmark');
    final tombH = await db.getTombstoneMap('highlight');
    final tombN = await db.getTombstoneMap('note');
    final tombS = await db.getTombstoneMap('sermon');
    final tombP = await db.getTombstoneMap('prayer');
    final tombT = await db.getTombstoneMap('todo');
    final tombC = await db.getTombstoneMap('completion');
    String rref(Map<String, dynamic> m) =>
        'b${m['book_id']}_c${m['chapter']}_v${m['verse']}';

    onStep?.call('同步中…下載雲端資料');
    // ---- 下載（雲端 → 本地，LWW 合併，被刪的（墓碑較新）跳過）----
    final cloudBookmarks = await _col(uid, 'bookmarks').get();
    for (final d in cloudBookmarks.docs) {
      final m = d.data();
      final t = tombB[rref(m)];
      if (t != null && t >= (m['created_at'] as int)) continue;
      await db.upsertBookmark(m['book_id'] as int, m['chapter'] as int,
          m['verse'] as int, m['created_at'] as int);
      downloaded++;
    }
    final cloudHighlights = await _col(uid, 'highlights').get();
    for (final d in cloudHighlights.docs) {
      final m = d.data();
      final t = tombH[rref(m)];
      if (t != null && t >= (m['created_at'] as int)) continue;
      await db.upsertHighlight(m['book_id'] as int, m['chapter'] as int,
          m['verse'] as int, m['color'] as int, m['created_at'] as int);
      downloaded++;
    }
    final cloudNotes = await _col(uid, 'notes').get();
    for (final d in cloudNotes.docs) {
      final m = d.data();
      final t = tombN[rref(m)];
      if (t != null && t >= (m['updated_at'] as int)) continue;
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
    final cloudCompletions = await _col(uid, 'chapter_completions').get();
    for (final d in cloudCompletions.docs) {
      final m = d.data();
      final completedAt = m['completed_at'] as int;
      final t = tombC['b${m['book_id']}_c${m['chapter']}'];
      if (t != null && t >= completedAt) continue;
      await db.upsertChapterCompletion(
          m['book_id'] as int, m['chapter'] as int, completedAt);
      downloaded++;
    }
    // 證道筆記：以雲端 doc id 對應本地（較新的 updated_at 為準）
    final cloudSermons = await _col(uid, 'sermon_notes').get();
    final localSermons = await db.getSermonNotes();
    for (final d in cloudSermons.docs) {
      final m = d.data();
      final createdAt = m['created_at'] as int;
      final t = tombS['s$createdAt'];
      if (t != null && t >= (m['updated_at'] as int)) continue;
      final localMatch =
          localSermons.where((s) => s.createdAt == createdAt).firstOrNull;
      if (localMatch == null ||
          (m['updated_at'] as int) > localMatch.updatedAt) {
        await db.saveSermonNote(SermonNote.fromMap({
          ...m,
          if (localMatch != null) 'id': localMatch.id,
        }));
        downloaded++;
      }
    }

    // 禱告事項：以 created_at 對應本地（較新的 updated_at 為準）
    final cloudPrayers = await _col(uid, 'prayers').get();
    final localPrayers = await db.getPrayers();
    for (final d in cloudPrayers.docs) {
      final m = d.data();
      final createdAt = m['created_at'] as int;
      final t = tombP['p$createdAt'];
      if (t != null && t >= (m['updated_at'] as int)) continue;
      final localMatch =
          localPrayers.where((p) => p.createdAt == createdAt).firstOrNull;
      if (localMatch == null ||
          (m['updated_at'] as int) > localMatch.updatedAt) {
        await db.savePrayer(Prayer.fromMap({
          ...m,
          if (localMatch != null) 'id': localMatch.id,
        }));
        downloaded++;
      }
    }

    // 代辦事項：以 created_at 對應本地（較新的 updated_at 為準）
    final cloudTodos = await _col(uid, 'todos').get();
    final localTodos = await db.getTodos();
    for (final d in cloudTodos.docs) {
      final m = d.data();
      final createdAt = m['created_at'] as int;
      final t = tombT['t$createdAt'];
      if (t != null && t >= (m['updated_at'] as int)) continue;
      final localMatch =
          localTodos.where((x) => x.createdAt == createdAt).firstOrNull;
      if (localMatch == null ||
          (m['updated_at'] as int) > localMatch.updatedAt) {
        await db.saveTodo(Todo.fromMap({
          ...m,
          if (localMatch != null) 'id': localMatch.id,
        }));
        downloaded++;
      }
    }

    // 套用所有（合併後）墓碑到本地：刪掉時間不比刪除時間新的本地資料。
    // （擋掉「另一台裝置刪除、但本機還留著」的情形。）
    for (final tomb in await db.getAllTombstones()) {
      await db.applyTombstone(tomb['kind'] as String, tomb['ref'] as String,
          tomb['deleted_at'] as int);
    }

    onStep?.call('同步中…上傳到雲端');
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
    for (final p in await db.getPrayers()) {
      final m = p.toMap()..remove('id');
      batch.set(_col(uid, 'prayers').doc('p${p.createdAt}'), m);
      pending++;
      uploaded++;
      await commitIfFull();
    }
    for (final t in await db.getTodos()) {
      final m = t.toMap()..remove('id');
      batch.set(_col(uid, 'todos').doc('t${t.createdAt}'), m);
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
    for (final m in await db.getAllChapterCompletions()) {
      batch.set(
          _col(uid, 'chapter_completions')
              .doc('b${m['book_id']}_c${m['chapter']}'),
          {
            'book_id': m['book_id'],
            'chapter': m['chapter'],
            'completed_at': m['completed_at'],
          });
      pending++;
      uploaded++;
      await commitIfFull();
    }
    // 墓碑：上傳墓碑本身，並刪掉雲端對應的資料 doc（本機已無此筆活資料，
    // 因為新增/更新時會清墓碑，不變量保證兩者互斥，不會誤刪活資料）。
    const kindCol = {
      'bookmark': 'bookmarks',
      'highlight': 'highlights',
      'note': 'notes',
      'sermon': 'sermon_notes',
      'prayer': 'prayers',
      'todo': 'todos',
      'completion': 'chapter_completions',
    };
    for (final t in await db.getAllTombstones()) {
      final kind = t['kind'] as String;
      final ref = t['ref'] as String;
      batch.set(_col(uid, 'tombstones').doc('${kind}_$ref'), {
        'kind': kind,
        'ref': ref,
        'deleted_at': t['deleted_at'],
      });
      final col = kindCol[kind];
      if (col != null) {
        // 雲端 doc id：sermon = s{createdAt}（ref 本身就是），其餘 = b.._c.._v..
        batch.delete(_col(uid, col).doc(ref));
      }
      pending++;
      uploaded++;
      await commitIfFull();
    }
    if (pending > 0) {
      onStep?.call('同步中…寫入雲端');
      await batch.commit();
    }

    return '已同步（上傳 $uploaded 筆、下載合併 $downloaded 筆）';
  }
}
