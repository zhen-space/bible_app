import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/models/church.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/services/content_workflow_service.dart';
import 'package:bible_app/services/study_content_repository.dart';

/// 種一個 published study_content（直接控 audience/church，繞過 workflow）。
Future<void> _seed(FakeFirebaseFirestore fs, String id,
    {required String audience, List<String> churches = const []}) async {
  await fs.collection('study_content').doc(id).set({
    'content_id': id,
    'content_type': 'topic_article',
    'status': 'published',
    'audience': audience,
    'allowed_church_ids': churches,
    'title': id,
    'topic_ids': const [],
    'data': const {},
    'version': 1,
  });
}

/// 已儲存內容 offline vs revoked 的三態辨識（spec item 10 / report 13,24）。
///  - item!=null            → 可開
///  - item==null && online  → **revoked/未授權**（顯示「目前無法存取」）
///  - item==null && !online → **無法驗證**（顯示「目前無法驗證教會存取權」；offline≠revoked）
void main() {
  ProviderContainer containerWith(
      FakeFirebaseFirestore fs, bool online, StudentAuth auth) {
    return ProviderContainer(overrides: [
      firebaseReadyProvider.overrideWithValue(online),
      savedStudyContentIdsProvider
          .overrideWith((ref) async => const ['pub', 'chB']),
      myAuthProvider.overrideWith((ref) async => auth),
      studyContentRepositoryProvider.overrideWithValue(
          StudyContentRepository(fs, ContentWorkflowService(fs))),
    ]);
  }

  test('online + 未授權 church 內容 → online:true, item:null（revoked/無存取）', () async {
    final fs = FakeFirebaseFirestore();
    await _seed(fs, 'pub', audience: 'public');
    await _seed(fs, 'chB', audience: 'church', churches: ['B']); // 只有 B 教會可讀
    // active A：pub 可讀、chB 不可讀（未授權，但線上已確認）。
    final c = containerWith(fs, true, const StudentAuth('A'));
    final rows = await c.read(resolvedSavedStudyContentProvider.future);
    final byId = {for (final r in rows) r.id: r};
    expect(byId['pub']!.item, isNotNull);
    expect(byId['pub']!.online, isTrue);
    expect(byId['chB']!.item, isNull);
    expect(byId['chB']!.online, isTrue); // 線上確認未授權 → 「目前無法存取」
    c.dispose();
  });

  test('offline → 全部 item:null, online:false（無法驗證，非 revoked）', () async {
    final fs = FakeFirebaseFirestore();
    await _seed(fs, 'pub', audience: 'public');
    await _seed(fs, 'chB', audience: 'church', churches: ['B']);
    final c = containerWith(fs, false, const StudentAuth('A'));
    final rows = await c.read(resolvedSavedStudyContentProvider.future);
    expect(rows.every((r) => r.item == null), isTrue);
    expect(rows.every((r) => r.online == false), isTrue); // → 「目前無法驗證教會存取權」
    c.dispose();
  });

  test('online + active B → 自己教會內容可開', () async {
    final fs = FakeFirebaseFirestore();
    await _seed(fs, 'pub', audience: 'public');
    await _seed(fs, 'chB', audience: 'church', churches: ['B']);
    final c = containerWith(fs, true, const StudentAuth('B'));
    final rows = await c.read(resolvedSavedStudyContentProvider.future);
    final byId = {for (final r in rows) r.id: r};
    expect(byId['chB']!.item, isNotNull); // B 授權 → 可開
    expect(byId['chB']!.online, isTrue);
    c.dispose();
  });
}
