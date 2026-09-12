import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../services/download_stub.dart'
    if (dart.library.js_interop) '../services/download_web.dart';
import '../theme/app_theme.dart';
import '../widgets/student_ux.dart';
import 'chapter_screen.dart';
import 'faith_map_screen.dart';
import 'notes_screen.dart';
import 'sermon_notes_screen.dart';

class BookmarksScreen extends ConsumerWidget {
  const BookmarksScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('我的標記'),
          actions: [
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: (value) {
                if (value == 'map') {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const FaithMapScreen()));
                } else if (value == 'sermon') {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SermonNotesScreen()));
                } else if (value == 'copy') {
                  _exportNotes(context, ref);
                } else if (value == 'html') {
                  _exportNotesHtml(context, ref);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'map', child: Text('我的信仰地圖')),
                PopupMenuItem(value: 'sermon', child: Text('證道筆記')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'copy', child: Text('複製筆記 Markdown')),
                PopupMenuItem(value: 'html', child: Text('下載筆記檔案')),
              ],
            ),
          ],
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

String _verseText(Book book, int chapter, int verse) =>
    book.chapters[chapter - 1][verse - 1];

String _humanVerse(Book book, int chapter, int verse) =>
    '${_verseText(book, chapter, verse)}\n${book.name} $chapter:$verse';

void _openChapter(BuildContext context, int bookId, int chapter, int verse) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ChapterScreen(
        bookId: bookId,
        chapter: chapter,
        focusVerse: verse,
        updateReadingPosition: false,
      ),
    ),
  );
}

class _BookmarkTab extends ConsumerStatefulWidget {
  const _BookmarkTab();
  @override
  ConsumerState<_BookmarkTab> createState() => _BookmarkTabState();
}

class _BookmarkTabState extends ConsumerState<_BookmarkTab> {
  final SelectionController<String> selection = SelectionController<String>();

  String keyOf(Bookmark b) => '${b.bookId}:${b.chapter}:${b.verse}';

  @override
  void initState() {
    super.initState();
    selection.addListener(_refreshState);
  }

  void _refreshState() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    selection
      ..removeListener(_refreshState)
      ..dispose();
    super.dispose();
  }

  Future<void> remove(Iterable<Bookmark> items) async {
    final db = ref.read(databaseServiceProvider);
    for (final item in items) {
      await db.toggleBookmark(item.bookId, item.chapter, item.verse);
    }
    selection.cancel();
    ref.invalidate(allBookmarksProvider);
    ref.invalidate(chapterMarksProvider);
  }

  @override
  Widget build(BuildContext context) {
    final booksAsync = ref.watch(booksProvider);
    final itemsAsync = ref.watch(allBookmarksProvider);
    if (booksAsync.hasError || itemsAsync.hasError) {
      return StudentErrorState(onRetry: () {
        ref.invalidate(booksProvider);
        ref.invalidate(allBookmarksProvider);
      });
    }
    final books = booksAsync.value;
    final items = itemsAsync.value;
    if (books == null || items == null) return const StudentCompactLoading();
    if (items.isEmpty) {
      return const StudentEmptyState(
          title: '還沒有書籤', subtitle: '在 Reader 選取經文即可加入書籤。', icon: Icons.bookmark_outline);
    }
    final chosen = items.where((b) => selection.contains(keyOf(b))).toList();
    final keys = items.map(keyOf).toList();
    return Column(children: [
      _SelectionHeader(
        active: selection.active,
        count: selection.count,
        total: items.length,
        onSelect: selection.start,
        onCancel: selection.cancel,
        onAll: () => selection.selectAll(keys),
      ),
      Expanded(
        child: ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 20),
          itemBuilder: (context, i) {
            final b = items[i];
            final book = books[b.bookId - 1];
            final key = keyOf(b);
            final row = ListTile(
              leading: selection.active
                  ? Checkbox(value: selection.contains(key), onChanged: (_) => selection.toggle(key))
                  : const Icon(Icons.bookmark),
              title: Text(_verseText(book, b.chapter, b.verse), maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${book.name} ${b.chapter}:${b.verse}'),
              onLongPress: () => selection.start(key),
              onTap: selection.active
                  ? () => selection.toggle(key)
                  : () => _openChapter(context, b.bookId, b.chapter, b.verse),
            );
            if (selection.active) return row;
            return StudentSwipeRow(
              dismissKey: ValueKey('bookmark_$key'),
              startLabel: '複製',
              startIcon: Icons.copy_outlined,
              endLabel: '移除',
              onSwipeStartToEnd: () => copyHumanReadable(context, _humanVerse(book, b.chapter, b.verse)),
              onSwipeEndToStart: () => remove([b]),
              child: row,
            );
          },
        ),
      ),
      if (selection.active)
        StudentBatchActionBar(actions: [
          StudentBatchAction(
            label: '複製',
            icon: Icons.copy_outlined,
            onPressed: chosen.isEmpty
                ? null
                : () => copyHumanReadable(
                      context,
                      joinHumanReadable(chosen.map((b) => _humanVerse(books[b.bookId - 1], b.chapter, b.verse))),
                      success: '已複製 ${chosen.length} 則經文',
                    ),
          ),
          StudentBatchAction(
            label: '移除',
            icon: Icons.delete_outline,
            destructive: true,
            onPressed: chosen.isEmpty ? null : () => remove(chosen),
          ),
        ]),
    ]);
  }
}

class _HighlightTab extends ConsumerStatefulWidget {
  const _HighlightTab();
  @override
  ConsumerState<_HighlightTab> createState() => _HighlightTabState();
}

class _HighlightTabState extends ConsumerState<_HighlightTab> {
  final SelectionController<String> selection = SelectionController<String>();
  String keyOf(Highlight h) => '${h.bookId}:${h.chapter}:${h.verse}';

  @override
  void initState() {
    super.initState();
    selection.addListener(_refreshState);
  }

  void _refreshState() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    selection
      ..removeListener(_refreshState)
      ..dispose();
    super.dispose();
  }

  Future<void> remove(Iterable<Highlight> items) async {
    final db = ref.read(databaseServiceProvider);
    for (final item in items) {
      await db.setHighlight(item.bookId, item.chapter, item.verse, null);
    }
    selection.cancel();
    ref.invalidate(allHighlightsProvider);
    ref.invalidate(chapterMarksProvider);
  }

  @override
  Widget build(BuildContext context) {
    final booksAsync = ref.watch(booksProvider);
    final itemsAsync = ref.watch(allHighlightsProvider);
    final labels = ref.watch(highlightLabelsProvider);
    if (booksAsync.hasError || itemsAsync.hasError) {
      return StudentErrorState(onRetry: () {
        ref.invalidate(booksProvider);
        ref.invalidate(allHighlightsProvider);
      });
    }
    final books = booksAsync.value;
    final items = itemsAsync.value;
    if (books == null || items == null) return const StudentCompactLoading();
    if (items.isEmpty) {
      return const StudentEmptyState(
          title: '還沒有螢光筆', subtitle: '在 Reader 選取經文即可標記。', icon: Icons.brush_outlined);
    }
    final chosen = items.where((h) => selection.contains(keyOf(h))).toList();
    return Column(children: [
      _SelectionHeader(
        active: selection.active,
        count: selection.count,
        total: items.length,
        onSelect: selection.start,
        onCancel: selection.cancel,
        onAll: () => selection.selectAll(items.map(keyOf)),
      ),
      Expanded(
        child: ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 20),
          itemBuilder: (context, i) {
            final h = items[i];
            final book = books[h.bookId - 1];
            final key = keyOf(h);
            final label = labels[h.color];
            final row = ListTile(
              leading: selection.active
                  ? Checkbox(value: selection.contains(key), onChanged: (_) => selection.toggle(key))
                  : CircleAvatar(radius: 9, backgroundColor: AppTheme.highlightSwatch(h.color)),
              title: Text(_verseText(book, h.chapter, h.verse), maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${book.name} ${h.chapter}:${h.verse}${label == null ? '' : ' · $label'}'),
              onLongPress: () => selection.start(key),
              onTap: selection.active
                  ? () => selection.toggle(key)
                  : () => _openChapter(context, h.bookId, h.chapter, h.verse),
            );
            if (selection.active) return row;
            return StudentSwipeRow(
              dismissKey: ValueKey('highlight_$key'),
              startLabel: '複製',
              startIcon: Icons.copy_outlined,
              endLabel: '移除',
              onSwipeStartToEnd: () => copyHumanReadable(context, _humanVerse(book, h.chapter, h.verse)),
              onSwipeEndToStart: () => remove([h]),
              child: row,
            );
          },
        ),
      ),
      if (selection.active)
        StudentBatchActionBar(actions: [
          StudentBatchAction(
            label: '複製',
            icon: Icons.copy_outlined,
            onPressed: chosen.isEmpty
                ? null
                : () => copyHumanReadable(
                      context,
                      joinHumanReadable(chosen.map((h) => _humanVerse(books[h.bookId - 1], h.chapter, h.verse))),
                      success: '已複製 ${chosen.length} 則經文',
                    ),
          ),
          StudentBatchAction(
            label: '移除',
            icon: Icons.delete_outline,
            destructive: true,
            onPressed: chosen.isEmpty ? null : () => remove(chosen),
          ),
        ]),
    ]);
  }
}

class _NoteTab extends StatelessWidget {
  const _NoteTab();
  @override
  Widget build(BuildContext context) => StudentEmptyState(
        title: '經文筆記已集中管理',
        subtitle: '從「內容 → 經文筆記」可搜尋、選取與管理全部筆記。',
        icon: Icons.edit_note_outlined,
        actionLabel: '開啟經文筆記',
        onAction: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const NotesScreen())),
      );
}

class _SelectionHeader extends StatelessWidget {
  const _SelectionHeader({
    required this.active,
    required this.count,
    required this.total,
    required this.onSelect,
    required this.onCancel,
    required this.onAll,
  });
  final bool active;
  final int count;
  final int total;
  final VoidCallback onSelect;
  final VoidCallback onCancel;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
        child: Row(children: [
          Expanded(
            child: Text(active ? '已選 $count 項' : '$total 項',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
          ),
          if (active) ...[
            TextButton(onPressed: onAll, child: const Text('全選')),
            TextButton(onPressed: onCancel, child: const Text('取消')),
          ] else
            TextButton(onPressed: onSelect, child: const Text('選取')),
        ]),
      );

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
      buf
        ..writeln('\n## ${book.name} ${n.chapter}:${n.verse}')
        ..writeln(n.content);
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    messenger.showSnackBar(SnackBar(content: Text('已複製 ${notes.length} 則筆記')));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('暫時無法匯出筆記，請稍後再試。')));
  }
}

Future<void> _exportNotesHtml(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final books = await ref.read(booksProvider.future);
    final notes = await ref.read(allNotesProvider.future);
    if (notes.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('還沒有筆記可匯出')));
      return;
    }
    String esc(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('\n', '<br>');
    final buf = StringBuffer('<!doctype html><html lang="zh-Hant"><head><meta charset="utf-8"><title>我的經文筆記</title></head><body><h1>我的經文筆記</h1>');
    for (final n in notes) {
      final book = books[n.bookId - 1];
      buf
        ..write('<article><h2>${esc(book.name)} ${n.chapter}:${n.verse}</h2>')
        ..write('<p>${esc(n.content)}</p></article>');
    }
    buf.write('</body></html>');
    final ok = downloadTextFile('我的經文筆記.html', 'text/html', buf.toString());
    messenger.showSnackBar(SnackBar(content: Text(ok ? '已下載筆記檔案' : '此平台不支援下載')));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('暫時無法匯出筆記，請稍後再試。')));
  }
}
