import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Home 提供既有 Q&A 與研讀內容入口，且不加入禁止的快捷入口', () {
    final home = File(
      'lib/screens/student_home_screen.dart',
    ).readAsStringSync();

    expect(home, contains("'聖經／信仰問答'"));
    expect(home, contains('const QaScreen()'));
    expect(home, contains("'研讀內容'"));
    expect(home, contains('const StudentStudyContentScreen()'));

    expect(home, isNot(contains("'老師專區'")));
    expect(home, isNot(contains("'AI解經'")));
    expect(home, isNot(contains("'問AI'")));
  });
}
