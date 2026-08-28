import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../utils/share_utils.dart';
import 'chapter_screen.dart';

/// 共用的「單節動作」面板（每日經文、書籤列表等非讀經頁的入口用）。
///
/// 提供螢光筆（可改色/移除）、書籤、筆記、複製（純經文／經文＋出處）、
/// 分享（走剪貼簿）、以及「在經文中閱讀」（臨時瀏覽，不動一般 Reading Position）。
/// 讀經頁本身有自己的深度註釋面板，不走這裡。
Future<void> showVerseActionSheet(
  BuildContext context,
  WidgetRef ref, {
  required Book book,
  required int chapter,
  required int verse,
  required String text,
}) async {
  final db = ref.read(databaseServiceProvider);
  final bookId = book.id;
  final highlights = await db.getChapterHighlights(bookId, chapter);
  final bookmarks = await db.getBookmarkedVerses(bookId, chapter);
  final notes = await db.getChapterNotes(bookId, chapter);
  final later = await db.getLaterVerses(bookId, chapter);
  if (!context.mounted) return;

  final currentColor = highlights[verse];
  final isBookmarked = bookmarks.contains(verse);
  final isLater = later.contains(verse);
  final existingNote = notes[verse];
  final citation = verseCitation(book, chapter, verse);
  final labels = ref.read(highlightLabelsProvider);

  void refresh() {
    ref.invalidate(chapterMarksProvider((bookId: bookId, chapter: chapter)));
    ref.invalidate(allBookmarksProvider);
    ref.invalidate(allHighlightsProvider);
    ref.invalidate(allNotesProvider);
    ref.invalidate(allLaterProvider);
  }

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                      color: scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text(citation,
                  style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                      color: scheme.primary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(text,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(height: 1.7)),
              const Divider(height: 24),
              // 螢光筆選色
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final c in HighlightColor.values)
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () async {
                          Navigator.pop(ctx);
                          await db.setHighlight(bookId, chapter, verse, c);
                          refresh();
                        },
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: AppTheme.highlightSwatch(c),
                          child: currentColor == c
                              ? const Icon(Icons.check, size: 16)
                              : null,
                        ),
                      ),
                      if (labels[c] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(labels[c]!,
                              style: Theme.of(ctx).textTheme.labelSmall),
                        ),
                    ]),
                  if (currentColor != null)
                    IconButton(
                      icon: const Icon(Icons.format_color_reset),
                      tooltip: '移除螢光筆',
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await db.setHighlight(bookId, chapter, verse, null);
                        refresh();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // 動作列
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _act(
                      ctx,
                      isBookmarked
                          ? Icons.bookmark_remove
                          : Icons.bookmark_add_outlined,
                      isBookmarked ? '移除書籤' : '書籤', () async {
                    Navigator.pop(ctx);
                    await db.toggleBookmark(bookId, chapter, verse);
                    refresh();
                  }),
                  _act(ctx, Icons.edit_note,
                      existingNote == null ? '筆記' : '編輯筆記', () {
                    Navigator.pop(ctx);
                    _showNoteEditor(context, ref, book, chapter, verse,
                        existingNote, refresh);
                  }),
                  _act(
                      ctx,
                      isLater ? Icons.watch_later : Icons.watch_later_outlined,
                      isLater ? '移除待讀' : '稍後讀', () async {
                    Navigator.pop(ctx);
                    await db.toggleLater(bookId, chapter, verse);
                    refresh();
                  }),
                  _act(ctx, Icons.copy, '複製', () {
                    Navigator.pop(ctx);
                    _copyOrShareMenu(context, text, citation, share: false);
                  }),
                  _act(ctx, Icons.ios_share, '分享', () {
                    Navigator.pop(ctx);
                    _copyOrShareMenu(context, text, citation, share: true);
                  }),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('在經文中閱讀'),
                onPressed: () {
                  Navigator.pop(ctx);
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
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _act(BuildContext ctx, IconData icon, String label, VoidCallback onTap) =>
    InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 22, color: Theme.of(ctx).colorScheme.secondary),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(ctx).textTheme.labelSmall),
        ]),
      ),
    );

/// 複製／分享：讓使用者選「純經文」或「經文＋出處」。分享在 web 走剪貼簿。
void _copyOrShareMenu(BuildContext context, String text, String citation,
    {required bool share}) {
  showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.short_text),
            title: const Text('純經文'),
            onTap: () {
              Navigator.pop(ctx);
              _toClipboard(context, plainVerses([text]), share);
            },
          ),
          ListTile(
            leading: const Icon(Icons.format_quote),
            title: const Text('經文＋出處'),
            subtitle: Text('「經文」（$citation）',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () {
              Navigator.pop(ctx);
              _toClipboard(
                  context, versesWithCitation([text], citation), share);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _toClipboard(
    BuildContext context, String value, bool share) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(share ? '已複製，可貼到任何 App 分享' : '已複製'),
        duration: const Duration(seconds: 2)));
  }
}

void _showNoteEditor(BuildContext context, WidgetRef ref, Book book,
    int chapter, int verse, Note? existing, VoidCallback onSaved) {
  final controller = TextEditingController(text: existing?.content ?? '');
  final tagsController = TextEditingController(text: existing?.tags ?? '');
  final db = ref.read(databaseServiceProvider);
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${book.name} $chapter:$verse 筆記',
              style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            maxLines: 5,
            autofocus: true,
            decoration: const InputDecoration(
                border: OutlineInputBorder(), hintText: '寫下你的想法…'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: tagsController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.tag, size: 18),
              hintText: '標籤（空格分隔）',
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (existing != null)
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await db.deleteNote(book.id, chapter, verse);
                  onSaved();
                },
                child: const Text('刪除'),
              ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () async {
                final content = controller.text.trim();
                final tags = tagsController.text.trim();
                Navigator.pop(ctx);
                if (content.isEmpty) return;
                await db.saveNote(book.id, chapter, verse, content, tags: tags);
                onSaved();
              },
              child: const Text('儲存'),
            ),
          ]),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
}
