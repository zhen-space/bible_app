import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/entities.dart';
import '../models/models.dart';
import '../models/study_content.dart';
import '../providers/providers.dart';
import '../services/qa_service.dart';
import '../services/related_verse_search.dart';
import '../services/verse_locator.dart';
import '../utils/text_utils.dart';
import '../widgets/student_ux.dart';
import 'chapter_screen.dart';
import 'qa_screen.dart' show QuestionDetailScreen;
import 'study_content_screen.dart';

/// 全文搜尋 + 節位快速跳轉（約3:16）+ 搜尋歷史。
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  List<VerseSearchHit> _results = [];
  // 「內容」＝授權後的 Study Content + Q&A。
  // Teacher Books/Chapters 已不再是 Student product surface；Study Content 本體仍照常可搜尋。
  List<StudyContentItem> _content = [];
  List<Question> _qa = [];
  List<BibleEntity> _entities = [];
  ({int bookId, int chapter, int? verse})? _jump;
  bool _searched = false;
  bool _searching = false;
  String? _searchError;
  int _searchRequest = 0;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      _clearSearch();
      return;
    }
    // 使用者一輸入新字就讓前一筆請求失效，不讓舊結果在 debounce 期間閃回畫面。
    final request = ++_searchRequest;
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _search(q, request: request),
    );
  }

  Future<void> _search(String q, {int? request}) async {
    final term = q.trim();
    if (term.isEmpty) {
      _clearSearch();
      return;
    }
    final currentRequest = request ?? ++_searchRequest;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final books = await ref.read(booksProvider.future);
      // 「內容」＝**已授權 universe FIRST**（public ∪ my-church）→ 再 client 端文字比對。
      // church B 從未進 universe，故 count/title/preview 皆不含（rules-not-filter 契約）。
      final universe = await ref.read(authorizedStudyContentProvider.future);
      final questions = await ref.read(publishedQuestionsProvider('').future);
      if (!mounted || currentRequest != _searchRequest) return;
      setState(() {
        _jump = VerseLocator.parse(q, books);
        _entities = searchEntities(q);
        _content = universe
            .where(
              (i) => matchesAllQueryTerms(term, [
                i.title,
                i.body,
                ...i.tags,
                ...i.scriptureRefs,
              ]),
            )
            .toList();
        _qa = questions
            .where(
              (question) => matchesAllQueryTerms(
                term,
                [question.title, question.body],
              ),
            )
            .toList();
        _results = ref
            .read(bibleRepositoryProvider)
            .searchRelated(q)
            .where((hit) => !queryOnlyInsideLongerName(hit.verse.text, term))
            .toList();
        _searched = true;
      });
    } catch (_) {
      if (!mounted || currentRequest != _searchRequest) return;
      setState(() => _searchError = '搜尋暫時無法完成');
    } finally {
      if (mounted && currentRequest == _searchRequest) {
        setState(() => _searching = false);
      }
    }
  }

  void _clearSearch() {
    _searchRequest++;
    if (!mounted) return;
    setState(() {
      _results = [];
      _content = [];
      _qa = [];
      _entities = [];
      _jump = null;
      _searched = false;
      _searching = false;
      _searchError = null;
    });
  }

  void _openChapter(int bookId, int chapter, {int? verse}) {
    // 有實際打開結果才記進搜尋歷史
    ref.read(searchHistoryProvider.notifier).add(_controller.text);
    Navigator.push(
      context,
      MaterialPageRoute(
        // 搜尋結果＝臨時瀏覽，不更新一般 Reading Position
        builder: (_) => ChapterScreen(
          bookId: bookId,
          chapter: chapter,
          focusVerse: verse,
          updateReadingPosition: false,
        ),
      ),
    );
  }

  Future<void> _copyVerse(Book book, VerseRef verse) => copyHumanReadable(
    context,
    '${verse.text}\n${book.name} ${verse.chapter}:${verse.verse}',
    success: '已複製 ${book.name} ${verse.chapter}:${verse.verse}',
  );

  Future<void> _toggleBookmark(VerseRef verse, bool bookmarked) async {
    await ref
        .read(databaseServiceProvider)
        .toggleBookmark(verse.bookId, verse.chapter, verse.verse);
    ref.invalidate(allBookmarksProvider);
    ref.invalidate(chapterMarksProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(bookmarked ? '已移除書籤' : '已加入書籤')));
  }

  void _showVerseActions(Book book, VerseRef verse, bool bookmarked) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('開啟經文'),
            subtitle: Text('${book.name} ${verse.chapter}:${verse.verse}'),
            onTap: () {
              Navigator.pop(sheetContext);
              _openChapter(verse.bookId, verse.chapter, verse: verse.verse);
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: const Text('複製經文'),
            onTap: () {
              Navigator.pop(sheetContext);
              _copyVerse(book, verse);
            },
          ),
          ListTile(
            leading: Icon(
              bookmarked ? Icons.bookmark_remove : Icons.bookmark_add_outlined,
            ),
            title: Text(bookmarked ? '移除書籤' : '加入書籤'),
            onTap: () {
              Navigator.pop(sheetContext);
              _toggleBookmark(verse, bookmarked);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final booksAsync = ref.watch(booksProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜尋經文，或輸入「約3:16」直接跳轉',
            border: InputBorder.none,
          ),
          onChanged: _onQueryChanged,
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                _clearSearch();
              },
            ),
        ],
        bottom: _searching
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: booksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _SearchError(
          label: '聖經資料暫時無法載入',
          onRetry: () => ref.invalidate(booksProvider),
        ),
        data: (books) {
          final bookmarkKeys = {
            for (final bookmark
                in ref.watch(allBookmarksProvider).value ?? const <Bookmark>[])
              '${bookmark.bookId}:${bookmark.chapter}:${bookmark.verse}',
          };
          if (_searchError != null) {
            return _SearchError(
              label: _searchError!,
              onRetry: () => _search(_controller.text),
            );
          }
          if (!_searched) {
            return _HistoryView(
              onTap: (q) {
                _controller.text = q;
                _search(q);
              },
            );
          }
          if (_jump == null &&
              _results.isEmpty &&
              _content.isEmpty &&
              _qa.isEmpty &&
              _entities.isEmpty) {
            return const Center(child: Text('沒有找到符合的結果'));
          }
          return ListView(
            children: [
              if (_jump != null)
                _JumpTile(
                  jump: _jump!,
                  book: books[_jump!.bookId - 1],
                  onTap: () => _openChapter(
                    _jump!.bookId,
                    _jump!.chapter,
                    verse: _jump!.verse,
                  ),
                ),
              if (_content.isNotEmpty) ...[
                const _SectionLabel('內容'),
                for (final i in _content)
                  ListTile(
                    leading: const Icon(Icons.auto_stories_outlined),
                    title: Text(i.title.isEmpty ? '(未命名)' : i.title),
                    subtitle: Text(
                      [
                        studyTypeLabel(i.contentType),
                        if (i.audience == Audience.church) '教會專屬',
                      ].join('・'),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StudentStudyContentDetail(item: i),
                      ),
                    ),
                  ),
              ],
              if (_qa.isNotEmpty) ...[
                const _SectionLabel('問答'),
                for (final question in _qa)
                  ListTile(
                    leading: const Icon(Icons.forum_outlined),
                    title: Text(question.title),
                    subtitle: const Text('聖經／信仰問答'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => QuestionDetailScreen(id: question.id),
                      ),
                    ),
                  ),
              ],
              if (_entities.isNotEmpty) ...[
                const _SectionLabel('人物・地點・事件'),
                for (final e in _entities)
                  ListTile(
                    leading: Icon(_entityIcon(e.type)),
                    title: Text(e.name),
                    subtitle: Text('${entityTypeLabel(e.type)}　找出全部出現處'),
                    onTap: () {
                      _controller.text = e.name;
                      _search(e.name);
                    },
                  ),
              ],
              if (_results.any((hit) => hit.isExact)) const _SectionLabel('經文'),
              for (final hit in _results.where((hit) => hit.isExact))
                _VerseResultTile(
                  hit: hit,
                  books: books,
                  query: _controller.text.trim(),
                  bookmarked: bookmarkKeys.contains(
                    '${hit.verse.bookId}:${hit.verse.chapter}:${hit.verse.verse}',
                  ),
                  onTap: () => _openChapter(
                    hit.verse.bookId,
                    hit.verse.chapter,
                    verse: hit.verse.verse,
                  ),
                  onCopy: () =>
                      _copyVerse(books[hit.verse.bookId - 1], hit.verse),
                  onBookmark: (bookmarked) =>
                      _toggleBookmark(hit.verse, bookmarked),
                  onMore: (bookmarked) => _showVerseActions(
                    books[hit.verse.bookId - 1],
                    hit.verse,
                    bookmarked,
                  ),
                ),
              if (_results.any((hit) => !hit.isExact))
                const _SectionLabel('相關經文'),
              for (final hit in _results.where((hit) => !hit.isExact))
                _VerseResultTile(
                  hit: hit,
                  books: books,
                  query: _controller.text.trim(),
                  bookmarked: bookmarkKeys.contains(
                    '${hit.verse.bookId}:${hit.verse.chapter}:${hit.verse.verse}',
                  ),
                  onTap: () => _openChapter(
                    hit.verse.bookId,
                    hit.verse.chapter,
                    verse: hit.verse.verse,
                  ),
                  onCopy: () =>
                      _copyVerse(books[hit.verse.bookId - 1], hit.verse),
                  onBookmark: (bookmarked) =>
                      _toggleBookmark(hit.verse, bookmarked),
                  onMore: (bookmarked) => _showVerseActions(
                    books[hit.verse.bookId - 1],
                    hit.verse,
                    bookmarked,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _VerseResultTile extends StatelessWidget {
  const _VerseResultTile({
    required this.hit,
    required this.books,
    required this.query,
    required this.bookmarked,
    required this.onTap,
    required this.onCopy,
    required this.onBookmark,
    required this.onMore,
  });

  final VerseSearchHit hit;
  final List<Book> books;
  final String query;
  final bool bookmarked;
  final VoidCallback onTap;
  final Future<void> Function() onCopy;
  final Future<void> Function(bool bookmarked) onBookmark;
  final void Function(bool bookmarked) onMore;

  @override
  Widget build(BuildContext context) {
    final verse = hit.verse;
    final previewTerm = hit.isExact
        ? query
        : hit.matchedTerms.firstWhere(
            (term) => verse.text.contains(term),
            orElse: () => query,
          );
    final citation =
        '${books[verse.bookId - 1].name} ${verse.chapter}:${verse.verse}';
    final related = hit.matchedTerms.take(3).join('、');
    return StudentSwipeRow(
      dismissKey: ValueKey(
        'search_${verse.bookId}_${verse.chapter}_${verse.verse}',
      ),
      startLabel: '複製',
      startIcon: Icons.copy_outlined,
      endLabel: bookmarked ? '移除書籤' : '加入書籤',
      endIcon: bookmarked ? Icons.bookmark_remove : Icons.bookmark_add_outlined,
      endDestructive: false,
      onSwipeStartToEnd: onCopy,
      onSwipeEndToStart: () => onBookmark(bookmarked),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text(sentenceWithMatch(verse.text, previewTerm)),
            subtitle: Text(
              hit.isExact || related.isEmpty
                  ? citation
                  : '$citation · 相關：$related',
            ),
            trailing: Icon(
              bookmarked ? Icons.bookmark : Icons.chevron_right,
              size: bookmarked ? 20 : 24,
            ),
            onTap: onTap,
            onLongPress: () => onMore(bookmarked),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

class _SearchError extends StatelessWidget {
  const _SearchError({required this.label, required this.onRetry});

  final String label;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off, size: 40),
          const SizedBox(height: 12),
          Text(label),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重試'),
          ),
        ],
      ),
    ),
  );
}

IconData _entityIcon(EntityType t) {
  switch (t) {
    case EntityType.person:
      return Icons.person_outline;
    case EntityType.place:
      return Icons.place_outlined;
    case EntityType.event:
      return Icons.event_outlined;
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _JumpTile extends StatelessWidget {
  final ({int bookId, int chapter, int? verse}) jump;
  final Book book;
  final VoidCallback onTap;

  const _JumpTile({
    required this.jump,
    required this.book,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = jump.verse == null
        ? '${book.name} 第 ${jump.chapter} 章'
        : '${book.name} ${jump.chapter}:${jump.verse}';
    return Material(
      color: scheme.primaryContainer,
      child: ListTile(
        leading: Icon(Icons.arrow_forward, color: scheme.onPrimaryContainer),
        title: Text(
          '跳到 $label',
          style: TextStyle(color: scheme.onPrimaryContainer),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _HistoryView extends ConsumerWidget {
  final void Function(String) onTap;

  const _HistoryView({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(searchHistoryProvider);
    if (history.isEmpty) {
      return const Center(child: Text('輸入關鍵字搜尋，或輸入節位（例：約3:16）'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('搜尋歷史', style: Theme.of(context).textTheme.titleSmall),
            TextButton(
              onPressed: () => ref.read(searchHistoryProvider.notifier).clear(),
              child: const Text('清除'),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final q in history)
              ActionChip(label: Text(q), onPressed: () => onTap(q)),
          ],
        ),
      ],
    );
  }
}
