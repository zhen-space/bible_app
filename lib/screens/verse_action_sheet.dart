import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../utils/share_utils.dart';
import 'chapter_screen.dart';
import 'verse_notes_sheet.dart';

/// 螢光筆顏色的預設唸法（使用者沒命名時給螢幕閱讀器用）。
const _colorNames = {
  HighlightColor.yellow: '黃色',
  HighlightColor.green: '綠色',
  HighlightColor.blue: '藍色',
  HighlightColor.pink: '粉紅色',
  HighlightColor.orange: '橘色',
};

/// 正在讀取個人標記、還沒開出來的面板（同一節只讀一次，避免連點開出兩層）。
/// 只在讀取期間佔用；面板開著時入口已被遮罩擋住，不靠這個旗標。
final _opening = <String>{};

/// 寫入中的標記（`kind:book:chapter:verse`），擋掉同一筆的重複寫入。
final _inFlight = <String>{};

/// 寫一個標記的目標狀態：同一 [key] 寫入中就略過；失敗顯示 [failMessage] 與「重試」；
/// 不論成敗都 [refresh]，讓畫面顯示實際儲存的狀態。
Future<void> _writeMark({
  required String key,
  required ScaffoldMessengerState? messenger,
  required Future<void> Function() write,
  required String failMessage,
  required VoidCallback refresh,
}) async {
  if (!_inFlight.add(key)) return;
  var failed = false;
  try {
    await write();
  } catch (_) {
    failed = true;
  } finally {
    _inFlight.remove(key);
    refresh();
  }
  if (!failed) return;
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: Text(failMessage),
      action: SnackBarAction(
        label: '重試',
        onPressed: () => _writeMark(
          key: key,
          messenger: messenger,
          write: write,
          failMessage: failMessage,
          refresh: refresh,
        ),
      ),
    ));
}

/// 共用的「單節動作」面板（每日經文、書籤列表等非讀經頁的入口用）。
///
/// 提供螢光筆（可改色/移除）、書籤、筆記、複製（純經文／經文＋出處）、
/// 分享（走剪貼簿）、以及「在經文中閱讀」（臨時瀏覽，不動一般 Reading Position）。
/// 讀經頁本身有自己的深度註釋面板，不走這裡。
///
/// 筆記和讀經頁一樣支援同一節多則（共用 `verse_notes_sheet.dart`）：顯示則數與最新摘要，
/// 點入看同節全部筆記、選一則編輯／刪除、或新增；一律以筆記 id 寫，不會整節覆蓋或刪除。
/// 個人標記讀取失敗時面板照常開（複製／分享／在經文中閱讀可用），依狀態才能決定的
/// 書籤／稍後讀／筆記先停用並提供重試，避免以「未知」當「沒有」去切換或覆蓋。
///
/// 螢光筆／書籤／稍後讀都寫「目標狀態」（`setHighlight`／`setBookmark`／`setLater`，
/// 皆 idempotent、本體＋墓碑同一交易），失敗時重新整理成實際儲存的狀態、以 SnackBar
/// 告知並提供「重試」（重試寫同一個目標狀態，不會翻回去）。同一節同一種標記寫入
/// 進行中時不會再寫第二次（面板裡該按鈕停用、重試也略過）；面板讀取中連點入口只開一個。
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
  final openKey = '$bookId:$chapter:$verse';
  final hlKey = 'highlight:$bookId:$chapter:$verse';
  final bmKey = 'bookmark:$bookId:$chapter:$verse';
  final laterKey = 'later:$bookId:$chapter:$verse';
  HighlightColor? currentColor;
  var isBookmarked = false;
  var isLater = false;
  var notes = const <Note>[];
  var marksKnown = true;
  if (!_opening.add(openKey)) return;
  try {
    final highlights = await db.getChapterHighlights(bookId, chapter);
    final bookmarks = await db.getBookmarkedVerses(bookId, chapter);
    final later = await db.getLaterVerses(bookId, chapter);
    notes = await db.getVerseNotes(bookId, chapter, verse);
    currentColor = highlights[verse];
    isBookmarked = bookmarks.contains(verse);
    isLater = later.contains(verse);
  } catch (_) {
    marksKnown = false;
  } finally {
    _opening.remove(openKey);
  }
  if (!context.mounted) return;
  final citation = verseCitation(book, chapter, verse);
  final labels = ref.read(highlightLabelsProvider);

  void refresh() {
    // 寫入完成時入口頁可能已離開（ref 已失效）；畫面已不在就不必重新整理。
    if (!context.mounted) return;
    ref.invalidate(chapterMarksProvider((bookId: bookId, chapter: chapter)));
    ref.invalidate(allBookmarksProvider);
    ref.invalidate(allHighlightsProvider);
    ref.invalidate(allNotesProvider);
    ref.invalidate(allLaterProvider);
  }

  // 每次開面板只處理第一個動作：關面板中的連點不會寫兩次，也不會多 pop 一層。
  // （放在 builder 外，面板重建也不會重置。）
  var acted = false;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      bool claim() {
        if (acted) return false;
        acted = true;
        Navigator.pop(ctx);
        return context.mounted;
      }

      final messenger = ScaffoldMessenger.maybeOf(context);
      void writeMark(String key, Future<void> Function() write, String fail) {
        if (!claim()) return;
        _writeMark(
          key: key,
          messenger: messenger,
          write: write,
          failMessage: fail,
          refresh: refresh,
        );
      }

      final hlBusy = _inFlight.contains(hlKey);
      final bmBusy = _inFlight.contains(bmKey);
      final laterBusy = _inFlight.contains(laterKey);
      void openNotes() {
        if (!claim()) return;
        openVerseNotes(
          context,
          bookName: book.name,
          bookId: bookId,
          chapter: chapter,
          verse: verse,
          hasNotes: notes.isNotEmpty,
          onChanged: refresh,
        );
      }

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
              if (!marksKnown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Expanded(
                      child: Semantics(
                        liveRegion: true,
                        child: Text('個人標記暫時無法載入，書籤、稍後讀與筆記請稍後再試。',
                            style: TextStyle(color: scheme.error)),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        if (!claim()) return;
                        showVerseActionSheet(context, ref,
                            book: book,
                            chapter: chapter,
                            verse: verse,
                            text: text);
                      },
                      child: const Text('重試'),
                    ),
                  ]),
                ),
              // 螢光筆選色
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final c in HighlightColor.values)
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Semantics(
                        button: true,
                        selected: currentColor == c,
                        label: '螢光筆 ${labels[c] ?? _colorNames[c]}',
                        child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: hlBusy
                            ? null
                            : () => writeMark(
                                  hlKey,
                                  () => db.setHighlight(
                                      bookId, chapter, verse, c),
                                  currentColor == null
                                      ? '加上螢光筆失敗，經文沒有標記。'
                                      : '更換螢光筆失敗，顏色沒有變更。',
                                ),
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: AppTheme.highlightSwatch(c),
                          child: currentColor == c
                              ? const Icon(Icons.check, size: 16)
                              : null,
                        ),
                      )),
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
                      onPressed: hlBusy
                          ? null
                          : () => writeMark(
                                hlKey,
                                () => db.setHighlight(
                                    bookId, chapter, verse, null),
                                '移除螢光筆失敗，螢光筆仍保留。',
                              ),
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
                      isBookmarked ? '移除書籤' : '書籤',
                      !marksKnown || bmBusy
                          ? null
                          : () => writeMark(
                                bmKey,
                                // 目標狀態（非切換）：重試不會把狀態翻回去。
                                () => db.setBookmark(
                                    bookId, chapter, verse, !isBookmarked),
                                isBookmarked
                                    ? '移除書籤失敗，書籤仍保留。'
                                    : '加入書籤失敗，這節沒有加入書籤。',
                              )),
                  _act(ctx, Icons.edit_note,
                      notes.isEmpty ? '筆記' : '筆記 ${notes.length}',
                      !marksKnown ? null : openNotes),
                  _act(
                      ctx,
                      isLater ? Icons.watch_later : Icons.watch_later_outlined,
                      isLater ? '移除待讀' : '稍後讀',
                      !marksKnown || laterBusy
                          ? null
                          : () => writeMark(
                                laterKey,
                                // 設定目標狀態（非切換）：失敗後重試不會把狀態翻回去。
                                () => db.setLater(
                                    bookId, chapter, verse, !isLater),
                                isLater ? '移除待讀失敗，仍在稍後閱讀。' : '加入稍後閱讀失敗。',
                              )),
                  _act(ctx, Icons.copy, '複製', () {
                    if (!claim()) return;
                    _copyOrShareMenu(context, text, citation, share: false);
                  }),
                  _act(ctx, Icons.ios_share, '分享', () {
                    if (!claim()) return;
                    _copyOrShareMenu(context, text, citation, share: true);
                  }),
                ],
              ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 4),
                VerseNotesSummaryTile(notes: notes, onTap: openNotes),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('在經文中閱讀'),
                onPressed: () {
                  if (!claim()) return;
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

Widget _act(
        BuildContext ctx, IconData icon, String label, VoidCallback? onTap) =>
    InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: 22,
              color: onTap == null
                  ? Theme.of(ctx).colorScheme.outline
                  : Theme.of(ctx).colorScheme.secondary),
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
