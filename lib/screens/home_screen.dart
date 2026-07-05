import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import 'bookmarks_screen.dart';
import 'chapter_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

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
              if (lastRead != null)
                _ContinueReadingBar(
                  book: books[lastRead.bookId - 1],
                  chapter: lastRead.chapter,
                ),
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
