import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Bible Hub 老師專區入口存在，且由 teacherEntryVisibleProvider（capability）把關', () {
    final hub = File('lib/screens/bible_hub_screen.dart').readAsStringSync();

    // Student Teacher Area 入口已補回；但必須以既有 capability provider 為唯一 gate。
    expect(hub, contains("'老師專區'"));
    expect(hub, contains('TeacherAreaScreen'));
    expect(hub, contains('teacherEntryVisibleProvider'));
    // 其餘理解區入口不變。
    expect(hub, contains("'書卷／章節導讀'"));
    expect(hub, contains("'聖經／信仰問答'"));
    expect(hub, contains("'研讀內容'"));
    expect(hub, contains("'我的研讀'"));
  });

  test('Teacher capability shared authorization infrastructure 不因 UI 移除而刪除', () {
    final providers = File('lib/providers/providers.dart').readAsStringSync();
    final qa = File('lib/services/qa_service.dart').readAsStringSync();

    // 現行 backend/Q&A contract 仍可能依 capability 保護既有 Church-scoped source；
    // 這是 shared authorization infrastructure，不是 Student Teacher Area UI。
    expect(providers, contains('teacherEntryVisibleProvider'));
    expect(providers, contains('hasTeacherAreaForActiveChurch'));
    expect(qa, contains('activeChurchHasTeacherArea'));
  });

  test('Search 不再向 Student 呈現 Teacher Area organization context', () {
    final search = File('lib/screens/search_screen.dart').readAsStringSync();
    expect(search, isNot(contains("'老師專區'")));
    expect(search, contains('authorizedStudyContentProvider'));
  });
}
