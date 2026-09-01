import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/models/knowledge.dart';
import 'package:bible_app/models/managed_content.dart';
import 'package:bible_app/models/study_content.dart';

void main() {
  group('Visibility enum (fail-closed)', () {
    test('fromName 正確值', () {
      expect(Visibility.fromName('internal'), Visibility.internal);
      expect(Visibility.fromName('student'), Visibility.student);
    });
    test('未知／缺失 → null（不得預設成 student）', () {
      expect(Visibility.fromName(null), isNull);
      expect(Visibility.fromName(''), isNull);
      expect(Visibility.fromName('public'), isNull);
      expect(Visibility.fromName('STUDENT'), isNull);
    });
  });

  group('StudyContentType enum (fail-closed)', () {
    test('wire 值', () {
      expect(StudyContentType.parallel.wire, 'parallel');
      expect(StudyContentType.topicArticle.wire, 'topic_article');
    });
    test('fromWire 未知 → null（不接受自由字串）', () {
      expect(StudyContentType.fromWire('parallel'), StudyContentType.parallel);
      expect(StudyContentType.fromWire('topic_article'),
          StudyContentType.topicArticle);
      expect(StudyContentType.fromWire('bogus'), isNull);
      expect(StudyContentType.fromWire(null), isNull);
    });
  });

  group('StudyContentItem visibility contract', () {
    StudyContentItem item(ContentStatus s, Visibility? v) => StudyContentItem(
          id: 'x',
          status: s,
          visibility: v,
          contentType: StudyContentType.parallel,
        );
    test('只有 published + student 才 student-visible', () {
      expect(item(ContentStatus.published, Visibility.student).isStudentVisible,
          isTrue);
    });
    test('published + internal 不可見', () {
      expect(item(ContentStatus.published, Visibility.internal).isStudentVisible,
          isFalse);
    });
    test('draft/review/rejected/archived + student 皆不可見', () {
      for (final s in [
        ContentStatus.draft,
        ContentStatus.review,
        ContentStatus.rejected,
        ContentStatus.archived,
      ]) {
        expect(item(s, Visibility.student).isStudentVisible, isFalse,
            reason: '$s + student 不得可見');
      }
    });
    test('缺 visibility（null）不可見（fail-closed）', () {
      expect(item(ContentStatus.published, null).isStudentVisible, isFalse);
    });
  });

  group('StudyContentItem round-trip（含 visibility 進出 doc）', () {
    test('toManaged/fromDoc 保留欄位與 visibility', () {
      const it = StudyContentItem(
        id: 'parallel__abc',
        status: ContentStatus.published,
        visibility: Visibility.student,
        contentType: StudyContentType.parallel,
        title: '四福音對觀',
        body: '說明',
        scriptureRefs: ['太1:1', '路1:1'],
        topicIds: ['gospel'],
        tags: ['對觀'],
        version: 2,
        data: {'refs': ['太1:1', '路1:1']},
      );
      // 模擬寫入 doc（flat）：meta 併 payload 於頂層。
      final managed = it.toManaged();
      final flat = {
        ...managed.payload,
        'content_id': managed.contentId,
        'content_type': managed.contentType,
        'status': managed.status.name,
        'version': managed.version,
        'visibility': managed.visibility!.name,
        'provenance': managed.provenance.toMap(),
      };
      final back = StudyContentItem.fromDoc('parallel__abc', flat);
      expect(back.id, 'parallel__abc');
      expect(back.status, ContentStatus.published);
      expect(back.visibility, Visibility.student);
      expect(back.contentType, StudyContentType.parallel);
      expect(back.title, '四福音對觀');
      expect(back.scriptureRefs, ['太1:1', '路1:1']);
      expect(back.topicIds, ['gospel']);
      expect(back.data['refs'], ['太1:1', '路1:1']);
      expect(back.isStudentVisible, isTrue);
    });

    test('doc 缺 visibility → 解析為 null → 不可見（fail-closed）', () {
      final back = StudyContentItem.fromDoc('x', {
        'content_id': 'x',
        'content_type': 'parallel',
        'status': 'published',
        'version': 1,
        'title': 't',
        // 無 visibility 欄位
      });
      expect(back.visibility, isNull);
      expect(back.isStudentVisible, isFalse);
    });

    test('doc 未知 content_type → null（fail-closed）', () {
      final back = StudyContentItem.fromDoc('x', {
        'content_id': 'x',
        'content_type': 'wat',
        'status': 'published',
        'visibility': 'student',
      });
      expect(back.contentType, isNull);
    });
  });

  group('ManagedContent visibility 序列化（不污染其他型別）', () {
    test('visibility=null → toMap 不含 visibility 欄位', () {
      const c = ManagedContent(
        contentId: 'a',
        status: ContentStatus.published,
        version: 1,
        createdAt: 0,
        createdBy: '',
        updatedAt: 0,
        updatedBy: '',
      );
      expect(c.toMap().containsKey('visibility'), isFalse);
    });
    test('visibility 非 null → toMap/ fromMap round-trip', () {
      const c = ManagedContent(
        contentId: 'a',
        status: ContentStatus.published,
        version: 1,
        createdAt: 0,
        createdBy: '',
        updatedAt: 0,
        updatedBy: '',
        visibility: Visibility.internal,
      );
      final back = ManagedContent.fromMap('a', c.toMap());
      expect(back.visibility, Visibility.internal);
    });
  });

  group('FNV-1a-64 跨語言向量（必須與 tools/migrate_knowledge.mjs 一致）', () {
    test('"abc" → e71fa2190541574b', () {
      expect(StudyContentMigration.fnv1a64('abc'), 'e71fa2190541574b');
    });
  });

  group('Legacy → Study Content migration mapping', () {
    final kb = KnowledgeBase.fromJson({
      'parallels': [
        {
          'title': '甲',
          'refs': ['創1:1', '約1:1']
        }
      ],
      'types': [
        {'title': '逾越節', 'otRef': '出12:1', 'ntRef': '林前5:7', 'note': '基督是逾越節羔羊'}
      ],
      'timeline': [
        {'order': 1, 'era': '族長', 'title': '亞伯拉罕蒙召', 'when': '約主前2000', 'ref': '創12:1'}
      ],
      'people': [
        {
          'id': 'moses',
          'name': '摩西',
          'bio': '領袖',
          'events': [
            {'title': '出埃及', 'ref': '出14:1'}
          ],
        }
      ],
    });

    test('全部 migrated item visibility 永遠 internal（不論 aggregate 狀態）', () {
      for (final published in [true, false]) {
        final items =
            StudyContentMigration.fromKnowledgeBase(kb, aggregatePublished: published);
        expect(items, isNotEmpty);
        expect(items.every((i) => i.visibility == Visibility.internal), isTrue,
            reason: 'aggregatePublished=$published 時仍須全 internal');
        expect(items.every((i) => !i.isStudentVisible), isTrue,
            reason: 'migrated 內容絕不得學生可見');
      }
    });

    test('deterministic / idempotent：兩次映射 id 完全相同', () {
      final a = StudyContentMigration.fromKnowledgeBase(kb, aggregatePublished: true)
          .map((i) => i.id)
          .toList();
      final b = StudyContentMigration.fromKnowledgeBase(kb, aggregatePublished: true)
          .map((i) => i.id)
          .toList();
      expect(a, b);
      // 人物沿用 legacy stable id
      expect(a.contains('person__moses'), isTrue);
      // 型別前綴
      expect(a.any((id) => id.startsWith('parallel__')), isTrue);
      expect(a.any((id) => id.startsWith('type__')), isTrue);
      expect(a.any((id) => id.startsWith('timeline__')), isTrue);
    });

    test('aggregate published → items published/version1；否則 draft/version0', () {
      final pub = StudyContentMigration.fromKnowledgeBase(kb, aggregatePublished: true);
      expect(pub.every((i) => i.status == ContentStatus.published), isTrue);
      expect(pub.every((i) => i.version == 1), isTrue);
      final draft =
          StudyContentMigration.fromKnowledgeBase(kb, aggregatePublished: false);
      expect(draft.every((i) => i.status == ContentStatus.draft), isTrue);
      expect(draft.every((i) => i.version == 0), isTrue);
    });

    test('provenance 記錄 migrated_legacy + 類別', () {
      final items = StudyContentMigration.fromKnowledgeBase(kb, aggregatePublished: true);
      final person = items.firstWhere((i) => i.id == 'person__moses');
      expect(person.provenance.source, 'migrated_legacy');
      expect(person.provenance.note.contains('people'), isTrue);
      expect(person.provenance.note.contains('knowledge/data'), isTrue);
    });
  });
}
