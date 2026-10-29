import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bible_app/services/database_service.dart';
import 'package:bible_app/services/sync_service.dart';

/// 個人經文標記（書籤／稍後閱讀／章節完成）的跨裝置墓碑協調。
///
/// 缺口（0c2eae1 確認存在）：同步合併雲端墓碑後，本機可能留下「較新的活資料＋較舊墓碑」
/// （別台裝置刪除後又重新加入）。上傳時墓碑迴圈會 `batch.delete` 雲端 doc，
/// 把剛上傳的較新活資料刪掉；另外書籤／稍後閱讀的下載 upsert 用 `ignore`，
/// 本機留著較舊的 created_at → 被較舊墓碑刪掉 → 上傳時一併刪掉雲端較新的重新加入。
///
/// 真 SQLite（sqflite_common_ffi）＋ fake Firestore 多裝置往返。
void main() {
  sqfliteFfiInit();

  final opened = <Database>[];

  Future<(Database, DatabaseService)> openDevice() async {
    final d = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    final s = DatabaseService();
    await s.debugCreateAllTables(d);
    s.debugUseDatabase(d);
    opened.add(d);
    return (d, s);
  }

  tearDown(() async {
    for (final d in opened) {
      await d.close();
    }
    opened.clear();
  });

  // 讓 DateTime.now() 前進（各裝置時間戳要嚴格遞增）。
  Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 5));

  Future<List<Map<String, Object?>>> tombs(Database d, String kind) =>
      d.query('tombstones', where: 'kind = ?', whereArgs: [kind]);

  // 三類標記共用同一套情境。
  final kinds = <_Kind>[
    _Kind(
      name: '書籤',
      kind: 'bookmark',
      collection: 'bookmarks',
      docId: 'b43_c3_v16',
      set: (s, on) => s.setBookmark(43, 3, 16, on),
      has: (s) async =>
          (await s.getAllBookmarks()).any((b) => b.bookId == 43 &&
              b.chapter == 3 &&
              b.verse == 16),
    ),
    _Kind(
      name: '稍後閱讀',
      kind: 'later',
      collection: 'later',
      docId: 'b43_c3_v16',
      set: (s, on) => s.setLater(43, 3, 16, on),
      has: (s) async =>
          (await s.getAllLater()).any((b) => b.bookId == 43 &&
              b.chapter == 3 &&
              b.verse == 16),
    ),
    _Kind(
      name: '章節完成',
      kind: 'completion',
      collection: 'chapter_completions',
      docId: 'b43_c3',
      set: (s, on) => s.setChapterComplete(43, 3, on),
      has: (s) async => (await s.getAllChapterCompletions())
          .any((m) => m['book_id'] == 43 && m['chapter'] == 3),
    ),
  ];

  for (final k in kinds) {
    group('${k.name}（${k.kind}）', () {
      test('A 刪除並同步後，B 重新加入（較新）：B 上傳不會把雲端新資料刪掉，A 也收得到',
          () async {
        final fs = FakeFirebaseFirestore();
        final (dbA, a) = await openDevice();
        final (dbB, b) = await openDevice();
        final syncA = SyncService(a, firestore: fs);
        final syncB = SyncService(b, firestore: fs);
        final cloud = fs.collection('users').doc('u').collection(k.collection);

        await k.set(a, true);
        await syncA.syncAll('u');
        await syncB.syncAll('u');
        expect(await k.has(b), isTrue);

        await tick();
        await k.set(a, false);
        await syncA.syncAll('u'); // 雲端：doc 刪除＋墓碑
        await syncB.syncAll('u'); // B 也被刪除
        expect(await k.has(b), isFalse);
        expect((await cloud.get()).docs, isEmpty);

        await tick();
        await k.set(b, true); // 重新加入，比墓碑新
        await syncB.syncAll('u');
        // B 合併回舊墓碑後仍保留活資料，且墓碑被清掉（互斥不變量）。
        expect(await k.has(b), isTrue);
        expect(await tombs(dbB, k.kind), isEmpty);
        // 舊實作：同一個 batch 先 set 再 delete → 雲端被誤刪。
        expect((await cloud.get()).docs.map((d) => d.id), [k.docId]);

        await syncA.syncAll('u');
        expect(await k.has(a), isTrue);
        expect(await tombs(dbA, k.kind), isEmpty);

        // 再多往返幾輪仍穩定（冪等）。
        await syncB.syncAll('u');
        await syncA.syncAll('u');
        expect(await k.has(a), isTrue);
        expect(await k.has(b), isTrue);
        expect((await cloud.get()).docs.map((d) => d.id), [k.docId]);
      });

      test('A 本機有較舊標記（未同步）＋B 刪除＋C 重新加入：A 同步不會刪掉 C 的新資料',
          () async {
        final fs = FakeFirebaseFirestore();
        final (dbA, a) = await openDevice();
        final (_, b) = await openDevice();
        final (_, c) = await openDevice();
        final syncA = SyncService(a, firestore: fs);
        final syncB = SyncService(b, firestore: fs);
        final syncC = SyncService(c, firestore: fs);
        final cloud = fs.collection('users').doc('u').collection(k.collection);

        await k.set(a, true);
        await syncA.syncAll('u');
        await syncB.syncAll('u');
        await syncC.syncAll('u');

        await tick();
        await k.set(b, false);
        await syncB.syncAll('u');
        await syncC.syncAll('u');
        expect(await k.has(c), isFalse);

        await tick();
        await k.set(c, true);
        await syncC.syncAll('u');
        expect((await cloud.get()).docs.map((d) => d.id), [k.docId]);

        // A 一直沒同步：本機仍是最早那筆（時間比 B 的墓碑舊）。
        await syncA.syncAll('u');
        expect(await k.has(a), isTrue);
        expect(await tombs(dbA, k.kind), isEmpty);
        expect((await cloud.get()).docs.map((d) => d.id), [k.docId]);

        await syncB.syncAll('u');
        expect(await k.has(b), isTrue);
      });

      test('對照：刪除比本機較舊的活資料新 → 仍正常刪除（不被協調救回）', () async {
        final fs = FakeFirebaseFirestore();
        final (dbA, a) = await openDevice();
        final (_, b) = await openDevice();
        final syncA = SyncService(a, firestore: fs);
        final syncB = SyncService(b, firestore: fs);
        final cloud = fs.collection('users').doc('u').collection(k.collection);

        await k.set(a, true);
        await syncA.syncAll('u');
        await syncB.syncAll('u');
        await tick();
        await k.set(b, false);
        await syncB.syncAll('u');

        await syncA.syncAll('u');
        expect(await k.has(a), isFalse);
        expect(await tombs(dbA, k.kind), hasLength(1));
        expect((await cloud.get()).docs, isEmpty);
      });
    });
  }

  group('DB 層（真 SQLite）', () {
    test('reconcileMarkTombstones：只清比活資料舊的墓碑；同時間或較新保留；不碰非標記 kind',
        () async {
      final (d, s) = await openDevice();
      await d.insert('bookmarks',
          {'book_id': 1, 'chapter': 1, 'verse': 1, 'created_at': 3000});
      await d.insert('bookmarks',
          {'book_id': 1, 'chapter': 1, 'verse': 2, 'created_at': 2000});
      await d.insert(
          'later', {'book_id': 2, 'chapter': 1, 'verse': 1, 'created_at': 3000});
      await d.insert('chapter_completions',
          {'book_id': 3, 'chapter': 4, 'completed_at': 3000});
      await d.insert('highlights', {
        'book_id': 1,
        'chapter': 1,
        'verse': 1,
        'color': 0,
        'created_at': 3000,
      });
      await s.upsertTombstone('bookmark', 'b1_c1_v1', 2000); // 舊 → 清
      await s.upsertTombstone('bookmark', 'b1_c1_v2', 2000); // 同時間 → 留
      await s.upsertTombstone('bookmark', 'b9_c9_v9', 2000); // 無活資料 → 留
      await s.upsertTombstone('later', 'b2_c1_v1', 4000); // 較新 → 留
      await s.upsertTombstone('completion', 'b3_c4', 1000); // 舊 → 清
      await s.upsertTombstone('highlight', 'b1_c1_v1', 2000); // 舊 → 清
      await s.upsertTombstone('todo', 't1', 1); // 不屬於標記 → 不碰

      expect(await s.reconcileMarkTombstones(), 3);
      final left = await d.query('tombstones', orderBy: 'kind, ref');
      expect(left.map((t) => '${t['kind']}:${t['ref']}'), [
        'bookmark:b1_c1_v2',
        'bookmark:b9_c9_v9',
        'later:b2_c1_v1',
        'todo:t1',
      ]);
      // 冪等
      expect(await s.reconcileMarkTombstones(), 0);
    });

    test('reconcileMarkTombstones 失敗時整批回滾（墓碑一筆都不少）', () async {
      final (d, s) = await openDevice();
      await d.insert('bookmarks',
          {'book_id': 1, 'chapter': 1, 'verse': 1, 'created_at': 3000});
      await d.insert('chapter_completions',
          {'book_id': 3, 'chapter': 4, 'completed_at': 3000});
      await s.upsertTombstone('bookmark', 'b1_c1_v1', 2000);
      await s.upsertTombstone('completion', 'b3_c4', 1000);
      await d.execute('''
        CREATE TRIGGER fail_completion_untomb BEFORE DELETE ON tombstones
        WHEN OLD.kind = 'completion'
        BEGIN SELECT RAISE(ABORT, 'injected'); END
      ''');
      await expectLater(s.reconcileMarkTombstones(), throwsA(anything));
      expect(await d.query('tombstones'), hasLength(2));
    });

    test('upsertBookmark／upsertLater 保留較新的 created_at（不再沿用本機舊時間）', () async {
      final (d, s) = await openDevice();
      for (final (table, upsert) in [
        ('bookmarks', s.upsertBookmark),
        ('later', s.upsertLater),
      ]) {
        await upsert(1, 2, 3, 500);
        await upsert(1, 2, 3, 2000); // 較新 → 推進
        await upsert(1, 2, 3, 100); // 較舊 → 不倒退
        final rows = await d.query(table);
        expect(rows, hasLength(1), reason: table);
        expect(rows.single['created_at'], 2000, reason: table);
      }
    });
  });
}

class _Kind {
  final String name;
  final String kind;
  final String collection;
  final String docId;
  final Future<void> Function(DatabaseService s, bool on) set;
  final Future<bool> Function(DatabaseService s) has;

  const _Kind({
    required this.name,
    required this.kind,
    required this.collection,
    required this.docId,
    required this.set,
    required this.has,
  });
}
