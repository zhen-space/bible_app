import 'package:bible_app/models/private_study.dart';
import 'package:bible_app/screens/private_study_screen.dart';
import 'package:bible_app/services/database_service.dart';
import 'package:bible_app/services/private_study_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecoveryPrivateStudyRepository extends PrivateStudyRepository {
  _RecoveryPrivateStudyRepository() : super(DatabaseService());

  bool failSearch = false;
  bool failDeletedBooks = false;
  int searchAttempts = 0;
  int deletedBookAttempts = 0;

  static const book = PrivateStudyBook(
    id: 'book-1',
    title: '信心之旅',
    createdAt: 1,
    updatedAt: 1,
    lastStudiedAt: 1,
  );

  static const note = PrivateStudyNote(
    id: 'note-1',
    bookId: 'book-1',
    quote: '刪除的摘錄',
    deletedAt: 10,
    createdAt: 1,
    updatedAt: 10,
  );

  @override
  Future<List<PrivateStudyBook>> getBooks({bool includeDeleted = false}) async {
    if (includeDeleted) {
      deletedBookAttempts += 1;
      if (failDeletedBooks) throw Exception('最近刪除書籍載入失敗');
    }
    return const [book];
  }

  @override
  Future<List<PrivateStudyNote>> getNotes({
    String? bookId,
    String? topic,
    bool includeDeleted = false,
  }) async => includeDeleted ? const [note] : const [];

  @override
  Future<List<PrivateStudyNote>> search({
    String query = '',
    String? bookId,
    String? topic,
    bool? hasScripture,
  }) async {
    searchAttempts += 1;
    if (failSearch) throw Exception('私人研讀搜尋失敗');
    return const [note];
  }
}

void main() {
  testWidgets('375px 搜尋結果失敗可重試並恢復', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = _RecoveryPrivateStudyRepository()..failSearch = true;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [privateStudyRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: PrivateStudySearchScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('研讀筆記暫時無法搜尋。'), findsOneWidget);
    expect(find.text('沒有符合的研讀筆記'), findsNothing);
    final attemptsBeforeRetry = repo.searchAttempts;

    repo.failSearch = false;
    await tester.tap(find.text('重試'));
    await tester.pumpAndSettle();

    expect(repo.searchAttempts, greaterThan(attemptsBeforeRetry));
    expect(find.text('刪除的摘錄'), findsOneWidget);
  });

  testWidgets('375px 最近刪除載入失敗可重試並恢復', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = _RecoveryPrivateStudyRepository()..failDeletedBooks = true;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [privateStudyRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: PrivateStudyDeletedScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('最近刪除暫時無法載入。'), findsOneWidget);
    expect(find.text('最近刪除目前是空的'), findsNothing);
    final attemptsBeforeRetry = repo.deletedBookAttempts;

    repo.failDeletedBooks = false;
    await tester.tap(find.text('重試'));
    await tester.pumpAndSettle();

    expect(repo.deletedBookAttempts, greaterThan(attemptsBeforeRetry));
    expect(find.text('刪除的摘錄'), findsOneWidget);
  });
}
