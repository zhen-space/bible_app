import 'package:bible_app/models/church.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/screens/admin_church_screen.dart';
import 'package:bible_app/services/church_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('新增 Church 可開啟老師專區並只寫 private capability', (tester) async {
    final fs = FakeFirebaseFirestore();
    final repo = ChurchRepository(fs);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          churchRepositoryProvider.overrideWithValue(repo),
          adminAllChurchesProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: AdminChurchesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('新增教會'));
    await tester.pumpAndSettle();
    expect(find.text('老師專區'), findsOneWidget);
    final initial = tester.widget<SwitchListTile>(
      find.byKey(const Key('church-teacher-area-switch')),
    );
    expect(initial.value, isFalse);

    await tester.enterText(find.byType(TextField).at(0), 'new-church');
    await tester.enterText(find.byType(TextField).at(1), '新教會');
    await tester.tap(find.byKey(const Key('church-teacher-area-switch')));
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();

    final private = await fs
        .collection('churches')
        .doc('new-church')
        .collection('private')
        .doc('capabilities')
        .get();
    expect(private.data()?['teacher_area'], isTrue);
    final public = await fs.collection('churches').doc('new-church').get();
    expect(public.data()?['teacher_area'], isNull);
  });

  testWidgets('編輯 Church 從 private capability 載入老師專區狀態', (tester) async {
    final fs = FakeFirebaseFirestore();
    final repo = ChurchRepository(fs);
    const church = Church(id: 'a', name: 'A教會', active: true);
    await repo.saveChurch(church);
    await repo.saveChurchCapabilities(
      const ChurchCapabilities(churchId: 'a', teacherArea: true),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          churchRepositoryProvider.overrideWithValue(repo),
          adminAllChurchesProvider.overrideWith((ref) async => const [church]),
        ],
        child: const MaterialApp(home: AdminChurchesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('A教會'));
    await tester.pumpAndSettle();
    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const Key('church-teacher-area-switch')),
    );
    expect(toggle.value, isTrue);

    await tester.tap(find.byKey(const Key('church-teacher-area-switch')));
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();
    expect((await repo.fetchChurchCapabilities('a')).teacherArea, isFalse);
  });
}
