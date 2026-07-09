import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import 'book_overview_screen.dart';
import '../theme/app_theme.dart';
import 'chapter_screen.dart';

/// 書卷列表（舊約/新約 分頁 + 章節格）。從首頁「讀聖經」進入。
class BooksScreen extends ConsumerWidget {
  const BooksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(booksProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('讀聖經'),
          bottom: const TabBar(
            tabs: [Tab(text: '舊約'), Tab(text: '新約')],
          ),
        ),
        body: booksAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('載入經文失敗：$e')),
          data: (books) => TabBarView(
            children: [
              _BookList(
                  books: books.where((b) => b.testament == 'ot').toList()),
              _BookList(
                  books: books.where((b) => b.testament == 'nt').toList()),
            ],
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

/// 章節格。最前面是「導讀」、最後面是「統整」標籤方格（獨立於各章）。
/// 注意：不用 GridView（在可捲動父層裡會出問題），用 Wrap。
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
        _OverviewBox(
          label: '導讀',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BookOverviewScreen(
                  bookId: book.id,
                  bookName: book.name,
                  kind: OverviewKind.intro),
            ),
          ),
        ),
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
                color: AppTheme.paleBlue.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$c',
                  style: TextStyle(
                      color: scheme.onSurface, fontWeight: FontWeight.w500)),
            ),
          ),
        _OverviewBox(
          label: '統整',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BookOverviewScreen(
                  bookId: book.id,
                  bookName: book.name,
                  kind: OverviewKind.summary),
            ),
          ),
        ),
      ],
    );
  }
}

/// 導讀／統整標籤方格（與章節格同大小，配色區隔）。
class _OverviewBox extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _OverviewBox({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: scheme.onPrimaryContainer,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
