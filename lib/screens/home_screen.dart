import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import 'bookmarks_screen.dart';
import 'chapter_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'topics_screen.dart';

/// 全聖經總章數（66 卷合計），讀經進度分母。
const int kTotalChapters = 1189;

/// 首頁：舊約/新約書卷列表 + 繼續閱讀。
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(booksProvider);
    final lastRead = ref.watch(lastReadProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('聖經 · 和合本'),
          actions: [
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: '搜尋經文',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchScreen()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.category_outlined),
              tooltip: '主題閱讀',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TopicsScreen()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.collections_bookmark_outlined),
              tooltip: '書籤與筆記',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BookmarksScreen()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: '設定',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [Tab(text: '舊約'), Tab(text: '新約')],
          ),
        ),
        body: booksAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('載入經文失敗：$e')),
          data: (books) => Column(
            children: [
              const _DailyVerseCard(),
              if (lastRead != null)
                _ContinueReadingBar(
                  book: books[lastRead.bookId - 1],
                  chapter: lastRead.chapter,
                ),
              const _ReadingProgressBar(),
              const _RecentNotesBar(),
              Expanded(
                child: TabBarView(
                  children: [
                    _BookList(
                        books: books
                            .where((b) => b.testament == 'ot')
                            .toList()),
                    _BookList(
                        books: books
                            .where((b) => b.testament == 'nt')
                            .toList()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 每日經文卡片。
class _DailyVerseCard extends ConsumerWidget {
  const _DailyVerseCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dailyAsync = ref.watch(dailyVerseProvider);
    final daily = dailyAsync.value;
    if (daily == null) return const SizedBox.shrink();

    final booksAsync = ref.watch(booksProvider);
    final books = booksAsync.value;
    if (books == null) return const SizedBox.shrink();
    final book = books[daily.bookId - 1];

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ChapterScreen(bookId: daily.bookId, chapter: daily.chapter),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('今日經文',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: 6),
              Text(daily.text, style: const TextStyle(height: 1.6)),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '—${book.name} ${daily.chapter}:${daily.verse}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 讀經進度（已讀章數 / 1189）。
class _ReadingProgressBar extends ConsumerWidget {
  const _ReadingProgressBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(readChapterCountProvider).value ?? 0;
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: count / kTotalChapters,
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('已讀 $count / $kTotalChapters 章',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// 首頁「個人筆記」區：最近筆記橫向預覽，點開回到該節。
class _RecentNotesBar extends ConsumerWidget {
  const _RecentNotesBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(allNotesProvider).value ?? const <Note>[];
    final books = ref.watch(booksProvider).value;
    if (notes.isEmpty || books == null) return const SizedBox.shrink();
    final recent = notes.take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('我的筆記',
                  style: Theme.of(context).textTheme.titleSmall),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const BookmarksScreen(initialTab: 2),
                  ),
                ),
                child: const Text('看全部'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: recent.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final n = recent[i];
              final book = books[n.bookId - 1];
              return SizedBox(
                width: 200,
                child: Card(
                  margin: EdgeInsets.zero,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChapterScreen(
                            bookId: n.bookId, chapter: n.chapter),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${book.name} ${n.chapter}:${n.verse}',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary)),
                          const SizedBox(height: 4),
                          Expanded(
                            child: Text(
                              n.content,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ContinueReadingBar extends StatelessWidget {
  final Book book;
  final int chapter;

  const _ContinueReadingBar({required this.book, required this.chapter});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      child: ListTile(
        leading: Icon(Icons.auto_stories, color: scheme.onPrimaryContainer),
        title: Text(
          '繼續閱讀：${book.name} 第 $chapter 章',
          style: TextStyle(color: scheme.onPrimaryContainer),
        ),
        trailing:
            Icon(Icons.chevron_right, color: scheme.onPrimaryContainer),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ChapterScreen(bookId: book.id, chapter: chapter),
          ),
        ),
      ),
    );
  }
}

class _BookList extends StatelessWidget {
  final List<Book> books;

  const _BookList({required this.books});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: books.length,
      itemBuilder: (context, i) {
        final book = books[i];
        return ExpansionTile(
          title: Text(book.name),
          subtitle: Text('${book.chapterCount} 章'),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: _ChapterGrid(book: book),
            ),
          ],
        );
      },
    );
  }
}

/// 章節格。注意：不用 GridView（在可捲動父層裡會出問題），用 Wrap。
class _ChapterGrid extends StatelessWidget {
  final Book book;

  const _ChapterGrid({required this.book});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var c = 1; c <= book.chapterCount; c++)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChapterScreen(bookId: book.id, chapter: c),
              ),
            ),
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$c', style: TextStyle(color: scheme.onSurface)),
            ),
          ),
      ],
    );
  }
}
