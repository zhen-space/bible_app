import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../widgets/student_ux.dart';
import 'bookmarks_screen.dart';
import 'chapter_screen.dart';
import 'notes_screen.dart';
import 'prayers_screen.dart';
import 'private_study_screen.dart';
import 'sermon_notes_screen.dart';
import 'study_content_screen.dart';
import 'todos_screen.dart';

class MyContentScreen extends ConsumerWidget {
  const MyContentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(allNotesProvider).value?.length;
    final highlights = ref.watch(allHighlightsProvider).value?.length;
    final bookmarks = ref.watch(allBookmarksProvider).value?.length;
    final later = ref.watch(allLaterProvider).value?.length;
    final sermons = ref.watch(allSermonNotesProvider).value?.length;
    final prayers = ref.watch(allPrayersProvider).value?.length;
    final todos = ref.watch(allTodosProvider).value?.length;
    String c(int? n) => n == null ? '' : '$n';

    final items = <({IconData icon, String title, String count, String subtitle, Widget Function() screen})>[
      (icon: Icons.edit_note, title: '經文筆記', count: c(notes), subtitle: '你的經文筆記與引用', screen: () => const NotesScreen()),
      (icon: Icons.brush_outlined, title: '螢光筆', count: c(highlights), subtitle: '各色標記的經文', screen: () => const BookmarksScreen(initialTab: 1)),
      (icon: Icons.bookmark_outline, title: '書籤', count: c(bookmarks), subtitle: '收藏的經文', screen: () => const BookmarksScreen(initialTab: 0)),
      (icon: Icons.watch_later_outlined, title: '稍後閱讀', count: c(later), subtitle: '待讀清單', screen: () => const LaterScreen()),
      (icon: Icons.menu_book_outlined, title: '已儲存的研讀內容', count: '', subtitle: '你儲存的研讀內容', screen: () => const SavedStudyContentScreen()),
      (icon: Icons.record_voice_over_outlined, title: '主日證道筆記', count: c(sermons), subtitle: '結構化證道筆記', screen: () => const SermonNotesScreen()),
      (icon: Icons.library_books_outlined, title: '我的研讀', count: '', subtitle: '整理自己閱讀的書籍、話語與心得', screen: () => const PrivateStudyHomeScreen()),
      (icon: Icons.volunteer_activism_outlined, title: '禱告事項', count: c(prayers), subtitle: '正在禱告的事情', screen: () => const PrayersScreen()),
      (icon: Icons.checklist, title: '信仰生活代辦', count: c(todos), subtitle: '分類代辦與完成狀態', screen: () => const TodosScreen()),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('我的內容')),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
        itemBuilder: (context, i) {
          final item = items[i];
          return ListTile(
            leading: Icon(item.icon),
            title: Text(item.title),
            subtitle: Text(item.subtitle),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (item.count.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(item.count,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline)),
                ),
              const Icon(Icons.chevron_right),
            ]),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => item.screen())),
          );
        },
      ),
    );
  }
}

class LaterScreen extends ConsumerStatefulWidget {
  const LaterScreen({super.key});

  @override
  ConsumerState<LaterScreen> createState() => _LaterScreenState();
}

class _LaterScreenState extends ConsumerState<LaterScreen> {
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

  Future<void> remove(Iterable<Bookmark> values) async {
    final db = ref.read(databaseServiceProvider);
    for (final b in values) {
      await db.removeLater(b.bookId, b.chapter, b.verse);
    }
    selection.cancel();
    ref.invalidate(allLaterProvider);
  }

  @override
  Widget build(BuildContext context) {
    final later = ref.watch(allLaterProvider);
    final list = later.value ?? const <Bookmark>[];
    final books = ref.watch(booksProvider).value;
    final ids = list.map(keyOf).toList();
    final chosen = list.where((b) => selection.contains(keyOf(b))).toList();

    String copyText(Bookmark b) {
      if (books == null) return '${b.bookId}:${b.chapter}:${b.verse}';
      final book = books[b.bookId - 1];
      return '${book.chapters[b.chapter - 1][b.verse - 1]}\n${book.name} ${b.chapter}:${b.verse}';
    }

    return Scaffold(
      appBar: selection.active
          ? StudentSelectionAppBar(
              title: '稍後閱讀',
              selectionCount: selection.count,
              totalCount: ids.length,
              onCancel: selection.cancel,
              onSelectAll: () => selection.selectAll(ids),
            )
          : AppBar(
              title: const Text('稍後閱讀'),
              actions: [
                if (list.isNotEmpty)
                  TextButton(onPressed: selection.start, child: const Text('選取')),
              ],
            ),
      bottomNavigationBar: selection.active
          ? StudentBatchActionBar(actions: [
              StudentBatchAction(
                label: '複製',
                icon: Icons.copy_outlined,
                onPressed: chosen.isEmpty
                    ? null
                    : () => copyHumanReadable(
                          context,
                          joinHumanReadable(chosen.map(copyText)),
                          success: '已複製 ${chosen.length} 則經文',
                        ),
              ),
              StudentBatchAction(
                label: '移除',
                icon: Icons.delete_outline,
                destructive: true,
                onPressed: chosen.isEmpty ? null : () => remove(chosen),
              ),
            ])
          : null,
      body: later.when(
        loading: () => const StudentCompactLoading(),
        error: (_, _) => StudentErrorState(onRetry: () => ref.invalidate(allLaterProvider)),
        data: (items) {
          if (items.isEmpty) {
            return const StudentEmptyState(
              title: '還沒有稍後閱讀',
              subtitle: '在 Reader 選取經文即可加入「稍後閱讀」。',
              icon: Icons.watch_later_outlined,
            );
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 20),
            itemBuilder: (context, i) {
              final b = items[i];
              final key = keyOf(b);
              final label = books == null
                  ? '${b.bookId}:${b.chapter}:${b.verse}'
                  : '${books[b.bookId - 1].name} ${b.chapter}:${b.verse}';
              final row = ListTile(
                leading: selection.active
                    ? Checkbox(value: selection.contains(key), onChanged: (_) => selection.toggle(key))
                    : const Icon(Icons.watch_later_outlined),
                title: Text(label),
                trailing: selection.active ? null : const Icon(Icons.chevron_right),
                onLongPress: () => selection.start(key),
                onTap: selection.active
                    ? () => selection.toggle(key)
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChapterScreen(
                              bookId: b.bookId,
                              chapter: b.chapter,
                              focusVerse: b.verse,
                              updateReadingPosition: false,
                            ),
                          ),
                        ),
              );
              if (selection.active) return row;
              return StudentSwipeRow(
                dismissKey: ValueKey('later_$key'),
                startLabel: '複製',
                startIcon: Icons.copy_outlined,
                endLabel: '移除',
                onSwipeStartToEnd: () => copyHumanReadable(context, copyText(b)),
                onSwipeEndToStart: () => remove([b]),
                child: row,
              );
            },
          );
        },
      ),
    );
  }
}
