import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../theme/app_theme.dart';
import 'chapter_screen.dart';

/// 書籤 / 螢光筆 / 筆記 總覽。
class BookmarksScreen extends ConsumerWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('我的標記'),
          bottom: const TabBar(
            tabs: [Tab(text: '書籤'), Tab(text: '螢光筆'), Tab(text: '筆記')],
          ),
        ),
        body: const TabBarView(
          children: [_BookmarkTab(), _HighlightTab(), _NoteTab()],
        ),
      ),
    );
  }
}

class _BookmarkTab extends ConsumerWidget {
  const _BookmarkTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(booksProvider);
    final bookmarksAsync = ref.watch(allBookmarksProvider);

    return _asyncList2(booksAsync, bookmarksAsync, (books, items) {
      if (items.isEmpty) return const Center(child: Text('還沒有書籤'));
      return ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, i) {
          final b = items[i];
          final book = books[b.bookId - 1];
          final text = book.chapters[b.chapter - 1][b.verse - 1];
          return ListTile(
            leading: const Icon(Icons.bookmark),
            title: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('${book.name} ${b.chapter}:${b.verse}'),
            onTap: () => _openChapter(context, b.bookId, b.chapter),
          );
        },
      );
    });
  }
}

class _HighlightTab extends ConsumerWidget {
  const _HighlightTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(booksProvider);
    final highlightsAsync = ref.watch(allHighlightsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _asyncList2(booksAsync, highlightsAsync, (books, items) {
      if (items.isEmpty) return const Center(child: Text('還沒有螢光筆標記'));
      return ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, i) {
          final h = items[i];
          final book = books[h.bookId - 1];
          final text = book.chapters[h.chapter - 1][h.verse - 1];
          return ListTile(
            leading: CircleAvatar(
              radius: 10,
              backgroundColor: AppTheme.highlightSwatch(h.color),
            ),
            title: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppTheme.highlightColor(h.color, isDark),
                borderRadius: BorderRadius.circular(4),
              ),
              child:
                  Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            subtitle: Text('${book.name} ${h.chapter}:${h.verse}'),
            onTap: () => _openChapter(context, h.bookId, h.chapter),
          );
        },
      );
    });
  }
}

class _NoteTab extends ConsumerWidget {
  const _NoteTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(booksProvider);
    final notesAsync = ref.watch(allNotesProvider);

    return _asyncList2(booksAsync, notesAsync, (books, items) {
      if (items.isEmpty) return const Center(child: Text('還沒有筆記'));
      return ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, i) {
          final n = items[i];
          final book = books[n.bookId - 1];
          return ListTile(
            leading: const Icon(Icons.sticky_note_2_outlined),
            title: Text(n.content,
                maxLines: 3, overflow: TextOverflow.ellipsis),
            subtitle: Text('${book.name} ${n.chapter}:${n.verse}'),
            onTap: () => _openChapter(context, n.bookId, n.chapter),
          );
        },
      );
    });
  }
}

void _openChapter(BuildContext context, int bookId, int chapter) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ChapterScreen(bookId: bookId, chapter: chapter),
    ),
  );
}

/// 兩個 AsyncValue 都 ready 才 build，否則顯示 loading/error。
Widget _asyncList2<A, B>(
  AsyncValue<List<A>> a,
  AsyncValue<List<B>> b,
  Widget Function(List<A>, List<B>) builder,
) {
  if (a.hasError) return Center(child: Text('載入失敗：${a.error}'));
  if (b.hasError) return Center(child: Text('載入失敗：${b.error}'));
  final av = a.value;
  final bv = b.value;
  if (av == null || bv == null) {
    return const Center(child: CircularProgressIndicator());
  }
  return builder(av, bv);
}
