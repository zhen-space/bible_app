import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../utils/text_utils.dart';
import 'chapter_screen.dart';
import 'faith_map_screen.dart';
import 'sermon_notes_screen.dart';

/// 書籤 / 螢光筆 / 筆記 總覽。[initialTab] 0=書籤 1=螢光筆 2=筆記。
class BookmarksScreen extends ConsumerWidget {
  final int initialTab;

  const BookmarksScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('我的標記'),
          actions: [
            IconButton(
              icon: const Icon(Icons.map_outlined),
              tooltip: '我的信仰地圖',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const FaithMapScreen()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.church_outlined),
              tooltip: '主日・證道筆記',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SermonNotesScreen()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: '匯出筆記（Markdown）',
              onPressed: () => _exportNotes(context, ref),
            ),
          ],
          bottom: const TabBar(
            tabs: [Tab(text: '書籤'), Tab(text: '螢光筆'), Tab(text: '筆記')],
          ),
        ),
        body: Column(
          children: const [
            _StatsCard(),
            Expanded(
              child: TabBarView(
                children: [_BookmarkTab(), _HighlightTab(), _NoteTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 把全部筆記整理成 Markdown 複製到剪貼簿（白板「筆記匯出」的第一步；
/// PDF/Word 匯出之後再加）。
Future<void> _exportNotes(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final books = await ref.read(booksProvider.future);
    final notes = await ref.read(allNotesProvider.future);
    if (notes.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('還沒有筆記可匯出')));
      return;
    }
    final buf = StringBuffer('# 我的經文筆記\n');
    for (final n in notes) {
      final book = books[n.bookId - 1];
      final text = book.chapters[n.chapter - 1][n.verse - 1];
      buf
        ..writeln()
        ..writeln('## ${book.name} ${n.chapter}:${n.verse}')
        ..writeln('> $text')
        ..writeln()
        ..writeln(n.content);
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    messenger.showSnackBar(
        SnackBar(content: Text('已複製 ${notes.length} 則筆記（Markdown）')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('匯出失敗：$e')));
  }
}

/// 統計小卡：讀經、書籤、螢光筆、筆記、證道筆記數量。
class _StatsCard extends ConsumerWidget {
  const _StatsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(statsProvider).value;
    if (s == null) return const SizedBox.shrink();
    final items = [
      ('已讀', '${s['read']}', '章', Icons.menu_book),
      ('書籤', '${s['bookmarks']}', '', Icons.bookmark),
      ('螢光筆', '${s['highlights']}', '', Icons.brush),
      ('筆記', '${s['notes']}', '', Icons.sticky_note_2_outlined),
      ('證道', '${s['sermons']}', '', Icons.church_outlined),
    ];
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (final it in items)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(it.$4,
                      size: 20,
                      color: Theme.of(context).colorScheme.secondary),
                  const SizedBox(height: 4),
                  Text('${it.$2}${it.$3}',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text(it.$1,
                      style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
          ],
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

class _NoteTab extends ConsumerStatefulWidget {
  const _NoteTab();

  @override
  ConsumerState<_NoteTab> createState() => _NoteTabState();
}

class _NoteTabState extends ConsumerState<_NoteTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final booksAsync = ref.watch(booksProvider);
    final notesAsync = ref.watch(allNotesProvider);

    return _asyncList2(booksAsync, notesAsync, (books, items) {
      if (items.isEmpty) return const Center(child: Text('還沒有筆記'));
      final q = _query.trim();
      // 可搜筆記內容、標籤、書名、節位（例：約 3:16、信心、觀察）
      final filtered = q.isEmpty
          ? items
          : items.where((n) {
              final book = books[n.bookId - 1];
              final ref = '${book.name} ${n.chapter}:${n.verse}';
              return n.content.contains(q) ||
                  n.tags.contains(q) ||
                  ref.contains(q);
            }).toList();

      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: '搜尋筆記（內容、書名、節位）',
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('沒有符合的筆記'))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final n = filtered[i];
                      final book = books[n.bookId - 1];
                      // 搜尋中：顯示「含關鍵詞的那句話」並高亮該詞
                      final display = q.isEmpty
                          ? n.content
                          : sentenceWithMatch(n.content, q);
                      return ListTile(
                        leading: const Icon(Icons.sticky_note_2_outlined),
                        title: q.isEmpty
                            ? Text(display,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis)
                            : Text.rich(
                                TextSpan(
                                    children: highlightSpans(
                                        context, display, q)),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${book.name} ${n.chapter}:${n.verse}'),
                            if (n.tagList.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Wrap(
                                  spacing: 6,
                                  children: [
                                    for (final t in n.tagList)
                                      Container(
                                        padding: const EdgeInsets
                                            .symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.paleBlue
                                              .withValues(alpha: 0.25),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Text('#$t',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        onTap: () =>
                            _openChapter(context, n.bookId, n.chapter),
                      );
                    },
                  ),
          ),
        ],
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
