import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';

/// 讀經畫面：一次一章，左右滑或按鈕換章，點經節開操作選單。
class ChapterScreen extends ConsumerStatefulWidget {
  final int bookId;
  final int chapter;

  const ChapterScreen(
      {super.key, required this.bookId, required this.chapter});

  @override
  ConsumerState<ChapterScreen> createState() => _ChapterScreenState();
}

class _ChapterScreenState extends ConsumerState<ChapterScreen> {
  late int _bookId;
  late int _chapter;

  @override
  void initState() {
    super.initState();
    _bookId = widget.bookId;
    _chapter = widget.chapter;
    // 記住閱讀位置
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(lastReadProvider.notifier).set(_bookId, _chapter);
    });
  }

  void _goTo(int bookId, int chapter) {
    setState(() {
      _bookId = bookId;
      _chapter = chapter;
    });
    ref.read(lastReadProvider.notifier).set(bookId, chapter);
  }

  /// 上一章／下一章，跨書卷自動接續。
  void _turn(List<Book> books, int delta) {
    var b = _bookId;
    var c = _chapter + delta;
    if (c < 1) {
      if (b == 1) return;
      b -= 1;
      c = books[b - 1].chapterCount;
    } else if (c > books[b - 1].chapterCount) {
      if (b == books.length) return;
      b += 1;
      c = 1;
    }
    _goTo(b, c);
  }

  @override
  Widget build(BuildContext context) {
    final booksAsync = ref.watch(booksProvider);
    final fontSize = ref.watch(fontSizeProvider);

    return booksAsync.when(
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator())),
      error: (e, _) =>
          Scaffold(body: Center(child: Text('載入失敗：$e'))),
      data: (books) {
        final book = books[_bookId - 1];
        final verses = book.chapters[_chapter - 1];
        final marksAsync = ref
            .watch(chapterMarksProvider((bookId: _bookId, chapter: _chapter)));
        final marks = marksAsync.value ??
            const ChapterMarks(bookmarks: {}, highlights: {}, notes: {});
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Scaffold(
          appBar: AppBar(
            title: Text('${book.name} $_chapter'),
            actions: [
              IconButton(
                icon: const Icon(Icons.list),
                tooltip: '選章',
                onPressed: () => _showChapterPicker(book),
              ),
            ],
          ),
          body: GestureDetector(
            onHorizontalDragEnd: (details) {
              final v = details.primaryVelocity ?? 0;
              if (v < -200) _turn(books, 1);
              if (v > 200) _turn(books, -1);
            },
            child: ListView.builder(
              key: PageStorageKey('$_bookId-$_chapter'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              itemCount: verses.length,
              itemBuilder: (context, i) {
                final verseNo = i + 1;
                final highlight = marks.highlights[verseNo];
                return InkWell(
                  onTap: () => _showVerseActions(
                      book, verseNo, verses[i], marks),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: highlight != null
                        ? BoxDecoration(
                            color:
                                AppTheme.highlightColor(highlight, isDark),
                            borderRadius: BorderRadius.circular(4),
                          )
                        : null,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$verseNo ',
                            style: TextStyle(
                              fontSize: fontSize * 0.7,
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextSpan(
                            text: verses[i],
                            style: TextStyle(
                                fontSize: fontSize, height: 1.7),
                          ),
                          if (marks.bookmarks.contains(verseNo))
                            const WidgetSpan(
                              child: Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(Icons.bookmark, size: 16),
                              ),
                            ),
                          if (marks.notes.containsKey(verseNo))
                            const WidgetSpan(
                              child: Padding(
                                padding: EdgeInsets.only(left: 4),
                                child:
                                    Icon(Icons.sticky_note_2_outlined, size: 16),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          bottomNavigationBar: BottomAppBar(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: '上一章',
                  onPressed: () => _turn(books, -1),
                ),
                Text('${book.name} 第 $_chapter 章'),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: '下一章',
                  onPressed: () => _turn(books, 1),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showChapterPicker(Book book) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          // 注意：這裡用 Wrap，不用 GridView（GridView 放進可捲動父層會出問題）
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var c = 1; c <= book.chapterCount; c++)
                ActionChip(
                  label: Text('$c'),
                  backgroundColor: c == _chapter
                      ? Theme.of(ctx).colorScheme.primaryContainer
                      : null,
                  onPressed: () {
                    Navigator.pop(ctx);
                    _goTo(book.id, c);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _refreshMarks() {
    ref.invalidate(
        chapterMarksProvider((bookId: _bookId, chapter: _chapter)));
    ref.invalidate(allBookmarksProvider);
    ref.invalidate(allHighlightsProvider);
    ref.invalidate(allNotesProvider);
  }

  void _showVerseActions(
      Book book, int verseNo, String text, ChapterMarks marks) {
    final db = ref.read(databaseServiceProvider);
    final isBookmarked = marks.bookmarks.contains(verseNo);
    final note = marks.notes[verseNo];

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${book.name} $_chapter:$verseNo　$text',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
            ),
            // 螢光筆選色
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final c in HighlightColor.values)
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () async {
                        Navigator.pop(ctx);
                        try {
                          await db.setHighlight(
                              _bookId, _chapter, verseNo, c);
                        } finally {
                          _refreshMarks();
                        }
                      },
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: AppTheme.highlightSwatch(c),
                        child: marks.highlights[verseNo] == c
                            ? const Icon(Icons.check, size: 18)
                            : null,
                      ),
                    ),
                  if (marks.highlights.containsKey(verseNo))
                    IconButton(
                      icon: const Icon(Icons.format_color_reset),
                      tooltip: '移除螢光筆',
                      onPressed: () async {
                        Navigator.pop(ctx);
                        try {
                          await db.setHighlight(
                              _bookId, _chapter, verseNo, null);
                        } finally {
                          _refreshMarks();
                        }
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(isBookmarked
                  ? Icons.bookmark_remove
                  : Icons.bookmark_add_outlined),
              title: Text(isBookmarked ? '移除書籤' : '加入書籤'),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await db.toggleBookmark(_bookId, _chapter, verseNo);
                } finally {
                  _refreshMarks();
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: Text(note == null ? '寫筆記' : '編輯筆記'),
              onTap: () {
                Navigator.pop(ctx);
                _showNoteEditor(book, verseNo, note);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('複製經文'),
              onTap: () async {
                await Clipboard.setData(ClipboardData(
                    text: '「$text」（${book.name} $_chapter:$verseNo）'));
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已複製')));
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showNoteEditor(Book book, int verseNo, Note? existing) {
    final controller = TextEditingController(text: existing?.content ?? '');
    final db = ref.read(databaseServiceProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${book.name} $_chapter:$verseNo 筆記',
                style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              maxLines: 5,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '寫下你的想法…',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (existing != null)
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      try {
                        await db.deleteNote(_bookId, _chapter, verseNo);
                      } finally {
                        _refreshMarks();
                      }
                    },
                    child: const Text('刪除'),
                  ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    final content = controller.text.trim();
                    Navigator.pop(ctx);
                    if (content.isEmpty) return;
                    try {
                      await db.saveNote(_bookId, _chapter, verseNo, content);
                    } finally {
                      _refreshMarks();
                    }
                  },
                  child: const Text('儲存'),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
