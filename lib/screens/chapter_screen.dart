import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../services/content_service.dart';
import '../services/tts_service.dart';
import '../services/verse_locator.dart';
import '../theme/app_theme.dart';
import 'search_screen.dart';

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
  TtsController? _ttsCtrl;

  @override
  void initState() {
    super.initState();
    _bookId = widget.bookId;
    _chapter = widget.chapter;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ttsCtrl = ref.read(ttsProvider.notifier);
      ref.read(lastReadProvider.notifier).set(_bookId, _chapter);
      _logRead();
      // 背景載入英文，讓「點開經節看英文」即時可用（載一次，之後常駐）
      ref.read(bibleRepositoryProvider).loadEnglish();
    });
  }

  @override
  void dispose() {
    // 離開這一章就停止朗讀（用 initState 抓好的 notifier，避免 dispose 中讀 ref）
    _ttsCtrl?.stop();
    super.dispose();
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
    ref.read(ttsProvider.notifier).stop(); // 換章先停止朗讀
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
    final bilingual = ref.watch(bilingualProvider);
    final tts = ref.watch(ttsProvider);
    // 只有正在讀本章時才拿高亮節（換章時 state 已被 stop 清掉）
    final speakingVerse = tts.playing ? tts.verse : null;
    // 觸發英文載入；載入完成後 rebuild 才會有英文
    final englishReady =
        bilingual && (ref.watch(englishReadyProvider).value ?? false);
    final repo = ref.read(bibleRepositoryProvider);
    String? en(int verseNo) =>
        englishReady ? repo.english(_bookId, _chapter, verseNo) : null;

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
        final verseAnns = ann?.verses ?? const <int, VerseAnnotation>{};
        // 段落標題：來自章導讀的「分段」欄（後台可編輯），如「1-8 各支派在營地的位置」
        final headings = headingsFromOutline(ann?.chapter?.outline ?? const []);
        // 預抓本章社群註解（審核通過的公開投稿）
        ref.watch(
            publicNotesProvider((bookId: _bookId, chapter: _chapter)));
        // 本卷統整：只在整卷最後一章的末尾顯示（章層級導讀/重點已移除）
        final bookSummary = _chapter == book.chapterCount
            ? ref.watch(bookAnnotationProvider(_bookId)).value?.summary
            : null;

        return Scaffold(
          appBar: AppBar(
            title: Text('${book.name} $_chapter'),
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
                icon: Icon(tts.playing
                    ? Icons.stop_circle
                    : Icons.play_circle_outline),
                color: tts.playing
                    ? Theme.of(context).colorScheme.secondary
                    : null,
                tooltip: tts.playing ? '停止朗讀' : '聽這一章',
                onPressed: () =>
                    ref.read(ttsProvider.notifier).toggle(verses),
              ),
              IconButton(
                icon: Icon(bilingual ? Icons.translate : Icons.translate_outlined),
                color: bilingual
                    ? Theme.of(context).colorScheme.secondary
                    : null,
                tooltip: bilingual ? '關閉中英對照' : '中英對照',
                onPressed: () =>
                    ref.read(bilingualProvider.notifier).toggle(),
              ),
              IconButton(
                icon: Icon(mode == ReadingMode.verse
                    ? Icons.notes
                    : Icons.format_list_numbered),
                tooltip: mode == ReadingMode.verse ? '段落分段' : '逐節分行',
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
              // 左右留白、上下寬鬆，讀起來不擁擠
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 96),
              children: [
                if (mode == ReadingMode.verse)
                  ...[
                    for (var i = 0; i < verses.length; i++) ...[
                      if (headings[i + 1] != null)
                        _SectionHeading(
                            text: headings[i + 1]!, fontSize: fontSize),
                      _VerseTile(
                        verseNo: i + 1,
                        text: verses[i],
                        english: en(i + 1),
                        fontSize: fontSize,
                        highlight: marks.highlights[i + 1],
                        bookmarked: marks.bookmarks.contains(i + 1),
                        hasNote: marks.notes.containsKey(i + 1),
                        hasAnnotation: verseAnns.containsKey(i + 1),
                        speaking: speakingVerse == i + 1,
                        onTap: () => _showVerseActions(books, book, i + 1,
                            verses[i], marks, verseAnns[i + 1]),
                      ),
                    ],
                  ]
                else
                  _ParagraphChapter(
                    verses: verses,
                    english: englishReady
                        ? [for (var v = 1; v <= verses.length; v++) en(v)]
                        : null,
                    fontSize: fontSize,
                    highlights: marks.highlights,
                    annotated: verseAnns.keys.toSet(),
                    headings: headings,
                    speakingVerse: speakingVerse,
                    onTapVerse: (verseNo) => _showVerseActions(books, book,
                        verseNo, verses[verseNo - 1], marks,
                        verseAnns[verseNo]),
                  ),
                if (bookSummary != null)
                  _BookSummaryCard(bookName: book.name, text: bookSummary),
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
    final highlightLabels = ref.read(highlightLabelsProvider);
    final isBookmarked = marks.bookmarks.contains(verseNo);
    final note = marks.notes[verseNo];
    // 點開一律附英文（不受對照開關影響，需要英文已載入）——先確保載入
    ref.read(bibleRepositoryProvider).loadEnglish();
    final english =
        ref.read(bibleRepositoryProvider).english(_bookId, _chapter, verseNo);
    // 已審核通過的社群註解（此章一次抓，取本節）
    final publicNotes = ref
            .read(publicNotesProvider(
                (bookId: _bookId, chapter: _chapter)))
            .value?[verseNo] ??
        const <PublicNote>[];

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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                '${book.name} $_chapter:$verseNo　$text',
                style: Theme.of(ctx).textTheme.bodyLarge,
              ),
            ),
            if (english != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  english,
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(ctx)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                      height: 1.5),
                ),
            ),
            // 螢光筆選色（可命名：顯示各色的意義標籤）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final c in HighlightColor.values)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                        if (highlightLabels[c] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(highlightLabels[c]!,
                                style: Theme.of(ctx).textTheme.labelSmall),
                          ),
                      ],
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
            // 社群註解（已審核通過的公開投稿）
            if (publicNotes.isNotEmpty) ...[
              const Divider(height: 24),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Row(children: [
                  Icon(Icons.groups_outlined,
                      size: 18, color: Theme.of(ctx).colorScheme.primary),
                  const SizedBox(width: 6),
                  Text('社群註解',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          color: Theme.of(ctx).colorScheme.primary)),
                ]),
              ),
              for (final n in publicNotes)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n.content,
                          style: Theme.of(ctx)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(height: 1.5)),
                      if (n.author.isNotEmpty)
                        Text('— ${n.author}',
                            style: Theme.of(ctx).textTheme.bodySmall),
                    ],
                  ),
                ),
            ],
            const Divider(height: 24),
            ListTile(
              leading: const Icon(Icons.rate_review_outlined),
              title: const Text('投稿公開註解'),
              subtitle: const Text('提交後經審核才會公開顯示'),
              onTap: () {
                Navigator.pop(ctx);
                _submitPublicNote(book, verseNo, text);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// 投稿一則公開註解（登入後可投；提交後進待審佇列）。
  void _submitPublicNote(Book book, int verseNo, String verseText) {
    final user = ref.read(authUserProvider).value;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('請先到「設定」用 Google 登入，才能投稿公開註解')));
      return;
    }
    final controller = TextEditingController();
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
            Text('投稿公開註解 · ${book.name} $_chapter:$verseNo',
                style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('提交後由管理者審核，通過才會公開顯示。',
                style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              maxLines: 4,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '寫下你對這節的理解或應用…',
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () async {
                  final content = controller.text.trim();
                  Navigator.pop(ctx);
                  if (content.isEmpty) return;
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await ref.read(contentServiceProvider).submitPublicNote(
                          uid: user.uid,
                          author: user.displayName ?? '',
                          bookId: _bookId,
                          chapter: _chapter,
                          verse: verseNo,
                          content: content,
                        );
                    messenger.showSnackBar(const SnackBar(
                        content: Text('已提交，待審核通過後公開')));
                  } catch (e) {
                    messenger.showSnackBar(
                        SnackBar(content: Text('提交失敗：$e')));
                  }
                },
                child: const Text('提交審核'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showNoteEditor(Book book, int verseNo, Note? existing) {
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
            TextField(
              controller: tagsController,
              maxLines: 1,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.tag, size: 18),
                hintText: '標籤（空格分隔，例：信心 禱告）',
                isDense: true,
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
                    final tags = tagsController.text.trim();
                    Navigator.pop(ctx);
                    if (content.isEmpty) return;
                    try {
                      await db.saveNote(_bookId, _chapter, verseNo, content,
                          tags: tags);
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
  final String? english; // 中英對照開啟時的 KJV 英文
  final double fontSize;
  final HighlightColor? highlight;
  final bool bookmarked;
  final bool hasNote;
  final bool hasAnnotation;
  final bool speaking; // 目前 TTS 正朗讀到這一節
  final VoidCallback onTap;

  const _VerseTile({
    required this.verseNo,
    required this.text,
    required this.english,
    required this.fontSize,
    required this.highlight,
    required this.bookmarked,
    required this.hasNote,
    required this.hasAnnotation,
    required this.speaking,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    // 朗讀中的節：用主色淡底框起來（優先於螢光筆底色的視覺提示）
    final bg = highlight != null
        ? AppTheme.highlightColor(highlight!, isDark)
        : (speaking ? scheme.primary.withValues(alpha: 0.12) : null);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: (bg != null || speaking)
            ? BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(4),
                border: speaking
                    ? Border.all(color: scheme.primary, width: 1.5)
                    : null,
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
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
                    style: TextStyle(fontSize: fontSize, height: 1.8),
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
            if (english != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 2),
                child: Text(
                  english!,
                  style: TextStyle(
                    fontSize: fontSize * 0.82,
                    height: 1.6,
                    color: scheme.onSurface.withValues(alpha: 0.62),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 解析章導讀「分段」欄成節→標題對照。
/// 每行格式：「1-8 各支派在營地的位置」或「9 標題」（起始節 + 標題文字）。
/// 標題內容由使用者在後台撰寫。
Map<int, String> headingsFromOutline(List<String> outline) {
  final out = <int, String>{};
  for (final line in outline) {
    final m = RegExp(r'^(\d+)(?:\s*[-–~－]\s*\d+)?\s*[、.．:：]?\s*(.+)$')
        .firstMatch(line.trim());
    if (m != null) {
      out[int.parse(m.group(1)!)] = m.group(2)!.trim();
    }
  }
  return out;
}

/// 段落標題（與章同級的小節標題，如「各支派在營地的位置」）。
class _SectionHeading extends StatelessWidget {
  final String text;
  final double fontSize;

  const _SectionHeading({required this.text, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: fontSize * 1.1,
          fontWeight: FontWeight.w700,
          height: 1.4,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// 把整章的節依標點斷句，自動組成自然段落（每段數節）。
/// 規則：累積到句末標點（。！？」』）且長度夠時斷段；
/// [breakBefore]（段落標題所在節）一定另起新段。
/// 回傳每段的節號清單（1-based）。
List<List<int>> groupIntoParagraphs(List<String> verses,
    {Set<int> breakBefore = const {}}) {
  const enders = {'。', '！', '？', '」', '』', '.', '!', '?'};
  final paras = <List<int>>[];
  var current = <int>[];
  var len = 0;
  for (var i = 0; i < verses.length; i++) {
    final verseNo = i + 1;
    if (breakBefore.contains(verseNo) && current.isNotEmpty) {
      paras.add(current);
      current = <int>[];
      len = 0;
    }
    final text = verses[i];
    current.add(verseNo);
    len += text.characters.length;
    final last = text.trim().characters.isEmpty
        ? ''
        : text.trim().characters.last;
    final endsSentence = enders.contains(last);
    if (endsSentence && len >= 90) {
      paras.add(current);
      current = <int>[];
      len = 0;
    }
  }
  if (current.isNotEmpty) paras.add(current);
  return paras;
}

/// 段落模式：依自然斷句分段呈現；首行縮排、段間留白；仍可逐節點擊、螢光筆、中英對照。
class _ParagraphChapter extends StatefulWidget {
  final List<String> verses;
  final List<String?>? english; // 中英對照開啟時每節英文（對齊 verses）
  final double fontSize;
  final Map<int, HighlightColor> highlights;
  final Set<int> annotated;
  final Map<int, String> headings; // 節→段落標題（後台「分段」欄）
  final int? speakingVerse; // 目前 TTS 朗讀到的節
  final void Function(int verseNo) onTapVerse;

  const _ParagraphChapter({
    required this.verses,
    required this.english,
    required this.fontSize,
    required this.highlights,
    required this.annotated,
    required this.headings,
    required this.speakingVerse,
    required this.onTapVerse,
  });

  @override
  State<_ParagraphChapter> createState() => _ParagraphChapterState();
}

class _ParagraphChapterState extends State<_ParagraphChapter> {
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
    final paragraphs = groupIntoParagraphs(widget.verses,
        breakBefore: widget.headings.keys.toSet());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final para in paragraphs) ...[
          if (widget.headings[para.first] != null)
            _SectionHeading(
                text: widget.headings[para.first]!,
                fontSize: widget.fontSize),
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Text.rich(
              TextSpan(children: _paragraphSpans(para, isDark, scheme)),
            ),
          ),
        ],
      ],
    );
  }

  List<InlineSpan> _paragraphSpans(
      List<int> verseNos, bool isDark, ColorScheme scheme) {
    final spans = <InlineSpan>[
      // 首行縮排（全形空格），像書本段落
      const TextSpan(text: '　　'),
    ];
    for (final verseNo in verseNos) {
      final i = verseNo - 1;
      final recognizer = TapGestureRecognizer()
        ..onTap = () => widget.onTapVerse(verseNo);
      _recognizers.add(recognizer);
      final hl = widget.highlights[verseNo];

      spans.add(TextSpan(
        text: ' $verseNo ',
        style: TextStyle(
          fontSize: widget.fontSize * 0.62,
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
      final speaking = widget.speakingVerse == verseNo;
      spans.add(TextSpan(
        text: widget.verses[i],
        style: TextStyle(
          fontSize: widget.fontSize,
          height: 1.9,
          fontWeight: speaking ? FontWeight.w700 : null,
          backgroundColor: hl != null
              ? AppTheme.highlightColor(hl, isDark)
              : (speaking
                  ? scheme.primary.withValues(alpha: 0.12)
                  : null),
        ),
        recognizer: recognizer,
      ));
      final en = widget.english != null ? widget.english![i] : null;
      if (en != null) {
        spans.add(TextSpan(
          text: ' $en ',
          style: TextStyle(
            fontSize: widget.fontSize * 0.8,
            height: 1.9,
            color: scheme.onSurface.withValues(alpha: 0.55),
          ),
          recognizer: recognizer,
        ));
      }
    }
    return spans;
  }
}

/// 本卷統整卡（顯示在整卷書最後一章的末尾）。
class _BookSummaryCard extends StatelessWidget {
  final String bookName;
  final String text;

  const _BookSummaryCard({required this.bookName, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      margin: const EdgeInsets.only(top: 24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.workspace_premium,
                    size: 20, color: scheme.onPrimaryContainer),
                const SizedBox(width: 6),
                Text('$bookName · 本卷統整',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 10),
            Text(text,
                style: TextStyle(
                    height: 1.8,
                    fontSize: 16,
                    color: scheme.onPrimaryContainer)),
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
