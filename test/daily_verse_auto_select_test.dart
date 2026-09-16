import 'dart:convert';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/daily_verse_catalog.dart';
import 'package:bible_app/models/models.dart';
import 'package:bible_app/models/daily_verse_batch.dart';
import 'package:bible_app/services/content_workflow_service.dart';
import 'package:bible_app/services/daily_verse_auto_selector.dart';
import 'package:bible_app/services/daily_verse_batch_service.dart';
import 'package:bible_app/services/daily_verse_scheduler.dart';
import 'package:bible_app/utils/date_key.dart';

List<Book> loadBooks() {
  final raw = File('assets/bible/cuv.json').readAsStringSync();
  final data = json.decode(raw) as Map<String, dynamic>;
  return (data['books'] as List)
      .map((b) => Book.fromJson(b as Map<String, dynamic>))
      .toList();
}

int _ord(String ymd) {
  final p = ymd.split('-');
  return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]))
      .difference(DateTime.utc(1970, 1, 1))
      .inDays;
}

void main() {
  final books = loadBooks();

  group('curated catalog：全部可解析且通過機械式硬排除', () {
    test('每一條都能在 corpus 解析到單節', () {
      for (final e in kDailyVerseCatalog) {
        final t = DailyVerseAutoSelector.resolveText(books, e.book, e.chapter, e.verse);
        expect(t, isNotNull, reason: '${e.book}:${e.chapter}:${e.verse} 無法解析');
        expect(t!.trim().isNotEmpty, isTrue);
      }
    });

    test('每一條都通過硬排除（too_short/too_long/digit_heavy/genealogy/list_like 皆無）', () {
      for (final e in kDailyVerseCatalog) {
        final t = DailyVerseAutoSelector.resolveText(books, e.book, e.chapter, e.verse)!;
        expect(DailyVerseAutoSelector.hardIssues(t), isEmpty,
            reason: '${e.book}:${e.chapter}:${e.verse} "$t"');
      }
    });

    test('catalog 覆蓋多卷（分散性前提）', () {
      final booksInCatalog = kDailyVerseCatalog.map((e) => e.book).toSet();
      expect(booksInCatalog.length, greaterThanOrEqualTo(30));
    });
  });

  group('機械式排除/建議旗標（合成資料，不涉神學判斷）', () {
    test('too_short / too_long', () {
      expect(DailyVerseAutoSelector.hardIssues('主'), contains('too_short'));
      expect(DailyVerseAutoSelector.hardIssues('字' * 91), contains('too_long'));
    });
    test('digit_heavy', () {
      expect(DailyVerseAutoSelector.hardIssues('共有12345678個'), contains('digit_heavy'));
    });
    test('genealogy（生了…＋數字）', () {
      expect(DailyVerseAutoSelector.hardIssues('亞當活到130歲，生了塞特'),
          anyOf(contains('genealogy'), contains('digit_heavy')));
    });
    test('list_like（≥4 頓號）', () {
      expect(DailyVerseAutoSelector.hardIssues('仁愛、喜樂、和平、忍耐、恩慈'),
          contains('list_like'));
    });
    test('乾淨句子無硬 issue；代名詞開頭為建議旗標', () {
      expect(DailyVerseAutoSelector.hardIssues('耶和華是我的牧者，我必不致缺乏。'), isEmpty);
      expect(DailyVerseAutoSelector.advisoryFlags('他必成全你所託付的。'),
          contains('pronoun_start'));
      expect(DailyVerseAutoSelector.advisoryFlags('耶和華是我的牧者。'), isEmpty);
    });
  });

  group('自動選取：deterministic、日界、可解析、分散、防重複', () {
    DailyVerseAutoPlan gen({
      String start = '2026-09-17',
      int days = 30,
      Map<String, ({int bookId, int chapter, int verse})> pub = const {},
      List<({String date, int bookId, int chapter, int verse})> hist = const [],
    }) =>
        DailyVerseAutoSelector.generate(
          books: books,
          startYmd: start,
          days: days,
          publishedByDate: pub,
          history: hist,
        );

    test('deterministic：同輸入兩次呼叫完全相同', () {
      final a = gen();
      final b = gen();
      String sig(DailyVerseAutoPlan p) =>
          p.days.map((d) => '${d.date}|${d.ref}|${d.failClosed}|${d.published}').join(';');
      expect(sig(a), sig(b));
    });

    test('Asia/Taipei 日界：每日 date 為 startYmd 起連續台北日期', () {
      final p = gen(days: 5);
      expect(p.days.map((d) => d.date).toList(),
          ['2026-09-17', '2026-09-18', '2026-09-19', '2026-09-20', '2026-09-21']);
      // date_key 與 selector 對齊：某固定時刻的台北日 = 預期
      expect(taipeiYmd(DateTime.utc(2026, 9, 16, 20, 0)), '2026-09-17'); // 20:00Z+8h=次日04:00
    });

    test('預設 30 天全部可解析、無 fail-closed（catalog 足量）', () {
      final p = gen(days: 30);
      expect(p.days.length, 30);
      expect(p.hasFailClosed, isFalse);
      for (final d in p.days) {
        expect(d.bookId, isNotNull);
        expect(d.resolvedText, isNotNull);
        expect(d.resolvedText!.isNotEmpty, isTrue);
      }
    });

    test('書卷分散：不連續同書卷、任一 7 天視窗同書卷 ≤2', () {
      final p = gen(days: 30);
      for (var i = 1; i < p.days.length; i++) {
        final a = p.days[i - 1].bookId, b = p.days[i].bookId;
        if (a != null && b != null) expect(a == b, isFalse, reason: 'day $i 連續同書卷');
      }
      for (final d in p.days) {
        if (d.bookId == null) continue;
        final o = _ord(d.date);
        final cnt = p.days
            .where((x) => x.bookId == d.bookId && (o - _ord(x.date)).abs() < 7)
            .length;
        expect(cnt, lessThanOrEqualTo(2));
      }
    });

    test('30 天內節位不重複', () {
      final p = gen(days: 30);
      final keys = [
        for (final d in p.days)
          if (d.bookId != null) '${d.bookId}:${d.chapter}:${d.verse}'
      ];
      expect(keys.length, keys.toSet().length);
    });

    test('365 天防重複：近期已用之節位不再入選；滿 365 天可再用', () {
      // 取 catalog 第一條為「近期已用」（29 天前），它不得出現在計畫。
      final first = kDailyVerseCatalog.first;
      final recent = DailyVerseScheduler.addDaysYmd('2026-09-17', -29);
      final p = gen(hist: [
        (date: recent, bookId: first.book, chapter: first.chapter, verse: first.verse)
      ]);
      final present = p.days.any((d) =>
          d.bookId == first.book && d.chapter == first.chapter && d.verse == first.verse);
      expect(present, isFalse);

      // 400 天前用過（>365）→ 允許再次入選（不被防重複擋）。
      final old = DailyVerseScheduler.addDaysYmd('2026-09-17', -400);
      final p2 = gen(hist: [
        (date: old, bookId: first.book, chapter: first.chapter, verse: first.verse)
      ]);
      expect(p2.days.first.bookId, first.book); // 第一天仍取回第一條
    });

    test('fail-closed：空 catalog → 全部留白、planToSpecs 為空、不 fabricate', () {
      final p = DailyVerseAutoSelector.generate(
          books: books, startYmd: '2026-09-17', days: 5, catalog: const []);
      expect(p.days.every((d) => d.failClosed), isTrue);
      expect(p.hasFailClosed, isTrue);
      expect(p.warnings, contains('shortfall:5'));
      expect(DailyVerseAutoSelector.planToSpecs(p), isEmpty);
    });

    test('不覆寫已 Published：該日鎖定、只讀、不進 specs', () {
      final p = gen(pub: {
        '2026-09-18': (bookId: 43, chapter: 3, verse: 16),
      });
      final locked = p.days.firstWhere((d) => d.date == '2026-09-18');
      expect(locked.published, isTrue);
      expect(locked.bookId, 43);
      expect(locked.isDraftable, isFalse);
      final specDates = DailyVerseAutoSelector.planToSpecs(p).map((s) => s.date).toSet();
      expect(specDates.contains('2026-09-18'), isFalse);
    });

    test('重新產生只影響未發布：鎖定日不變，未發布日仍 deterministic', () {
      final pub = {'2026-09-17': (bookId: 43, chapter: 3, verse: 16)};
      final a = gen(pub: pub);
      final b = gen(pub: pub);
      // 鎖定日一致
      expect(a.days.first.published, isTrue);
      expect(a.days.first.bookId, 43);
      // 未發布日在兩次產生間相同（deterministic）
      expect(a.days.map((d) => '${d.date}|${d.ref}').toList(),
          b.days.map((d) => '${d.date}|${d.ref}').toList());
    });
  });

  group('planToSpecs / planFromDatedPool', () {
    test('planToSpecs 只含可建立日（refResolves 皆 true）', () {
      final p = DailyVerseAutoSelector.generate(
          books: books, startYmd: '2026-09-17', days: 10);
      final specs = DailyVerseAutoSelector.planToSpecs(p);
      expect(specs.length, p.draftableDays.length);
      expect(specs.every((s) => s.refResolves), isTrue);
    });

    test('planFromDatedPool：由帶 date 的池還原計畫，並以最新 published 鎖定', () {
      final pool = DailyVerseCandidatePool(
        source: 'auto',
        approved: true,
        version: 1,
        catalogVersion: kDailyVerseCatalogVersion,
        algoVersion: kDailyVerseSelectionAlgoVersion,
        candidates: const [
          DailyVerseCandidate(ref: '約3:16', date: '2026-09-17'),
          DailyVerseCandidate(ref: '詩23:1', date: '2026-09-18'),
        ],
      );
      final plan = DailyVerseAutoSelector.planFromDatedPool(
        books: books,
        pool: pool,
        publishedByDate: {'2026-09-18': (bookId: 19, chapter: 23, verse: 1)},
      );
      expect(plan.days.length, 2);
      expect(plan.days[0].date, '2026-09-17');
      expect(plan.days[0].isDraftable, isTrue);
      expect(plan.days[0].bookId, 43);
      expect(plan.days[1].published, isTrue); // 已發布鎖定
    });

    test('dayFromRef：可解析回帶正文；不可解析回 null', () {
      final d = DailyVerseAutoSelector.dayFromRef(books, '2026-09-17', '約3:16');
      expect(d, isNotNull);
      expect(d!.bookId, 43);
      expect(d.resolvedText, isNotNull);
      expect(DailyVerseAutoSelector.dayFromRef(books, '2026-09-17', '不存在99:99'), isNull);
    });
  });

  group('批次服務（fake firestore）：generate→save→approve→draft', () {
    late FakeFirebaseFirestore fs;
    late DailyVerseBatchService svc;
    setUp(() {
      fs = FakeFirebaseFirestore();
      svc = DailyVerseBatchService(fs, ContentWorkflowService(fs));
    });

    test('generateAutoPlan 讀 published 歷史並鎖定；未發布日可建立', () async {
      // 種一筆已發布：落在視窗內的日期鎖定。
      await fs.collection('daily_verses').doc('2026-09-18').set({
        'status': 'published', 'date': '2026-09-18',
        'book_id': 43, 'chapter': 3, 'verse': 16,
      });
      final plan = await svc.generateAutoPlan(books: books, startYmd: '2026-09-17', days: 5);
      final locked = plan.days.firstWhere((d) => d.date == '2026-09-18');
      expect(locked.published, isTrue);
      expect(plan.draftableDays.every((d) => d.date != '2026-09-18'), isTrue);
    });

    test('saveAutoPlan 存帶 date 候選 + provenance（approved=false）；approvePool 後可建 Draft', () async {
      final plan = await svc.generateAutoPlan(books: books, startYmd: '2026-09-17', days: 6);
      final saved = await svc.saveAutoPlan(plan);
      expect(saved.approved, isFalse);
      expect(saved.source, 'auto');
      expect(saved.catalogVersion, kDailyVerseCatalogVersion);
      expect(saved.candidates.every((c) => c.date != null), isTrue);

      final approved = await svc.approvePool();
      expect(approved.approved, isTrue);
      expect(approved.version, 1);

      final specs = DailyVerseAutoSelector.planToSpecs(plan);
      final dates = await svc.applyDraftBatch(specs, editorEmail: 'a@x');
      expect(dates.length, specs.length);
      final ws = await fs.collection('daily_verses_workspace').get();
      expect(ws.docs.length, specs.length);
      expect(ws.docs.first.data()['content_type'], 'daily_verse');
    });

    test('saveAutoPlan 全部已發布/留白 → 無可建立日 → throw', () async {
      final plan = DailyVerseAutoPlan(startYmd: '2026-09-17', days: const [
        DailyVersePlanDay(date: '2026-09-17', published: true, bookId: 1, chapter: 1, verse: 1),
        DailyVersePlanDay(date: '2026-09-18', failClosed: true),
      ]);
      await expectLater(svc.saveAutoPlan(plan), throwsStateError);
    });

    test('端到端 draft→review→publish（未發布日）', () async {
      final plan = await svc.generateAutoPlan(books: books, startYmd: '2026-09-17', days: 4);
      await svc.saveAutoPlan(plan);
      await svc.approvePool();
      final specs = DailyVerseAutoSelector.planToSpecs(plan);
      final dates = await svc.applyDraftBatch(specs, editorEmail: 'a@x');
      await svc.submitBatchForReview(dates, editorEmail: 'a@x');
      await svc.publishBatch(dates, publisherEmail: 'admin@x');
      final pub = await fs.collection('daily_verses').get();
      expect(pub.docs.length, dates.length);
      expect(pub.docs.first.data()['status'], 'published');
    });
  });
}
