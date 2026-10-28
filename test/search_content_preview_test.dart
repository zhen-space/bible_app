import 'package:bible_app/models/models.dart';
import 'package:bible_app/models/study_content.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/screens/search_screen.dart';
import 'package:bible_app/services/bible_repository.dart';
import 'package:bible_app/services/database_service.dart';
import 'package:bible_app/services/qa_service.dart';
import 'package:bible_app/services/related_verse_search.dart';
import 'package:flutter/material.dart' hide Visibility;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _EmptySearchBibleRepository extends BibleRepository {
  @override
  Future<List<Book>> loadBooks() async => const [];

  @override
  List<VerseSearchHit> searchRelated(String query, {int limit = 100}) =>
      const [];
}

class _PreviewDatabaseService extends DatabaseService {
  @override
  Future<List<Bookmark>> getAllBookmarks() async => const [];
}

void main() {
  testWidgets('375px 中文多詞結果顯示命中句並保留內容標籤', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const content = StudyContentItem(
      id: 'peace',
      status: ContentStatus.published,
      visibility: Visibility.student,
      contentType: StudyContentType.topicArticle,
      title: '患難中的操練',
      body: '即使在患難中仍有平安。可以用禱告交託憂慮。',
      audience: Audience.church,
    );
    const question = Question(
      id: 'q1',
      uid: 'u1',
      author: '作者',
      title: '如何面對憂慮？',
      body: '先尋求從神而來的平安。再以禱告交託。',
      category: '信仰',
      status: 'approved',
      published: true,
      featured: false,
      createdAt: 0,
      updatedAt: 0,
      answer: null,
      answerVersions: [],
      audience: Audience.public,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bibleRepositoryProvider.overrideWithValue(
            _EmptySearchBibleRepository(),
          ),
          booksProvider.overrideWith((ref) async => const <Book>[]),
          databaseServiceProvider.overrideWithValue(_PreviewDatabaseService()),
          authorizedStudyContentProvider.overrideWith(
            (ref) async => const [content],
          ),
          publishedQuestionsProvider(
            '',
          ).overrideWith((ref) async => const [question]),
          allBookmarksProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: SearchScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '平安，禱告');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('主題研讀・教會專屬'), findsOneWidget);
    expect(find.textContaining('即使在患難中仍有平安。'), findsOneWidget);
    expect(find.textContaining('聖經／信仰問答'), findsOneWidget);
    expect(find.textContaining('先尋求從神而來的平安。'), findsOneWidget);
  });
}
