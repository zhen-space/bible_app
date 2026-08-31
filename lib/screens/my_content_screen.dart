import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import 'bookmarks_screen.dart';
import 'chapter_screen.dart';
import 'notes_screen.dart';
import 'prayers_screen.dart';
import 'sermon_notes_screen.dart';
import 'todos_screen.dart';

/// 我的內容：統一入口，把個人資料的各類集合集中在一個地方，
/// 但每種資料仍是獨立的 model／畫面（不合併資料）。
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

    return Scaffold(
      appBar: AppBar(title: const Text('我的內容')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _tile(context, Icons.edit_note, '經文筆記', c(notes), '標題、引用、標籤、搜尋',
              () => const NotesScreen()),
          _tile(context, Icons.brush_outlined, '螢光筆', c(highlights),
              '各色標記的經文', () => const BookmarksScreen(initialTab: 1)),
          _tile(context, Icons.bookmark_outline, '書籤', c(bookmarks), '收藏的經文',
              () => const BookmarksScreen(initialTab: 0)),
          _tile(context, Icons.watch_later_outlined, '稍後閱讀', c(later),
              '待讀清單', () => const LaterScreen()),
          _tile(context, Icons.record_voice_over_outlined, '主日證道筆記',
              c(sermons), '結構化證道筆記，可匯入匯出',
              () => const SermonNotesScreen()),
          _tile(context, Icons.volunteer_activism_outlined, '禱告事項', c(prayers),
              '正在禱告的事情', () => const PrayersScreen()),
          _tile(context, Icons.checklist, '信仰生活代辦', c(todos),
              '分類代辦，完成可打勾', () => const TodosScreen()),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title, String count,
          String subtitle, Widget Function() screen) =>
      Card(
        margin: const EdgeInsets.symmetric(vertical: 5),
        child: ListTile(
          leading: Icon(icon),
          title: Row(children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (count.isNotEmpty) ...[
              const SizedBox(width: 8),
              _badge(context, count),
            ],
          ]),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => screen())),
        ),
      );

  Widget _badge(BuildContext context, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onPrimaryContainer)),
      );
}

/// 稍後閱讀清單。
class LaterScreen extends ConsumerWidget {
  const LaterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final later = ref.watch(allLaterProvider);
    final books = ref.watch(booksProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('稍後閱讀')),
      body: later.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('載入失敗：$e')),
        data: (list) => list.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('還沒有待讀的經文。讀經時選取經文可加入「稍後讀」。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline)),
                ),
              )
            : ListView(
                children: [
                  for (final b in list)
                    ListTile(
                      leading: const Icon(Icons.watch_later_outlined),
                      title: Text(books == null
                          ? '${b.bookId}:${b.chapter}:${b.verse}'
                          : '${books[b.bookId - 1].name} ${b.chapter}:${b.verse}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: '移除',
                        onPressed: () async {
                          await ref
                              .read(databaseServiceProvider)
                              .removeLater(b.bookId, b.chapter, b.verse);
                          ref.invalidate(allLaterProvider);
                        },
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChapterScreen(
                              bookId: b.bookId,
                              chapter: b.chapter,
                              focusVerse: b.verse,
                              updateReadingPosition: false),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
