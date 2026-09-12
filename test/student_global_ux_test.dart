import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bible_app/models/models.dart';
import 'package:bible_app/widgets/scripture_reference_field.dart';
import 'package:bible_app/widgets/student_ux.dart';

List<Book> _books() => [
      Book(
        id: 1,
        name: '約翰福音',
        abbr: '約',
        testament: 'nt',
        chapters: [
          ['a'],
          ['a'],
          List.generate(36, (i) => 'v${i + 1}'),
        ],
      ),
      Book(
        id: 2,
        name: '羅馬書',
        abbr: '羅',
        testament: 'nt',
        chapters: List.generate(5, (c) => List.generate(20, (v) => 'v')),
      ),
      Book(
        id: 3,
        name: '約翰一書',
        abbr: '約一',
        testament: 'nt',
        chapters: List.generate(4, (c) => List.generate(20, (v) => 'v')),
      ),
    ];

void main() {
  group('selection mode', () {
    test('單選 / 多選 / 全選 / 取消', () {
      final s = SelectionController<String>();
      s.start('a');
      expect(s.active, isTrue);
      expect(s.selected, {'a'});
      s.toggle('b');
      expect(s.selected, {'a', 'b'});
      s.selectAll(['a', 'b', 'c']);
      expect(s.selected, {'a', 'b', 'c'});
      s.cancel();
      expect(s.active, isFalse);
      expect(s.selected, isEmpty);
      s.dispose();
    });
  });

  group('Scripture parsing', () {
    test('manual single verse', () {
      final r = parseScriptureReference('約翰福音 3:16', _books());
      expect(r, isNotNull);
      expect(r!.bookId, 1);
      expect(r.chapter, 3);
      expect(r.startVerse, 16);
      expect(r.endVerse, isNull);
    });

    test('continuous range with en dash', () {
      final r = parseScriptureReference('約翰一書 4:7–8', _books());
      expect(r, isNotNull);
      expect(r!.bookId, 3);
      expect(r.chapter, 4);
      expect(r.startVerse, 7);
      expect(r.endVerse, 8);
    });

    test('range with hyphen and multiple independent references', () {
      final values = [
        parseScriptureReference('約翰福音 3:16-18', _books()),
        parseScriptureReference('羅馬書 5:8', _books()),
      ];
      expect(values.every((v) => v != null), isTrue);
      expect(values[0]!.endVerse, 18);
      expect(values[1]!.startVerse, 8);
    });

    test('invalid Scripture never creates a reference', () {
      expect(parseScriptureReference('約翰福音 3:99', _books()), isNull);
      expect(parseScriptureReference('不存在 3:16', _books()), isNull);
      expect(parseScriptureReference('約翰福音 3:18-16', _books()), isNull);
    });

    test('picker value formats single and range output', () {
      const single = ScriptureReferenceValue(bookId: 1, chapter: 3, startVerse: 16);
      const range = ScriptureReferenceValue(bookId: 1, chapter: 3, startVerse: 16, endVerse: 18);
      expect(single.label(_books()), '約翰福音 3:16');
      expect(range.label(_books()), '約翰福音 3:16–18');
    });
  });

  test('row swipe invokes action but never hard-dismisses by gesture', () {
    final source = File('lib/widgets/student_ux.dart').readAsStringSync();
    expect(source, contains('confirmDismiss'));
    expect(source, contains('return false;'));
    expect(source, contains('dismissThresholds'));
  });

  test('batch delete follows existing personal-data delete contracts', () {
    final notes = File('lib/screens/notes_screen.dart').readAsStringSync();
    final study = File('lib/screens/private_study_screen.dart').readAsStringSync();
    final todos = File('lib/screens/todos_screen.dart').readAsStringSync();
    expect(notes, contains('softDeleteNoteById'));
    expect(study, contains('softDeleteNote'));
    expect(todos, contains('deleteTodo'));
    expect(notes, isNot(contains('purgeNote(note.id')));
  });

  test('batch copy is human-readable, never JSON/internal path', () {
    final ux = File('lib/widgets/student_ux.dart').readAsStringSync();
    final study = File('lib/screens/private_study_screen.dart').readAsStringSync();
    expect(ux, contains('joinHumanReadable'));
    expect(study, contains('privateStudyNoteHumanReadable'));
    expect(study, contains('我的整理／心得：'));
    expect(study, contains('對應經文：'));
    expect(study, isNot(contains('Firestore path')));
  });

  test('Scripture click uses existing AppLinks temporary Reader contract', () {
    final field = File('lib/widgets/scripture_reference_field.dart').readAsStringSync();
    final links = File('lib/services/app_links.dart').readAsStringSync();
    expect(field, contains('AppLinks.openVerseRef'));
    expect(links, contains('updateReadingPosition: false'));
  });

  test('temporary Reader swipe preserves reading-position guard', () {
    final reader = File('lib/screens/chapter_screen.dart').readAsStringSync();
    expect(reader, contains('onHorizontalDragEnd'));
    expect(reader, contains('_turn(books, 1)'));
    expect(reader, contains('_turn(books, -1)'));
    expect(reader, contains('if (widget.updateReadingPosition)'));
    expect(reader, contains('lastReadProvider.notifier'));
  });

  test('normal Reader navigation contract remains present', () {
    final reader = File('lib/screens/chapter_screen.dart').readAsStringSync();
    expect(reader, contains('void _goTo(int bookId, int chapter)'));
    expect(reader, contains('void _turn(List<Book> books, int delta)'));
    expect(reader, contains('_logRead();'));
  });

  test('edge-back uses native/platform route path; row swipe does not implement global back', () {
    final route = File('lib/navigation/student_page_route.dart').readAsStringSync();
    final row = File('lib/widgets/student_ux.dart').readAsStringSync();
    expect(route, contains('CupertinoPageRoute'));
    expect(route, contains('MaterialPageRoute'));
    expect(row, isNot(contains('Navigator.pop')));
  });

  test('production-facing list errors do not render raw exception text in touched pages', () {
    for (final path in [
      'lib/screens/todos_screen.dart',
      'lib/screens/prayers_screen.dart',
      'lib/screens/notes_screen.dart',
      'lib/screens/bookmarks_screen.dart',
      'lib/screens/my_content_screen.dart',
      'lib/screens/sermon_notes_screen.dart',
      'lib/screens/private_study_screen.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src, isNot(contains('載入失敗：$e')), reason: path);
      expect(src, isNot(contains('error: (e, _) => Center')), reason: path);
    }
  });

  test('Teacher Area stays retired and Church/Q&A/Study Content contracts remain', () {
    expect(File('lib/screens/teacher_area_screen.dart').existsSync(), isFalse);
    expect(File('lib/services/church_repository.dart').existsSync(), isTrue);
    expect(File('lib/services/qa_service.dart').existsSync(), isTrue);
    expect(File('lib/services/study_content_repository.dart').existsSync(), isTrue);
    final hub = File('lib/screens/bible_hub_screen.dart').readAsStringSync();
    expect(hub, isNot(contains('老師專區')));
  });
}
