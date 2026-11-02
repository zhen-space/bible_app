import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bible_app/models/models.dart';
import 'package:bible_app/services/database_service.dart';
import 'package:bible_app/services/sync_service.dart';

/// 螢光筆與經文筆記的跨裝置墓碑協調（182befd 之後的殘留缺口）。
///
/// 螢光筆：同書籤——別台刪除後又重新加入（較新），合併回來的舊墓碑會在上傳時
/// `batch.delete` 掉剛寫入的雲端 doc。
///
/// 筆記：雲端 doc 以節位為 id（`b{book}_c{ch}_v{v}`），同一節可有多則筆記。
/// 舊實作：同節多則上傳時互相覆蓋（雲端只剩一則）、下載時以「同節第一則」覆蓋別則、
/// 永久刪除最後一則時寫整節墓碑（會刪掉別台尚未同步、這台沒見過的同節筆記），
/// 而且整節墓碑合併回來後同樣會刪掉別台較新的重新加入。
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

  CollectionReference<Map<String, dynamic>> col(
          FakeFirebaseFirestore fs, String name) =>
      fs.collection('users').doc('u').collection(name);

  group('螢光筆（highlight）', () {
    Future<HighlightColor?> colorOf(DatabaseService s) async =>
        (await s.getChapterHighlights(43, 3))[16];

    test('A 移除並同步後，B 重新加入（較新、換色）：B 上傳不會把雲端新資料刪掉，A 也收到新顏色',
        () async {
      final fs = FakeFirebaseFirestore();
      final (dbA, a) = await openDevice();
      final (dbB, b) = await openDevice();
      final syncA = SyncService(a, firestore: fs);
      final syncB = SyncService(b, firestore: fs);
      final cloud = col(fs, 'highlights');

      await a.setHighlight(43, 3, 16, HighlightColor.values[0]);
      await syncA.syncAll('u');
      await syncB.syncAll('u');
      expect(await colorOf(b), HighlightColor.values[0]);

      await tick();
      await a.setHighlight(43, 3, 16, null);
      await syncA.syncAll('u');
      await syncB.syncAll('u');
      expect(await colorOf(b), isNull);
      expect((await cloud.get()).docs, isEmpty);

      await tick();
      await b.setHighlight(43, 3, 16, HighlightColor.values[2]);
      await syncB.syncAll('u');
      expect(await colorOf(b), HighlightColor.values[2]);
      expect(await tombs(dbB, 'highlight'), isEmpty);
      // 舊實作：同一個 batch 先 set 再 delete → 雲端被誤刪。
      expect((await cloud.get()).docs.map((d) => d.id), ['b43_c3_v16']);

      await syncA.syncAll('u');
      expect(await colorOf(a), HighlightColor.values[2]);
      expect(await tombs(dbA, 'highlight'), isEmpty);

      await syncB.syncAll('u');
      await syncA.syncAll('u');
      expect(await colorOf(a), HighlightColor.values[2]);
      expect(await colorOf(b), HighlightColor.values[2]);
      expect((await cloud.get()).docs.map((d) => d.id), ['b43_c3_v16']);
    });

    test('A 本機有較舊螢光筆（未同步）＋B 移除＋C 重新加入：A 同步不會刪掉 C 的新資料',
        () async {
      final fs = FakeFirebaseFirestore();
      final (dbA, a) = await openDevice();
      final (_, b) = await openDevice();
      final (_, c) = await openDevice();
      final syncA = SyncService(a, firestore: fs);
      final syncB = SyncService(b, firestore: fs);
      final syncC = SyncService(c, firestore: fs);

      await a.setHighlight(43, 3, 16, HighlightColor.values[0]);
      await syncA.syncAll('u');
      await syncB.syncAll('u');
      await syncC.syncAll('u');

      await tick();
      await b.setHighlight(43, 3, 16, null);
      await syncB.syncAll('u');
      await syncC.syncAll('u');
      expect(await colorOf(c), isNull);

      await tick();
      await c.setHighlight(43, 3, 16, HighlightColor.values[1]);
      await syncC.syncAll('u');

      await syncA.syncAll('u');
      expect(await colorOf(a), HighlightColor.values[1]);
      expect(await tombs(dbA, 'highlight'), isEmpty);
      expect((await col(fs, 'highlights').get()).docs.map((d) => d.id),
          ['b43_c3_v16']);

      await syncB.syncAll('u');
      expect(await colorOf(b), HighlightColor.values[1]);
    });

    test('對照：移除比活資料新 → 各裝置與雲端仍正常刪除', () async {
      final fs = FakeFirebaseFirestore();
      final (dbA, a) = await openDevice();
      final (_, b) = await openDevice();
      final syncA = SyncService(a, firestore: fs);
      final syncB = SyncService(b, firestore: fs);

      await a.setHighlight(43, 3, 16, HighlightColor.values[0]);
      await a.setHighlight(43, 3, 17, HighlightColor.values[3]);
      await syncA.syncAll('u');
      await syncB.syncAll('u');
      await tick();
      await b.setHighlight(43, 3, 16, null);
      await syncB.syncAll('u');

      await syncA.syncAll('u');
      expect(await colorOf(a), isNull);
      expect((await a.getChapterHighlights(43, 3))[17], HighlightColor.values[3]);
      expect(await tombs(dbA, 'highlight'), hasLength(1));
      expect((await col(fs, 'highlights').get()).docs.map((d) => d.id),
          ['b43_c3_v17']);
    });
  });

  group('經文筆記（note）', () {
    Future<int> add(DatabaseService s, String content,
            {int b = 43, int c = 3, int v = 16}) =>
        s.saveNoteFull(Note(
            bookId: b,
            chapter: c,
            verse: v,
            content: content,
            createdAt: 0,
            updatedAt: 0));

    Future<void> purge(DatabaseService s, String content) async {
      final n = (await s.getAllNotes()).firstWhere((n) => n.content == content);
      await s.softDeleteNoteById(n.id!);
      await s.purgeNote(n.id!);
    }

    Future<List<String>> contents(DatabaseService s) async =>
        (await s.getAllNotes()).map((n) => n.content).toList()..sort();

    Future<List<String>> cloudContents(FakeFirebaseFirestore fs,
        [String docId = 'b43_c3_v16']) async {
      final d = await col(fs, 'notes').doc(docId).get();
      if (!d.exists) return [];
      return [
        for (final e in d.data()!['notes'] as List) (e as Map)['content'] as String
      ]..sort();
    }

    test('A 永久刪除並同步後，B 在同一節新增（較新）：雲端與兩台都保留，多輪穩定', () async {
      final fs = FakeFirebaseFirestore();
      final (_, a) = await openDevice();
      final (dbB, b) = await openDevice();
      final syncA = SyncService(a, firestore: fs);
      final syncB = SyncService(b, firestore: fs);

      await add(a, '舊筆記');
      await syncA.syncAll('u');
      await syncB.syncAll('u');
      expect(await contents(b), ['舊筆記']);

      await tick();
      await purge(a, '舊筆記');
      await syncA.syncAll('u');
      await syncB.syncAll('u');
      expect(await contents(b), isEmpty);
      expect((await col(fs, 'notes').get()).docs, isEmpty);

      await tick();
      await add(b, '重新寫的');
      await syncB.syncAll('u');
      expect(await contents(b), ['重新寫的']);
      expect(await tombs(dbB, 'note'), isEmpty);
      expect(await cloudContents(fs), ['重新寫的']);

      await syncA.syncAll('u');
      expect(await contents(a), ['重新寫的']);

      for (var i = 0; i < 2; i++) {
        await syncB.syncAll('u');
        await syncA.syncAll('u');
      }
      expect(await contents(a), ['重新寫的']);
      expect(await contents(b), ['重新寫的']);
      expect(await cloudContents(fs), ['重新寫的']);
    });

    test('同一節多則筆記：同步不互相覆蓋；只永久刪除其中一則，另一則各處都保留', () async {
      final fs = FakeFirebaseFirestore();
      final (_, a) = await openDevice();
      final (_, b) = await openDevice();
      final syncA = SyncService(a, firestore: fs);
      final syncB = SyncService(b, firestore: fs);

      await add(a, '第一則');
      await tick();
      await add(a, '第二則');
      await add(a, '別節', v: 17);
      await syncA.syncAll('u');
      // 舊實作：兩則寫同一個 doc，雲端只剩一則；B 只收到一則。
      expect(await cloudContents(fs), ['第一則', '第二則']);
      await syncB.syncAll('u');
      expect(await contents(b), ['別節', '第一則', '第二則']);

      // B 編輯第二則、A 同時新增第三則（同一節）：都不會蓋掉別則。
      await tick();
      final second =
          (await b.getAllNotes()).firstWhere((n) => n.content == '第二則');
      await b.saveNoteFull(Note(
          id: second.id,
          bookId: 43,
          chapter: 3,
          verse: 16,
          content: '第二則（B 改）',
          createdAt: second.createdAt,
          updatedAt: second.updatedAt));
      await add(a, '第三則');
      await syncB.syncAll('u');
      await syncA.syncAll('u');
      await syncB.syncAll('u');
      const all = ['別節', '第一則', '第三則', '第二則（B 改）'];
      expect(await contents(a), all);
      expect(await contents(b), all);

      // A 永久刪除第一則：只寫單則墓碑，第二、三則與別節不受影響。
      await tick();
      await purge(a, '第一則');
      await syncA.syncAll('u');
      expect(await cloudContents(fs), ['第三則', '第二則（B 改）']);
      await syncB.syncAll('u');
      const left = ['別節', '第三則', '第二則（B 改）'];
      expect(await contents(b), left);

      for (var i = 0; i < 2; i++) {
        await syncA.syncAll('u');
        await syncB.syncAll('u');
      }
      expect(await contents(a), left);
      expect(await contents(b), left);
      expect(await cloudContents(fs), ['第三則', '第二則（B 改）']);
      expect(await cloudContents(fs, 'b43_c3_v17'), ['別節']);
    });

    test('三台：A 刪掉這節最後一則，C 離線時在同節寫的另一則（更早、A 沒見過）不被誤刪',
        () async {
      final fs = FakeFirebaseFirestore();
      final (_, a) = await openDevice();
      final (_, b) = await openDevice();
      final (_, c) = await openDevice();
      final syncA = SyncService(a, firestore: fs);
      final syncB = SyncService(b, firestore: fs);
      final syncC = SyncService(c, firestore: fs);

      await add(a, '共同筆記');
      await syncA.syncAll('u');
      await syncB.syncAll('u');
      await syncC.syncAll('u');

      // C 離線寫了同節另一則（時間早於 A 的刪除）。
      await tick();
      await add(c, 'C 的離線筆記');

      await tick();
      await purge(a, '共同筆記'); // A 這節已無筆記
      await syncA.syncAll('u');
      expect((await col(fs, 'notes').get()).docs, isEmpty);

      // 舊實作：整節墓碑（時間比 C 的筆記新）會把 C 的筆記一起刪掉。
      await syncC.syncAll('u');
      expect(await contents(c), ['C 的離線筆記']);
      expect(await cloudContents(fs), ['C 的離線筆記']);

      await syncA.syncAll('u');
      await syncB.syncAll('u');
      expect(await contents(a), ['C 的離線筆記']);
      expect(await contents(b), ['C 的離線筆記']);
    });

    test('三台：A 有較舊筆記（未同步）＋B 刪除＋C 同節重新寫：A 同步不刪 C 的新筆記', () async {
      final fs = FakeFirebaseFirestore();
      final (_, a) = await openDevice();
      final (_, b) = await openDevice();
      final (_, c) = await openDevice();
      final syncA = SyncService(a, firestore: fs);
      final syncB = SyncService(b, firestore: fs);
      final syncC = SyncService(c, firestore: fs);

      await add(a, '最早');
      await syncA.syncAll('u');
      await syncB.syncAll('u');
      await syncC.syncAll('u');

      await tick();
      await purge(b, '最早');
      await syncB.syncAll('u');
      await syncC.syncAll('u');
      expect(await contents(c), isEmpty);

      await tick();
      await add(c, 'C 重新寫');
      await syncC.syncAll('u');

      await syncA.syncAll('u'); // A 的「最早」被單則墓碑刪掉，C 的新筆記保留
      expect(await contents(a), ['C 重新寫']);
      expect(await cloudContents(fs), ['C 重新寫']);
      await syncB.syncAll('u');
      expect(await contents(b), ['C 重新寫']);
    });

    test('對照：正常永久刪除 → 另一台也刪除、雲端 doc 移除、墓碑保留擋復活', () async {
      final fs = FakeFirebaseFirestore();
      final (_, a) = await openDevice();
      final (dbB, b) = await openDevice();
      final syncA = SyncService(a, firestore: fs);
      final syncB = SyncService(b, firestore: fs);

      await add(a, '要刪的');
      await add(a, '別節', v: 17);
      await syncA.syncAll('u');
      await syncB.syncAll('u');
      await tick();
      await purge(b, '要刪的');
      await syncB.syncAll('u');

      await syncA.syncAll('u');
      expect(await contents(a), ['別節']);
      expect(await tombs(dbB, 'note_item'), hasLength(1));
      expect((await col(fs, 'notes').get()).docs.map((d) => d.id), ['b43_c3_v17']);

      await syncB.syncAll('u');
      await syncA.syncAll('u');
      expect(await contents(a), ['別節']);
      expect(await contents(b), ['別節']);
    });

    test('改錨點：A 把筆記移到別節，B 同步後只在新節（不重複、舊節 doc 移除）', () async {
      final fs = FakeFirebaseFirestore();
      final (_, a) = await openDevice();
      final (_, b) = await openDevice();
      final syncA = SyncService(a, firestore: fs);
      final syncB = SyncService(b, firestore: fs);

      final id = await add(a, '會搬家');
      await syncA.syncAll('u');
      await syncB.syncAll('u');
      await tick();
      final n = (await a.getAllNotes()).single;
      await a.saveNoteFull(Note(
          id: id,
          bookId: 1,
          chapter: 1,
          verse: 1,
          content: '會搬家',
          createdAt: n.createdAt,
          updatedAt: n.updatedAt));
      await syncA.syncAll('u');
      await syncB.syncAll('u');
      final onB = await b.getAllNotes();
      expect(onB.map((n) => '${n.bookId}:${n.chapter}:${n.verse}'), ['1:1:1']);
      expect((await col(fs, 'notes').get()).docs.map((d) => d.id), ['b1_c1_v1']);
    });

    test('相容舊版：只有頂層欄位的舊 doc 照樣下載；新版 doc 頂層保留最新一則供舊版讀', () async {
      final fs = FakeFirebaseFirestore();
      final (_, a) = await openDevice();
      final syncA = SyncService(a, firestore: fs);
      await col(fs, 'notes').doc('b19_c23_v1').set({
        'book_id': 19,
        'chapter': 23,
        'verse': 1,
        'title': '',
        'content': '舊版寫的',
        'tags': '',
        'refs': '',
        'deleted_at': 0,
        'created_at': 1000,
        'updated_at': 1000,
      });
      await add(a, '較早');
      await tick();
      await add(a, '較新');
      await syncA.syncAll('u');
      expect(await contents(a), ['舊版寫的', '較新', '較早']);

      final doc = (await col(fs, 'notes').doc('b43_c3_v16').get()).data()!;
      expect(doc['content'], '較新'); // 舊版 App 讀頂層
      expect((doc['notes'] as List), hasLength(2));
      // 舊 doc 被改寫成新格式，內容不變。
      expect(await cloudContents(fs, 'b19_c23_v1'), ['舊版寫的']);
    });

    test('相容舊版：舊同步把兩台筆記合併成同內容但 created_at 不同 → 升級後不重複，收斂到較早的 created_at',
        () async {
      final fs = FakeFirebaseFirestore();
      final (dA, a) = await openDevice();
      final (dB, b) = await openDevice();
      final syncA = SyncService(a, firestore: fs);
      final syncB = SyncService(b, firestore: fs);
      final row = {
        'book_id': 43,
        'chapter': 3,
        'verse': 16,
        'title': '',
        'content': '同一份',
        'tags': '',
        'refs': '',
        'deleted_at': 0,
        'updated_at': 5000,
      };
      await dA.insert('notes', {...row, 'created_at': 2000});
      await dB.insert('notes', {...row, 'created_at': 1000});
      await col(fs, 'notes').doc('b43_c3_v16').set({...row, 'created_at': 1000});

      await syncA.syncAll('u');
      await syncB.syncAll('u');
      await syncA.syncAll('u');
      for (final d in [dA, dB]) {
        final rows = await d.query('notes');
        expect(rows, hasLength(1));
        expect(rows.single['created_at'], 1000);
      }
      expect(await cloudContents(fs), ['同一份']);
    });

    test('最近刪除（本機 trash）不同步刪除：另一台仍保留，雲端 doc 不被刪', () async {
      final fs = FakeFirebaseFirestore();
      final (_, a) = await openDevice();
      final (_, b) = await openDevice();
      final syncA = SyncService(a, firestore: fs);
      final syncB = SyncService(b, firestore: fs);

      final id = await add(a, '丟到最近刪除');
      await syncA.syncAll('u');
      await syncB.syncAll('u');
      await a.softDeleteNoteById(id);
      await syncA.syncAll('u');
      await syncB.syncAll('u');
      expect(await contents(b), ['丟到最近刪除']);
      expect(await cloudContents(fs), ['丟到最近刪除']);
      expect((await a.getDeletedNotes()).map((n) => n.content), ['丟到最近刪除']);
    });
  });

  group('DB 層（真 SQLite）', () {
    test('reconcileMarkTombstones：筆記整節／單則墓碑只在有較新筆記時清掉', () async {
      final (d, s) = await openDevice();
      Map<String, Object?> note(int v, int created, int updated) => {
            'book_id': 1,
            'chapter': 1,
            'verse': v,
            'content': 'x',
            'created_at': created,
            'updated_at': updated,
          };
      await d.insert('notes', note(1, 100, 3000));
      await d.insert('notes', {...note(2, 200, 2000), 'deleted_at': 2000});
      await s.upsertTombstone('note', 'b1_c1_v1', 2500); // 較新筆記 → 清
      await s.upsertTombstone('note', 'b1_c1_v2', 1000); // 最近刪除中的較新 → 清
      await s.upsertTombstone('note', 'b1_c1_v3', 1000); // 無筆記 → 留
      await s.upsertTombstone('note_item', 'n100', 2999); // 較新 → 清
      await s.upsertTombstone('note_item', 'n200', 2000); // 同時間 → 留
      await s.upsertTombstone('note_item', 'n999', 1); // 無此筆記 → 留

      expect(await s.reconcileMarkTombstones(), 3);
      final left = await d.query('tombstones', orderBy: 'kind, ref');
      expect(left.map((t) => '${t['kind']}:${t['ref']}'),
          ['note:b1_c1_v3', 'note_item:n200', 'note_item:n999']);
      expect(await s.reconcileMarkTombstones(), 0);
    });

    test('applyTombstone note_item：只刪該身分且不比刪除新的筆記，同節其他筆記不動', () async {
      final (d, s) = await openDevice();
      for (final (created, updated) in [(100, 500), (200, 500), (300, 900)]) {
        await d.insert('notes', {
          'book_id': 1,
          'chapter': 1,
          'verse': 1,
          'content': 'n$created',
          'created_at': created,
          'updated_at': updated,
        });
      }
      expect(await s.applyTombstone('note_item', 'n100', 600), 1);
      expect(await s.applyTombstone('note_item', 'n300', 600), 0); // 較新 → 留
      expect(await s.applyTombstone('note_item', 'bad', 600), 0);
      final left = await d.query('notes', orderBy: 'created_at');
      expect(left.map((r) => r['created_at']), [200, 300]);
    });

    test('upsertNote：以 created_at 對身分，不覆蓋同節別則；較舊不倒退', () async {
      final (d, s) = await openDevice();
      await s.upsertNote(1, 1, 1, '甲', 100, 1000);
      await s.upsertNote(1, 1, 1, '乙', 200, 1000); // 同節另一則 → 新增，不覆蓋甲
      await s.upsertNote(1, 1, 1, '甲改', 100, 2000); // 較新 → 更新
      await s.upsertNote(1, 1, 1, '甲舊', 100, 1500); // 較舊 → 不倒退
      final rows = await d.query('notes', orderBy: 'created_at');
      expect(rows.map((r) => r['content']), ['甲改', '乙']);
    });
  });
}
