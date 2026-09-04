import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Teacher Area 入口只依 capability provider，不依 teaching count', () {
    final providers = File('lib/providers/providers.dart').readAsStringSync();
    final start = providers.indexOf('final teacherEntryVisibleProvider');
    final end = providers.indexOf('// Admin 老師專區。', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final entryContract = providers.substring(start, end);

    expect(entryContract, contains('hasTeacherAreaForActiveChurch'));
    expect(entryContract, isNot(contains('fetchAuthorizedBooks')));
    expect(entryContract, isNot(contains('fetchAuthorizedChapters')));
    expect(entryContract, isNot(contains('fetchAuthorizedTeachings')));
  });

  test('Bible Hub 只隱藏 Teacher Area tile；一般理解功能不受 Church state 影響', () {
    final hub = File('lib/screens/bible_hub_screen.dart').readAsStringSync();

    expect(
        hub, contains('ref.watch(teacherEntryVisibleProvider).value == true'));
    expect(hub, contains("'聖經／信仰問答'"));
    expect(hub, contains("'研讀內容'"));
    expect(hub, contains("'閱讀聖經'"));
    expect(hub, contains("'搜尋經文'"));
  });

  test('capability=true 但 0 authorized books 時仍有 Teacher Area empty state', () {
    final screen =
        File('lib/screens/teacher_area_screen.dart').readAsStringSync();

    expect(screen, contains('books.isEmpty'));
    expect(screen, contains('目前沒有可瀏覽的老師專區內容。'));
  });
}
