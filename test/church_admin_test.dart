import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/models/church.dart';
import 'package:bible_app/services/church_repository.dart';

void main() {
  // Teacher Area 產品功能已退休：原「Admin Teacher repository」group（TeacherRepository
  // saveBook/saveChapter/adminList）已移除，TeacherRepository 本身已刪。

  group('Admin Church repository', () {
    test('saveChurch / fetchAllChurches / setChurchActive', () async {
      final fs = FakeFirebaseFirestore();
      final repo = ChurchRepository(fs);
      await repo.saveChurch(const Church(id: 'a', name: 'A教會', active: false));
      await repo.saveChurch(const Church(id: 'b', name: 'B教會', active: true));
      expect((await repo.fetchAllChurches()).length, 2);
      expect((await repo.fetchActiveChurches()).map((c) => c.id), ['b']);
      await repo.setChurchActive('a', true);
      expect((await repo.fetchActiveChurches()).map((c) => c.id).toSet(), {
        'a',
        'b',
      });
      // saveChurch 只寫公開欄位（無 private 混入）。
      final doc = await fs.collection('churches').doc('a').get();
      expect(doc.data()!.containsKey('name'), isTrue);
      expect(doc.data()!.containsKey('members'), isFalse);
    });

    test(
      'saveChurchCapabilities 寫 private doc，缺 teacher_area 預設 false',
      () async {
        final fs = FakeFirebaseFirestore();
        final repo = ChurchRepository(fs);
        await repo.saveChurchCapabilities(
          const ChurchCapabilities(churchId: 'a', teacherArea: true),
        );
        final doc = await fs
            .collection('churches')
            .doc('a')
            .collection('private')
            .doc('capabilities')
            .get();
        expect(doc.data(), {'teacher_area': true});
        expect(ChurchCapabilities.fromDoc('a', const {}).teacherArea, isFalse);
        expect(
          ChurchCapabilities.fromDoc('a', const {
            'teacher_area': 'true',
          }).teacherArea,
          isFalse,
        );
      },
    );

    test('fetchChurchCapabilities 只讀 private doc，缺文件／欄位預設 false', () async {
      final fs = FakeFirebaseFirestore();
      final repo = ChurchRepository(fs);

      expect(
        (await repo.fetchChurchCapabilities('missing')).teacherArea,
        isFalse,
      );
      await fs
          .collection('churches')
          .doc('a')
          .collection('private')
          .doc('capabilities')
          .set({'some_future_capability': true});
      expect((await repo.fetchChurchCapabilities('a')).teacherArea, isFalse);

      await repo.saveChurchCapabilities(
        const ChurchCapabilities(churchId: 'a', teacherArea: true),
      );
      expect((await repo.fetchChurchCapabilities('a')).teacherArea, isTrue);
      final public = await fs.collection('churches').doc('a').get();
      expect(public.data()?['teacher_area'], isNull);
    });

    test(
      'requestMembership → pending；pendingMemberships 佇列；approve→active',
      () async {
        final fs = FakeFirebaseFirestore();
        final repo = ChurchRepository(fs);
        await repo.saveChurch(const Church(id: 'a', active: true));
        await repo.requestMembership('u1', 'a');
        expect((await repo.pendingMemberships()).map((m) => m.uid), ['u1']);
        await repo.approveMembership('u1', 'admin@e.com');
        expect(await repo.pendingMemberships(), isEmpty);
        final m = await repo.fetchMembership('u1');
        expect(m!.status, MembershipStatus.active);
        expect(m.activeChurchId, 'a');
        // 稽核 history 有一筆。
        final hist = await fs
            .collection('memberships')
            .doc('u1')
            .collection('history')
            .get();
        expect(hist.docs.length, 1);
        expect(hist.docs.first.data()['to'], 'active');
      },
    );
  });
}
