import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/services/content_service.dart';
import 'package:bible_app/services/content_workflow_service.dart';

/// Daily Verse Admin R1 acceptance（Part G Daily Verse 1–10）。
/// 走既有 managed-content workflow（type='daily_verses'、contentId=日期）。
void main() {
  const type = 'daily_verses';
  const date = '2026-09-10';

  Future<void> draft(ContentWorkflowService wf,
          {String d = date, int verse = 16}) =>
      wf.saveDraft(type, d,
          contentType: 'daily_verse',
          payload: {
            'date': d,
            'book_id': 43,
            'chapter': 3,
            'verse': verse,
            'ref_text': '約3:$verse',
            'title': '',
            'content': '',
          },
          editorEmail: 'admin@e.com');

  group('學生可見（date gate + status）— dailyVerseVisibleToday 純函式', () {
    test('3 published + today → 顯示', () {
      expect(ContentService.dailyVerseVisibleToday('published', date, date), isTrue);
    });
    test('4 published + future → 今天不顯示', () {
      expect(ContentService.dailyVerseVisibleToday('published', '2026-09-20', date), isFalse);
    });
    test('5 published + past → 今天不顯示（但 status 不變＝不 auto-archive）', () {
      expect(ContentService.dailyVerseVisibleToday('published', '2026-09-01', date), isFalse);
    });
    test('1/2 draft/review + today → 不顯示', () {
      expect(ContentService.dailyVerseVisibleToday('draft', date, date), isFalse);
      expect(ContentService.dailyVerseVisibleToday('review', date, date), isFalse);
    });
  });

  group('workflow + fetchPublishedDailyVerse（fail-closed serving）', () {
    test('1 Draft → 學生讀不到（fetchPublished null）', () async {
      final fs = FakeFirebaseFirestore();
      final wf = ContentWorkflowService(fs);
      final cs = ContentService(fs);
      await draft(wf);
      expect(await cs.fetchPublishedDailyVerse(date), isNull);
    });

    test('2 Review → 學生讀不到', () async {
      final fs = FakeFirebaseFirestore();
      final wf = ContentWorkflowService(fs);
      final cs = ContentService(fs);
      await draft(wf);
      await wf.submitForReview(type, date, 'admin@e.com');
      expect(await cs.fetchPublishedDailyVerse(date), isNull);
    });

    test('3/10 Published → 可讀＋title/content 傳遞', () async {
      final fs = FakeFirebaseFirestore();
      final wf = ContentWorkflowService(fs);
      final cs = ContentService(fs);
      await wf.saveDraft(type, date,
          contentType: 'daily_verse',
          payload: {
            'date': date,
            'book_id': 43,
            'chapter': 3,
            'verse': 16,
            'title': '神的愛',
            'content': '這是引言',
          },
          editorEmail: 'admin@e.com');
      await wf.submitForReview(type, date, 'admin@e.com');
      await wf.approveAndPublish(type, date, publisherEmail: 'admin@e.com');
      final m = await cs.fetchPublishedDailyVerse(date);
      expect(m, isNotNull);
      expect(m!['book_id'], 43);
      expect(m['title'], '神的愛');
      expect(m['content'], '這是引言');
    });

    test('6 replacement draft → 版本 +1、仍單一 doc（one active per date）', () async {
      final fs = FakeFirebaseFirestore();
      final wf = ContentWorkflowService(fs);
      final cs = ContentService(fs);
      await draft(wf, verse: 16);
      await wf.submitForReview(type, date, 'admin@e.com');
      await wf.approveAndPublish(type, date, publisherEmail: 'admin@e.com');
      final v1 = (await cs.fetchPublishedDailyVerse(date))!['version'] as int;
      // 建立替代草稿 → 改節 → 發布
      await wf.createDraftFromPublished(type, date, editorEmail: 'admin@e.com');
      await draft(wf, verse: 17);
      await wf.submitForReview(type, date, 'admin@e.com');
      await wf.approveAndPublish(type, date, publisherEmail: 'admin@e.com');
      final pub = await cs.fetchPublishedDailyVerse(date);
      expect(pub!['version'], greaterThan(v1)); // 版本 +1
      expect(pub['verse'], 17); // 內容已替換
      // 仍只有一個 daily_verses/{date} doc（結構 one-active-per-date）
      final all = await fs.collection('daily_verses').get();
      expect(all.docs.map((d) => d.id).toList(), [date]);
    });

    test('7 Published 直接改草稿只動 workspace，不動 live published', () async {
      final fs = FakeFirebaseFirestore();
      final wf = ContentWorkflowService(fs);
      final cs = ContentService(fs);
      await draft(wf, verse: 16);
      await wf.submitForReview(type, date, 'admin@e.com');
      await wf.approveAndPublish(type, date, publisherEmail: 'admin@e.com');
      // 新草稿（未發布）
      await wf.createDraftFromPublished(type, date, editorEmail: 'admin@e.com');
      await draft(wf, verse: 99);
      // live published 仍是舊節（16），未被草稿污染
      final pub = await cs.fetchPublishedDailyVerse(date);
      expect(pub!['verse'], 16);
    });

    test('8 Archive → 學生立即讀不到', () async {
      final fs = FakeFirebaseFirestore();
      final wf = ContentWorkflowService(fs);
      final cs = ContentService(fs);
      await draft(wf);
      await wf.submitForReview(type, date, 'admin@e.com');
      await wf.approveAndPublish(type, date, publisherEmail: 'admin@e.com');
      expect(await cs.fetchPublishedDailyVerse(date), isNotNull);
      await wf.archive(type, date, 'admin@e.com');
      expect(await cs.fetchPublishedDailyVerse(date), isNull); // fail-closed
    });

    test('9 沒有任何 Published → fetchPublished null（不 fallback）', () async {
      final fs = FakeFirebaseFirestore();
      final cs = ContentService(fs);
      expect(await cs.fetchPublishedDailyVerse('2099-01-01'), isNull);
    });
  });
}
