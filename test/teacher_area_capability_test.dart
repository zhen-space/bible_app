import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Bible Hub 不再提供 Teacher Area Student 入口', () {
    final hub = File('lib/screens/bible_hub_screen.dart').readAsStringSync();

    expect(hub, isNot(contains("'老師專區'")));
    expect(hub, isNot(contains('TeacherAreaScreen')));
    expect(hub, contains("'書卷／章節導讀'"));
    expect(hub, contains("'聖經／信仰問答'"));
    expect(hub, contains("'研讀內容'"));
    expect(hub, contains("'我的研讀'"));
  });

  test('Admin 不再提供 Teacher Books / Chapters 管理 UI（產品功能退休）', () {
    // Admin Teacher Area 畫面與 provider 已刪；Dashboard 不再有老師專區入口，
    // 「教會與教師」section 改名「教會管理」，但教會/會籍管理入口保留。
    expect(File('lib/screens/admin_teacher_screen.dart').existsSync(), isFalse);
    expect(File('lib/models/teacher.dart').existsSync(), isFalse);
    final dash = File('lib/screens/admin_dashboard_screen.dart').readAsStringSync();
    expect(dash, isNot(contains('老師專區書卷')));
    expect(dash, isNot(contains('AdminTeacherBooksScreen')));
    expect(dash, isNot(contains('admin_teacher_screen.dart')));
    expect(dash, contains('教會管理'));
    // 教會 / 會籍管理入口保留。
    expect(dash, contains('AdminChurchesScreen'));
    expect(dash, contains('AdminMembershipRequestsScreen'));
    final providers = File('lib/providers/providers.dart').readAsStringSync();
    expect(providers, isNot(contains('adminTeacherBooksProvider')));
    expect(providers, isNot(contains('authorizedTeacherBooksProvider')));
    expect(providers, isNot(contains('teacherRepositoryProvider')));
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
