import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../services/content_service.dart';
import '../services/tts_service.dart';
import '../services/verse_locator.dart';
import '../utils/text_utils.dart';
import '../utils/share_utils.dart';
import '../theme/app_theme.dart';
import 'search_screen.dart';

/// 讀經畫面：一次一章，左右滑或按鈕換章，點經節開操作選單。
/// 支援兩種閱讀模式（逐節／整章）、章前導讀、章後統整、每節註解。
class ChapterScreen extends ConsumerStatefulWidget {
  final int bookId;
  final int chapter;

  /// 進來時要還原到的捲動位移（「繼續閱讀」帶上次的 offset；一般進入 0＝章頂）。
  final double initialOffset;

  /// 進來時要「跳到並閃一下」的節（從搜尋、引用、交叉引用等跳進來時帶上）。
  final int? focusVerse;

  /// 是否更新「一般 Reading Position / History」。
  /// 正常閱讀（書卷→章、繼續閱讀）＝true；**臨時瀏覽**（搜尋結果、每日經文、
  /// 交叉引用、Q&A 引用、知識庫、之後的 Plan Reader）＝false：
  /// 進入、捲動、換章、換卷都**不**更新一般 Reading Position，也不記閱讀紀錄。
  final bool updateReadingPosition;

  const ChapterScreen({
    super.key,
    required this.bookId,
    required this.chapter,
    this.initialOffset = 0,
    this.focusVerse,
    this.updateReadingPosition = true,
  });

  @override
  ConsumerState<ChapterScreen> createState() => _ChapterScreenState();
}

class _ChapterScreenState extends ConsumerState<ChapterScreen> {
  late int _bookId;
  late int _chapter;
  TtsController? _ttsCtrl;

  // 記住閱讀位置：ScrollController 存/還原捲動位移（逐節、段落兩模式通用，渲染穩定）
  final ScrollController _scroll = ScrollController();
  double? _restoreOffset; // 本章要還原到的位移（套用一次後清空）
  Timer? _savePosDebounce;

  // 多選模式（逐節模式）：選中的節號集合，非空即進入多選。
  final Set<int> _selected = {};
  bool get _selectionMode => _selected.isNotEmpty;

  // 跳到指定節並閃一下（搜尋/引用跳進來）
  final GlobalKey _focusKey = GlobalKey();
  int? _flashVerse; // 目前要閃的節（幾秒後清空）
  bool _focusPending = false; // 還沒捲到定位
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    _bookId = widget.bookId;
    _chapter = widget.chapter;
    // 帶了 focusVerse 就以它為準，不還原上次 offset
    if (widget.focusVerse != null) {
      _flashVerse = widget.focusVerse;
      _focusPending = true;
      _restoreOffset = null;
    } else {
      _restoreOffset = widget.initialOffset > 0 ? widget.initialOffset : null;
    }
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ttsCtrl = ref.read(ttsProvider.notifier);
      // 臨時瀏覽不更新一般 Reading Position／閱讀紀錄
      if (widget.updateReadingPosition) {
        ref
            .read(lastReadProvider.notifier)
            .set(_bookId, _chapter, widget.initialOffset);
        _logRead();
      }
      // 背景載入英文，讓「點開經節看英文」即時可用（載一次，之後常駐）
      ref.read(bibleRepositoryProvider).loadEnglish();
      if (_focusPending) _tryFocus();
    });
  }

  @override
  void dispose() {
    _savePosDebounce?.cancel();
    _flashTimer?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    // 離開這一章就停止朗讀（用 initState 抓好的 notifier，避免 dispose 中讀 ref）
    _ttsCtrl?.stop();
    super.dispose();
  }

  /// 捲動時 debounce 存位移（記住讀到的畫面）。臨時瀏覽不存。
  void _onScroll() {
    if (!widget.updateReadingPosition) return;
    if (!_scroll.hasClients) return;
    final offset = _scroll.offset;
    _savePosDebounce?.cancel();
    _savePosDebounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(lastReadProvider.notifier).setOffset(_bookId, _chapter, offset);
    });
  }

  /// 首屏後把捲動位置還原到上次讀到的地方（只做一次）。
  void _maybeRestore() {
    final target = _restoreOffset;
    if (target == null || !_scroll.hasClients) return;
    _restoreOffset = null;
    final max = _scroll.position.maxScrollExtent;
    _scroll.jumpTo(target.clamp(0, max));
  }

  /// 捲到 focusVerse 並閃一下。逐節懶載入時，往下翻直到那節建出來。
  void _tryFocus() {
    if (!_focusPending || !mounted) return;
    final ctx = _focusKey.currentContext;
    if (ctx != null) {
      _focusPending = false;
      Scrollable.ensureVisible(ctx,
          alignment: 0.3,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut);
      _startFlash();
      return;
    }
    if (_scroll.hasClients) {
      final pos = _scroll.position;
      if (pos.pixels < pos.maxScrollExtent) {
        _scroll.jumpTo((pos.pixels + pos.viewportDimension * 0.85)
            .clamp(0.0, pos.maxScrollExtent));
        WidgetsBinding.instance.addPostFrameCallback((_) => _tryFocus());
      } else {
        _focusPending = false; // 到底仍沒建出來（罕見）→ 至少閃一下
        _startFlash();
      }
    }
  }

  /// 閃 2.6 秒後淡出。
  void _startFlash() {
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _flashVerse = null);
    });
  }

  /// 記錄「造訪」到 Reading History（reading_log）。**不等於完成**——
  /// 完成是使用者主動按「完成本章」（見 _toggleComplete）。
  Future<void> _logRead() async {
    await ref
        .read(databaseServiceProvider)
        .markChapterRead(_bookId, _chapter);
  }

  /// 使用者主動確認「完成／取消完成」本章。只在正常閱讀（非臨時瀏覽）出現。
  Future<void> _toggleComplete(int bookId, int chapter, bool currentlyDone) async {
    final db = ref.read(databaseServiceProvider);
    try {
      if (currentlyDone) {
        await db.unmarkChapterComplete(bookId, chapter);
      } else {
        await db.markChapterComplete(bookId, chapter);
      }
    } finally {
      ref.invalidate(chapterCompleteProvider((bookId: bookId, chapter: chapter)));
      ref.invalidate(readChapterCountProvider);
      ref.invalidate(faithMapProvider);
      ref.invalidate(statsProvider);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(currentlyDone ? '已取消本章完成標記' : '已標記本章完成'),
          duration: const Duration(seconds: 1)));
    }
  }

  void _toggleSelect(int verseNo) {
    setState(() {
      if (!_selected.remove(verseNo)) _selected.add(verseNo);
    });
  }

  void _clearSelection() => setState(_selected.clear);

  List<int> get _selectedSorted => _selected.toList()..sort();

  /// 多選批次：對選中的每一節套用螢光筆（null＝移除）。
  Future<void> _bulkHighlight(HighlightColor? color) async {
    final db = ref.read(databaseServiceProvider);
    final verses = _selectedSorted;
    try {
      for (final v in verses) {
        await db.setHighlight(_bookId, _chapter, v, color);
      }
    } finally {
      _refreshMarks();
    }
    _clearSelection();
  }

  /// 多選批次：加入書籤（已有的略過）。
  Future<void> _bulkBookmark(Set<int> alreadyBookmarked) async {
    final db = ref.read(databaseServiceProvider);
    try {
      for (final v in _selectedSorted) {
        if (!alreadyBookmarked.contains(v)) {
          await db.toggleBookmark(_bookId, _chapter, v);
        }
      }
    } finally {
      _refreshMarks();
    }
    _clearSelection();
  }

  /// 多選批次：加入稍後閱讀。
  Future<void> _bulkLater() async {
    final db = ref.read(databaseServiceProvider);
    try {
      for (final v in _selectedSorted) {
        await db.addLater(_bookId, _chapter, v);
      }
    } finally {
      ref.invalidate(allLaterProvider);
      _refreshMarks();
    }
    _clearSelection();
  }

  /// 多選批次：複製／分享（純經文 / 經文＋出處）。
  void _bulkCopyShare(Book book, List<String> allVerses, {required bool share}) {
    final verses = _selectedSorted;
    final texts = [for (final v in verses) allVerses[v - 1]];
    final citation = versesCitation(book, _chapter, verses);
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
                _copyText(plainVerses(texts), share);
              },
            ),
            ListTile(
              leading: const Icon(Icons.format_quote),
              title: const Text('經文＋出處'),
              subtitle: Text(citation),
              onTap: () {
                Navigator.pop(ctx);
                _copyText(versesWithCitation(texts, citation), share);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyText(String value, bool share) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(share ? '已複製，可貼到任何 App 分享' : '已複製'),
          duration: const Duration(seconds: 2)));
    }
    _clearSelection();
  }

  void _goTo(int bookId, int chapter) {
    ref.read(ttsProvider.notifier).stop(); // 換章先停止朗讀
    _restoreOffset = null; // 換章從頂端開始
    setState(() {
      _bookId = bookId;
      _chapter = chapter;
      _selected.clear(); // 換章清空多選
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    // 臨時瀏覽：換章/換卷也不更新一般 Reading Position
    if (widget.updateReadingPosition) {
      ref.read(lastReadProvider.notifier).set(bookId, chapter);
      _logRead();
    }
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
        // 「完成本章」只在正常閱讀時提供（臨時瀏覽不記完成）。
        final isComplete = widget.updateReadingPosition &&
            (ref
                    .watch(chapterCompleteProvider(
                        (bookId: _bookId, chapter: _chapter)))
                    .value ??
                false);
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
          appBar: _selectionMode
              ? _selectionAppBar(verses.length)
              : AppBar(
            // 點標題（頂部入口）先開「66 卷書卷目錄」
            title: InkWell(
              onTap: () =>
                  _showBookChapterPicker(books, startInBookList: true),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text('${book.name} $_chapter')),
                  const Icon(Icons.arrow_drop_down, size: 22),
                ],
              ),
            ),
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
              if (widget.updateReadingPosition)
                IconButton(
                  icon: Icon(isComplete
                      ? Icons.check_circle
                      : Icons.check_circle_outline),
                  color: isComplete
                      ? Theme.of(context).colorScheme.secondary
                      : null,
                  tooltip: isComplete ? '已完成本章（點擊取消）' : '標記本章完成',
                  onPressed: () =>
                      _toggleComplete(_bookId, _chapter, isComplete),
                ),
              IconButton(
                icon: const Icon(Icons.list),
                tooltip: '選卷選章',
                onPressed: () =>
                    _showBookChapterPicker(books, startInBookList: true),
              ),
            ],
          ),
          body: GestureDetector(
            onHorizontalDragEnd: (details) {
              final v = details.primaryVelocity ?? 0;
              if (v < -200) _turn(books, 1);
              if (v > 200) _turn(books, -1);
            },
            // 逐節模式用 builder 懶載入：超長章（詩119 有 176 節）只建
            // 進到畫面的節，捲動不卡頓（白板「多線程渲染優化」的 Flutter 正解——
            // UI 單執行緒下靠 lazy build 而非開執行緒）。
            child: mode == ReadingMode.verse
                // 逐節模式用 builder 懶載入：超長章（詩119 有 176 節）只建
                // 進到畫面的節，捲動不卡頓。位置還原走 ScrollController offset。
                ? ListView.builder(
                    key: PageStorageKey('$_bookId-$_chapter'),
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 96),
                    itemCount:
                        verses.length + (bookSummary != null ? 1 : 0),
                    itemBuilder: (context, i) {
                      // 首個 item 建好後（有 clients）嘗試還原捲動位置
                      if (i == 0) {
                        WidgetsBinding.instance
                            .addPostFrameCallback((_) => _maybeRestore());
                      }
                      if (i == verses.length) {
                        return _BookSummaryCard(
                            bookName: book.name, text: bookSummary!);
                      }
                      final isFocus = widget.focusVerse == i + 1;
                      final verseNo = i + 1;
                      final tile = _VerseTile(
                        key: isFocus ? _focusKey : null,
                        verseNo: verseNo,
                        text: verses[i],
                        english: en(verseNo),
                        fontSize: fontSize,
                        highlight: marks.highlights[verseNo],
                        bookmarked: marks.bookmarks.contains(verseNo),
                        hasNote: marks.notes.containsKey(verseNo),
                        hasAnnotation: verseAnns.containsKey(verseNo),
                        speaking: speakingVerse == verseNo,
                        flashing: _flashVerse == verseNo,
                        selected: _selected.contains(verseNo),
                        onTap: () {
                          if (_selectionMode) {
                            _toggleSelect(verseNo);
                          } else {
                            _showVerseActions(books, book, verseNo, verses[i],
                                marks, verseAnns[verseNo]);
                          }
                        },
                        onLongPress: () => _toggleSelect(verseNo),
                      );
                      if (headings[i + 1] == null) return tile;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SectionHeading(
                              text: headings[i + 1]!, fontSize: fontSize),
                          tile,
                        ],
                      );
                    },
                  )
                : ListView(
                    key: PageStorageKey('$_bookId-$_chapter'),
                    controller: _scroll,
                    // 左右留白、上下寬鬆，讀起來不擁擠
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 96),
                    children: [
                      Builder(builder: (_) {
                        WidgetsBinding.instance
                            .addPostFrameCallback((_) => _maybeRestore());
                        return const SizedBox.shrink();
                      }),
                      _ParagraphChapter(
                        verses: verses,
                        english: englishReady
                            ? [
                                for (var v = 1; v <= verses.length; v++)
                                  en(v)
                              ]
                            : null,
                        fontSize: fontSize,
                        highlights: marks.highlights,
                        annotated: verseAnns.keys.toSet(),
                        headings: headings,
                        speakingVerse: speakingVerse,
                        flashVerse: _flashVerse,
                        focusVerse: widget.focusVerse,
                        focusKey: _focusKey,
                        onTapVerse: (verseNo) => _showVerseActions(
                            books,
                            book,
                            verseNo,
                            verses[verseNo - 1],
                            marks,
                            verseAnns[verseNo]),
                      ),
                      if (bookSummary != null)
                        _BookSummaryCard(
                            bookName: book.name, text: bookSummary),
                    ],
                  ),
          ),
          bottomNavigationBar: _selectionMode
              ? _selectionBar(book, verses, marks)
              : BottomAppBar(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: '上一章',
                  onPressed: () => _turn(books, -1),
                ),
                // 點中間開「選卷選章」（可切書卷、點章跳轉）
                TextButton(
                  onPressed: () => _showBookChapterPicker(books),
                  child: Text('${book.name} 第 $_chapter 章',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface)),
                ),
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

  /// 多選模式的 AppBar：顯示已選數、清除、全選。
  AppBar _selectionAppBar(int verseCount) => AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: '取消選取',
          onPressed: _clearSelection,
        ),
        title: Text('已選 ${_selected.length} 節'),
        actions: [
          IconButton(
            icon: const Icon(Icons.select_all),
            tooltip: '全選本章',
            onPressed: () => setState(() {
              _selected
                ..clear()
                ..addAll(List.generate(verseCount, (i) => i + 1));
            }),
          ),
        ],
      );

  /// 多選模式的底部批次動作列：螢光筆／書籤／稍後讀／複製／分享。
  Widget _selectionBar(Book book, List<String> verses, ChapterMarks marks) {
    return BottomAppBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: const Icon(Icons.brush_outlined),
            tooltip: '螢光筆',
            onPressed: () => _showBulkHighlightMenu(),
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: '書籤',
            onPressed: () => _bulkBookmark(marks.bookmarks),
          ),
          IconButton(
            icon: const Icon(Icons.watch_later_outlined),
            tooltip: '稍後讀',
            onPressed: _bulkLater,
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: '複製',
            onPressed: () => _bulkCopyShare(book, verses, share: false),
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: '分享',
            onPressed: () => _bulkCopyShare(book, verses, share: true),
          ),
        ],
      ),
    );
  }

  /// 多選批次螢光筆選色（含移除）。
  void _showBulkHighlightMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final c in HighlightColor.values)
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () {
                    Navigator.pop(ctx);
                    _bulkHighlight(c);
                  },
                  child: CircleAvatar(
                      radius: 18, backgroundColor: AppTheme.highlightSwatch(c)),
                ),
              IconButton(
                icon: const Icon(Icons.format_color_reset),
                tooltip: '移除螢光筆',
                onPressed: () {
                  Navigator.pop(ctx);
                  _bulkHighlight(null);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 選卷選章。[startInBookList] true＝先顯示 66 卷書卷目錄（**頂部入口**用）；
  /// false＝直接顯示目前書卷的章格（**底部 selector** 用）。兩種模式可互相切換
  /// （書卷目錄點書→該卷章格；章格點卷名→回書卷目錄）。點章走 _goTo 跳轉。
  void _showBookChapterPicker(List<Book> books, {bool startInBookList = false}) {
    var pickBookId = _bookId; // 目前展示哪一卷的章格（可與正在讀的不同）
    var showingBooks = startInBookList; // true＝書卷目錄；false＝章格
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final maxH = MediaQuery.of(ctx).size.height * 0.72;

          // ── 模式一：66 卷書卷目錄（頂部入口的第一個畫面）──
          if (showingBooks) {
            Widget bookTile(Book bk) => ListTile(
                  dense: true,
                  title: Text(bk.name),
                  trailing: Text('${bk.chapterCount} 章',
                      style: Theme.of(ctx).textTheme.bodySmall),
                  selected: bk.id == _bookId,
                  onTap: () => setSheet(() {
                    pickBookId = bk.id;
                    showingBooks = false; // 選書 → 進該卷章格
                  }),
                );
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Text('選擇書卷（共 66 卷）',
                          style: Theme.of(ctx).textTheme.titleMedium),
                    ),
                    const Divider(height: 1),
                    Flexible(
                      child: ListView(
                        children: [
                          _pickerSectionLabel(ctx, '舊約'),
                          for (final bk in books.where((x) => x.id <= 39))
                            bookTile(bk),
                          _pickerSectionLabel(ctx, '新約'),
                          for (final bk in books.where((x) => x.id >= 40))
                            bookTile(bk),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // ── 模式二：目前/選定書卷的章格（底部 selector 的第一個畫面）──
          final b = books[pickBookId - 1];
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxH),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 書卷切換列：‹ › 切鄰卷；點卷名 → 回 66 卷目錄
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        tooltip: '上一卷',
                        onPressed: pickBookId > 1
                            ? () => setSheet(() => pickBookId -= 1)
                            : null,
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () => setSheet(() => showingBooks = true),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Text('${b.name}（${b.chapterCount} 章）',
                                      textAlign: TextAlign.center,
                                      style:
                                          Theme.of(ctx).textTheme.titleMedium),
                                ),
                                const Icon(Icons.arrow_drop_down, size: 22),
                              ],
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        tooltip: '下一卷',
                        onPressed: pickBookId < books.length
                            ? () => setSheet(() => pickBookId += 1)
                            : null,
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      // 注意：用 Wrap，不用 GridView（GridView 放進可捲動父層會出問題）
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var c = 1; c <= b.chapterCount; c++)
                            ActionChip(
                              label: Text('$c'),
                              backgroundColor:
                                  (b.id == _bookId && c == _chapter)
                                      ? Theme.of(ctx)
                                          .colorScheme
                                          .primaryContainer
                                      : null,
                              onPressed: () {
                                Navigator.pop(ctx);
                                _goTo(b.id, c);
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _pickerSectionLabel(BuildContext ctx, String text) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(text,
              style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                  color: Theme.of(ctx).colorScheme.primary,
                  fontWeight: FontWeight.bold)),
        ),
      );

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

    // 抽屜面板：閱讀主體保持乾淨，深度註釋收進底部面板，
    // 用 Tabs 切「字義／背景／應用／相關」（白板：抽屜面板構想）。
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        Widget quickAction(IconData icon, String label, VoidCallback onTap) =>
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 22, color: scheme.secondary),
                  const SizedBox(height: 2),
                  Text(label, style: Theme.of(ctx).textTheme.labelSmall),
                ]),
              ),
            );
        Widget empty(String hint) => Center(
              child: Text(hint,
                  style: Theme.of(ctx)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.outline)),
            );

        return FractionallySizedBox(
          heightFactor: annotation != null || publicNotes.isNotEmpty
              ? 0.82
              : 0.6,
          child: DefaultTabController(
            length: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10),
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    '${book.name} $_chapter:$verseNo　$text',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(ctx).textTheme.bodyLarge,
                  ),
                ),
                if (english != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text(
                      english,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.6),
                          height: 1.4),
                    ),
                  ),
                // 螢光筆選色（可命名）
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
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
                                radius: 16,
                                backgroundColor: AppTheme.highlightSwatch(c),
                                child: marks.highlights[verseNo] == c
                                    ? const Icon(Icons.check, size: 16)
                                    : null,
                              ),
                            ),
                            if (highlightLabels[c] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(highlightLabels[c]!,
                                    style:
                                        Theme.of(ctx).textTheme.labelSmall),
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
                // 快速動作列
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    quickAction(
                        isBookmarked
                            ? Icons.bookmark_remove
                            : Icons.bookmark_add_outlined,
                        isBookmarked ? '移除書籤' : '書籤', () async {
                      Navigator.pop(ctx);
                      try {
                        await db.toggleBookmark(_bookId, _chapter, verseNo);
                      } finally {
                        _refreshMarks();
                      }
                    }),
                    quickAction(
                        Icons.edit_note, note == null ? '筆記' : '編輯筆記', () {
                      Navigator.pop(ctx);
                      _showNoteEditor(book, verseNo, note);
                    }),
                    quickAction(Icons.copy, '複製', () async {
                      await Clipboard.setData(ClipboardData(
                          text:
                              '「$text」（${book.name} $_chapter:$verseNo）'));
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已複製')));
                      }
                    }),
                    quickAction(Icons.rate_review_outlined, '投稿註解', () {
                      Navigator.pop(ctx);
                      _submitPublicNote(book, verseNo, text);
                    }),
                  ],
                ),
                const SizedBox(height: 4),
                TabBar(
                  labelStyle: Theme.of(ctx).textTheme.titleSmall,
                  tabs: const [
                    Tab(text: '字義'),
                    Tab(text: '背景'),
                    Tab(text: '應用'),
                    Tab(text: '相關'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      // 字義：注釋 + 關鍵字
                      if (annotation?.commentary == null &&
                          (annotation?.keywords.isEmpty ?? true))
                        empty('此節尚無字義註釋（內容待補）')
                      else
                        ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            if (annotation!.commentary != null)
                              Text(annotation.commentary!,
                                  style: const TextStyle(height: 1.8)),
                            if (annotation.keywords.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              for (final k in annotation.keywords)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 6),
                                  child: Text.rich(TextSpan(children: [
                                    TextSpan(
                                        text: '${k.word}　',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    TextSpan(
                                        text: k.note,
                                        style:
                                            const TextStyle(height: 1.6)),
                                  ])),
                                ),
                            ],
                            if (annotation.updatedAt != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                    '註解更新於 ${_ymdOf(annotation.updatedAt!)}',
                                    style: Theme.of(ctx)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: scheme.outline)),
                              ),
                          ],
                        ),
                      // 背景
                      annotation?.background == null
                          ? empty('此節尚無背景說明（內容待補）')
                          : ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                Text(annotation!.background!,
                                    style: const TextStyle(height: 1.8)),
                              ],
                            ),
                      // 應用
                      annotation?.application == null
                          ? empty('此節尚無生活應用（內容待補）')
                          : ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                if (annotation!.applicationCategory != null)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 6),
                                    child: Text(
                                        '分類：${annotation.applicationCategory}',
                                        style: Theme.of(ctx)
                                            .textTheme
                                            .labelLarge),
                                  ),
                                Text(annotation.application!,
                                    style: const TextStyle(height: 1.8)),
                              ],
                            ),
                      // 相關：交叉引用 + 社群註解
                      ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (annotation != null &&
                              annotation.crossRefs.isNotEmpty) ...[
                            Text('相關經文',
                                style: Theme.of(ctx).textTheme.labelLarge),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final r in annotation.crossRefs)
                                  ActionChip(
                                    avatar: const Icon(Icons.link, size: 16),
                                    label: Text(r),
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _jumpToRef(books, r);
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (publicNotes.isNotEmpty) ...[
                            Row(children: [
                              Icon(Icons.groups_outlined,
                                  size: 18, color: scheme.primary),
                              const SizedBox(width: 6),
                              Text('社群註解',
                                  style: Theme.of(ctx)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(color: scheme.primary)),
                            ]),
                            const SizedBox(height: 6),
                            for (final n in publicNotes)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(n.content,
                                        style:
                                            const TextStyle(height: 1.6)),
                                    if (n.author.isNotEmpty)
                                      Text('— ${n.author}',
                                          style: Theme.of(ctx)
                                              .textTheme
                                              .bodySmall),
                                  ],
                                ),
                              ),
                          ],
                          if ((annotation == null ||
                                  annotation.crossRefs.isEmpty) &&
                              publicNotes.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 40),
                              child: empty('尚無相關經文與社群註解'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _ymdOf(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/'
        '${d.day.toString().padLeft(2, '0')}';
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
  final bool flashing; // 從搜尋/引用跳進來，短暫閃一下提示位置
  final bool selected; // 多選模式選中
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _VerseTile({
    super.key,
    required this.verseNo,
    required this.text,
    required this.english,
    required this.fontSize,
    required this.highlight,
    required this.bookmarked,
    required this.hasNote,
    required this.hasAnnotation,
    required this.speaking,
    this.flashing = false,
    this.selected = false,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    // 閃示 > 螢光筆 > 朗讀中，依序決定底色
    final bg = selected
        ? scheme.primary.withValues(alpha: 0.18)
        : (flashing
            ? scheme.primary.withValues(alpha: 0.28)
            : (highlight != null
                ? AppTheme.highlightColor(highlight!, isDark)
                : (speaking ? scheme.primary.withValues(alpha: 0.12) : null)));
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: (bg != null || speaking || selected)
            ? BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(4),
                border: selected
                    ? Border.all(color: scheme.primary, width: 1.5)
                    : (speaking
                        ? Border.all(color: scheme.primary, width: 1.5)
                        : null),
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
                    // 人名/地名畫私名號（底線）
                    children: properNameSpans(context, text,
                        style: TextStyle(fontSize: fontSize, height: 1.8)),
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
  final int? flashVerse; // 跳進來要閃的節（給底色）
  final int? focusVerse; // 要定位的節（放 key 在該段落上）
  final GlobalKey? focusKey;
  final void Function(int verseNo) onTapVerse;

  const _ParagraphChapter({
    required this.verses,
    required this.english,
    required this.fontSize,
    required this.highlights,
    required this.annotated,
    required this.headings,
    required this.speakingVerse,
    this.flashVerse,
    this.focusVerse,
    this.focusKey,
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
            // 定位節所在的段落掛上 key，供捲動 ensureVisible
            key: (widget.focusVerse != null && para.contains(widget.focusVerse))
                ? widget.focusKey
                : null,
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
      final flashing = widget.flashVerse == verseNo;
      // 人名/地名畫私名號（底線）；保留原本的高亮底色與點擊
      spans.addAll(properNameSpans(
        context,
        widget.verses[i],
        style: TextStyle(
          fontSize: widget.fontSize,
          height: 1.9,
          fontWeight: (speaking || flashing) ? FontWeight.w700 : null,
          backgroundColor: flashing
              ? scheme.primary.withValues(alpha: 0.28)
              : (hl != null
                  ? AppTheme.highlightColor(hl, isDark)
                  : (speaking
                      ? scheme.primary.withValues(alpha: 0.12)
                      : null)),
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

