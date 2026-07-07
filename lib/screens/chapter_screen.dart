import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../services/verse_locator.dart';
import '../theme/app_theme.dart';

/// 讀經畫面：一次一章，左右滑或按鈕換章，點經節開操作選單。
/// 支援兩種閱讀模式（逐節／整章）、章前導讀、章後統整、每節註解。
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(lastReadProvider.notifier).set(_bookId, _chapter);
      _logRead();
    });
  }

  Future<void> _logRead() async {
    try {
      await ref
          .read(databaseServiceProvider)
          .markChapterRead(_bookId, _chapter);
    } finally {
      ref.invalidate(readChapterCountProvider);
    }
  }

  void _goTo(int bookId, int chapter) {
    setState(() {
      _bookId = bookId;
      _chapter = chapter;
    });
    ref.read(lastReadProvider.notifier).set(bookId, chapter);
    _logRead();
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

  /// 依節位字串跳轉（交叉引用用）。
  void _jumpToRef(List<Book> books, String ref) {
    final loc = VerseLocator.parse(ref, books);
    if (loc == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ChapterScreen(bookId: loc.bookId, chapter: loc.chapter),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final booksAsync = ref.watch(booksProvider);
    final fontSize = ref.watch(fontSizeProvider);
    final mode = ref.watch(readingModeProvider);

    return booksAsync.when(
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('載入失敗：$e'))),
      data: (books) {
        final book = books[_bookId - 1];
        final verses = book.chapters[_chapter - 1];
        final marks = ref
                .watch(chapterMarksProvider(
                    (bookId: _bookId, chapter: _chapter)))
                .value ??
            const ChapterMarks(bookmarks: {}, highlights: {}, notes: {});
        final ann = ref
            .watch(chapterAnnotationProvider(
                (bookId: _bookId, chapter: _chapter)))
            .value;
        final chapterAnn = ann?.chapter;
        final verseAnns = ann?.verses ?? const <int, VerseAnnotation>{};

        return Scaffold(
          appBar: AppBar(
            title: Text('${book.name} $_chapter'),
            actions: [
              IconButton(
                icon: Icon(mode == ReadingMode.verse
                    ? Icons.notes
                    : Icons.format_list_numbered),
                tooltip: mode == ReadingMode.verse ? '整章連續' : '逐節分行',
                onPressed: () =>
                    ref.read(readingModeProvider.notifier).toggle(),
              ),
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
            child: ListView(
              key: PageStorageKey('$_bookId-$_chapter'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              children: [
                if (chapterAnn != null && chapterAnn.hasIntro)
                  _IntroCard(annotation: chapterAnn),
                if (mode == ReadingMode.verse)
                  ...List.generate(verses.length, (i) {
                    final verseNo = i + 1;
                    return _VerseTile(
                      verseNo: verseNo,
                      text: verses[i],
                      fontSize: fontSize,
                      highlight: marks.highlights[verseNo],
                      bookmarked: marks.bookmarks.contains(verseNo),
                      hasNote: marks.notes.containsKey(verseNo),
                      hasAnnotation: verseAnns.containsKey(verseNo),
                      onTap: () => _showVerseActions(books, book, verseNo,
                          verses[i], marks, verseAnns[verseNo]),
                    );
                  })
                else
                  _FlowingChapter(
                    verses: verses,
                    fontSize: fontSize,
                    highlights: marks.highlights,
                    annotated: verseAnns.keys.toSet(),
                    onTapVerse: (verseNo) => _showVerseActions(books, book,
                        verseNo, verses[verseNo - 1], marks,
                        verseAnns[verseNo]),
                  ),
                if (chapterAnn?.conclusion != null)
                  _ConclusionCard(text: chapterAnn!.conclusion!),
              ],
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
          // 注意：用 Wrap，不用 GridView（GridView 放進可捲動父層會出問題）
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

  void _showVerseActions(List<Book> books, Book book, int verseNo, String text,
      ChapterMarks marks, VerseAnnotation? annotation) {
    final db = ref.read(databaseServiceProvider);
    final isBookmarked = marks.bookmarks.contains(verseNo);
    final note = marks.notes[verseNo];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: annotation != null ? 0.6 : 0.42,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        builder: (ctx, scrollController) => ListView(
          controller: scrollController,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${book.name} $_chapter:$verseNo　$text',
                style: Theme.of(ctx).textTheme.bodyLarge,
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
                          await db.setHighlight(_bookId, _chapter, verseNo, c);
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
            if (annotation != null)
              _VerseAnnotationView(
                annotation: annotation,
                onTapRef: (ref) {
                  Navigator.pop(ctx);
                  _jumpToRef(books, ref);
                },
              ),
            const SizedBox(height: 16),
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
            Row(
              children: [
                Expanded(
                  child: Text('${book.name} $_chapter:$verseNo 筆記',
                      style: Theme.of(ctx).textTheme.titleMedium),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.view_column_outlined, size: 18),
                  label: const Text('三欄模板'),
                  onPressed: () {
                    // 觀察 / 相信 / 行動 三欄整理模板
                    final t = controller.text;
                    controller.text =
                        '${t.isEmpty ? '' : '$t\n'}【觀察】\n\n【相信】\n\n【行動】\n';
                    controller.selection = TextSelection.collapsed(
                        offset: controller.text.indexOf('\n【相信】'));
                  },
                ),
              ],
            ),
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

/// 逐節模式的單節。
class _VerseTile extends StatelessWidget {
  final int verseNo;
  final String text;
  final double fontSize;
  final HighlightColor? highlight;
  final bool bookmarked;
  final bool hasNote;
  final bool hasAnnotation;
  final VoidCallback onTap;

  const _VerseTile({
    required this.verseNo,
    required this.text,
    required this.fontSize,
    required this.highlight,
    required this.bookmarked,
    required this.hasNote,
    required this.hasAnnotation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: highlight != null
            ? BoxDecoration(
                color: AppTheme.highlightColor(highlight!, isDark),
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
                  color: scheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextSpan(
                text: text,
                style: TextStyle(fontSize: fontSize, height: 1.7),
              ),
              if (hasAnnotation)
                WidgetSpan(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.menu_book_outlined,
                        size: 15, color: scheme.tertiary),
                  ),
                ),
              if (bookmarked)
                const WidgetSpan(
                  child: Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.bookmark, size: 16),
                  ),
                ),
              if (hasNote)
                const WidgetSpan(
                  child: Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.sticky_note_2_outlined, size: 16),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 整章連續模式：所有節連成段落，節號上標，仍可逐節點擊與顯示螢光筆。
class _FlowingChapter extends StatefulWidget {
  final List<String> verses;
  final double fontSize;
  final Map<int, HighlightColor> highlights;
  final Set<int> annotated;
  final void Function(int verseNo) onTapVerse;

  const _FlowingChapter({
    required this.verses,
    required this.fontSize,
    required this.highlights,
    required this.annotated,
    required this.onTapVerse,
  });

  @override
  State<_FlowingChapter> createState() => _FlowingChapterState();
}

class _FlowingChapterState extends State<_FlowingChapter> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _clearRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clearRecognizers();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];

    for (var i = 0; i < widget.verses.length; i++) {
      final verseNo = i + 1;
      final recognizer = TapGestureRecognizer()
        ..onTap = () => widget.onTapVerse(verseNo);
      _recognizers.add(recognizer);
      final hl = widget.highlights[verseNo];

      spans.add(TextSpan(
        text: ' $verseNo ',
        style: TextStyle(
          fontSize: widget.fontSize * 0.65,
          color: scheme.primary,
          fontWeight: FontWeight.bold,
          fontFeatures: const [FontFeature.superscripts()],
        ),
        recognizer: recognizer,
      ));
      if (widget.annotated.contains(verseNo)) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Icon(Icons.menu_book_outlined,
              size: 13, color: scheme.tertiary),
        ));
      }
      spans.add(TextSpan(
        text: widget.verses[i],
        style: TextStyle(
          fontSize: widget.fontSize,
          height: 1.9,
          backgroundColor:
              hl != null ? AppTheme.highlightColor(hl, isDark) : null,
        ),
        recognizer: recognizer,
      ));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text.rich(TextSpan(children: spans)),
    );
  }
}

/// 章前導讀卡（與章同級的標題）。
class _IntroCard extends StatelessWidget {
  final ChapterAnnotation annotation;

  const _IntroCard({required this.annotation});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHigh,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_stories, size: 18, color: scheme.primary),
                const SizedBox(width: 6),
                Text('本章導讀',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: scheme.primary)),
              ],
            ),
            const SizedBox(height: 8),
            if (annotation.summary != null)
              _field('大意', annotation.summary!),
            if (annotation.purpose != null)
              _field('目的', annotation.purpose!),
            if (annotation.author != null)
              _field('作者', annotation.author!),
            if (annotation.background != null)
              _field('背景', annotation.background!),
            if (annotation.outline.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('分段',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: scheme.secondary)),
              const SizedBox(height: 2),
              for (final line in annotation.outline)
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 4),
                  child: Text('• $line',
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field(String label, String value) {
    return Builder(builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text.rich(TextSpan(children: [
          TextSpan(
            text: '$label　',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: scheme.secondary),
          ),
          TextSpan(
            text: value,
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ])),
      );
    });
  }
}

/// 章後統整卡（重點一句話）。
class _ConclusionCard extends StatelessWidget {
  final String text;

  const _ConclusionCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline,
                    size: 18, color: scheme.onPrimaryContainer),
                const SizedBox(width: 6),
                Text('本章重點',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: scheme.onPrimaryContainer)),
              ],
            ),
            const SizedBox(height: 8),
            Text(text,
                style: TextStyle(
                    height: 1.6, color: scheme.onPrimaryContainer)),
          ],
        ),
      ),
    );
  }
}

/// 節操作選單裡的註解區塊（注釋／關鍵字／生活應用／經文串連）。
class _VerseAnnotationView extends StatelessWidget {
  final VerseAnnotation annotation;
  final void Function(String ref) onTapRef;

  const _VerseAnnotationView(
      {required this.annotation, required this.onTapRef});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    Widget header(String label) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(label,
              style: tt.labelLarge?.copyWith(color: scheme.tertiary)),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(Icons.menu_book_outlined, size: 18, color: scheme.tertiary),
              const SizedBox(width: 6),
              Text('經文註解',
                  style: tt.titleMedium?.copyWith(color: scheme.tertiary)),
            ],
          ),
        ),
        if (annotation.commentary != null) ...[
          header('注釋'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(annotation.commentary!,
                style: tt.bodyMedium?.copyWith(height: 1.6)),
          ),
        ],
        if (annotation.keywords.isNotEmpty) ...[
          header('關鍵字'),
          for (final k in annotation.keywords)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
              child: Text.rich(TextSpan(children: [
                TextSpan(
                    text: '${k.word}　',
                    style: tt.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                TextSpan(
                    text: k.note,
                    style: tt.bodyMedium?.copyWith(height: 1.5)),
              ])),
            ),
        ],
        if (annotation.application != null) ...[
          header('生活應用${annotation.applicationCategory != null ? '・${annotation.applicationCategory}' : ''}'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(annotation.application!,
                style: tt.bodyMedium?.copyWith(height: 1.6)),
          ),
        ],
        if (annotation.crossRefs.isNotEmpty) ...[
          header('相關經文'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in annotation.crossRefs)
                  ActionChip(
                    avatar: const Icon(Icons.link, size: 16),
                    label: Text(r),
                    onPressed: () => onTapRef(r),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
