import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/models/managed_content.dart';
import 'package:bible_app/services/content_workflow_service.dart';
import 'package:bible_app/services/qa_service.dart';

void main() {
  group('ContentStatus', () {
    test('fromName / isPublished', () {
      expect(ContentStatus.fromName('published'), ContentStatus.published);
      expect(ContentStatus.fromName('draft'), ContentStatus.draft);
      expect(ContentStatus.fromName('review'), ContentStatus.review);
      expect(ContentStatus.fromName('rejected'), ContentStatus.rejected);
      expect(ContentStatus.fromName('archived'), ContentStatus.archived);
      // 未知值 fail-safe 落在 draft（不會誤判成 published）。
      expect(ContentStatus.fromName(null), ContentStatus.draft);
      expect(ContentStatus.fromName('bogus'), ContentStatus.draft);
      expect(ContentStatus.published.isPublished, true);
      expect(ContentStatus.draft.isPublished, false);
    });
  });

  group('ManagedContent round-trip', () {
    test('toMap/fromMap 保留 content_type/version/provenance/新 by 欄名', () {
      const c = ManagedContent(
        contentId: 'chapter_1_1',
        contentType: 'chapter_guide',
        status: ContentStatus.published,
        version: 3,
        createdAt: 100,
        createdBy: 'a@x',
        updatedAt: 200,
        updatedBy: 'b@x',
        reviewedBy: 'r@x',
        reviewedAt: 150,
        publishedBy: 'p@x',
        publishedAt: 200,
        archivedAt: 0,
        provenance: ContentProvenance(source: '管理員親撰', note: 'n'),
        payload: {'intro': 'hi'},
      );
      final m = c.toMap();
      expect(m['content_type'], 'chapter_guide');
      expect(m['reviewed_by'], 'r@x');
      expect(m['published_by'], 'p@x');
      expect(m['version'], 3);
      final back = ManagedContent.fromMap('doc', m);
      expect(back.contentId, 'chapter_1_1');
      expect(back.contentType, 'chapter_guide');
      expect(back.status, ContentStatus.published);
      expect(back.version, 3);
      expect(back.reviewedBy, 'r@x');
      expect(back.publishedBy, 'p@x');
      expect(back.provenance.source, '管理員親撰');
    });

    test('fromMap 相容 legacy 欄名 reviewer/publisher', () {
      final back = ManagedContent.fromMap('doc', {
        'status': 'published',
        'version': 1,
        'created_at': 1,
        'updated_at': 1,
        'reviewer': 'legacy-r',
        'publisher': 'legacy-p',
      });
      expect(back.reviewedBy, 'legacy-r');
      expect(back.publishedBy, 'legacy-p');
    });
  });

  group('ContentWorkflowService.payloadOf', () {
    test('把 meta 欄位剝掉，只留 payload', () {
      final doc = {
        'content_id': 'x',
        'content_type': 'knowledge',
        'status': 'published',
        'version': 2,
        'created_at': 1,
        'created_by': 'a',
        'updated_at': 2,
        'updated_by': 'b',
        'reviewed_by': 'r',
        'reviewed_at': 1,
        'published_by': 'p',
        'published_at': 2,
        'archived_at': 0,
        'provenance': {'source': 's'},
        'versions': [],
        // legacy 舊欄名也要被剝掉
        'reviewer': 'old',
        'publisher': 'old',
        // 真正的 payload
        'timeline': [1, 2, 3],
        'people': ['a'],
      };
      final payload = ContentWorkflowService.payloadOf(doc);
      expect(payload.keys.toSet(), {'timeline', 'people'});
      expect(payload['timeline'], [1, 2, 3]);
    });
  });

  group('AnswerSource', () {
    test('round-trip 含 version + evidence', () {
      const s = AnswerSource(
          contentId: 'q1', version: 4, kind: 'question', evidence: 'hit');
      final back = AnswerSource.fromMap(s.toMap());
      expect(back.contentId, 'q1');
      expect(back.version, 4);
      expect(back.kind, 'question');
      expect(back.evidence, 'hit');
    });
  });

  group('QA 三態結果', () {
    test('QaRetrievalResult 空＝insufficient', () {
      expect(const QaRetrievalResult([]).insufficientApprovedContent, true);
    });
    test('QaAskResult.pending 帶 id', () {
      final r = QaAskResult.pending('qid');
      expect(r.outcome, QaOutcome.pendingQuestionCreated);
      expect(r.pendingQuestionId, 'qid');
    });
    test('三種 outcome 齊全', () {
      expect(QaOutcome.values.toSet(), {
        QaOutcome.answered,
        QaOutcome.insufficientApprovedContent,
        QaOutcome.pendingQuestionCreated,
      });
    });
  });
}
