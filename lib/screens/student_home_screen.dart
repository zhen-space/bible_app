import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import 'chapter_screen.dart';
import 'reading_plans_screen.dart';
import 'notes_screen.dart';
import 'search_screen.dart';
import 'verse_action_sheet.dart';

/// 新版首頁：只回答「今天／接下來要讀什麼」，不再充當功能總表。
class StudentHomeScreen extends ConsumerWidget {
  const StudentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastRead = ref.watch(lastReadProvider);
    final booksAsync = ref.watch(booksProvider);
    final dailyAsync = ref.watch(dailyVerseProvider);
    final notesAsync = ref.watch(allNotesProvider);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(allNotesProvider);
          ref.invalidate(dailyVerseProvider);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
          children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_greeting(), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(_dateLabel(), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.outline)),
              ])),
              IconButton(
                tooltip: '搜尋',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen())),
                icon: const Icon(Icons.search),
              ),
            ]),
            const SizedBox(height: 28),
            _sectionLabel(context, '繼續閱讀'),
            const SizedBox(height: 10),
            booksAsync.when(
              loading: () => const _LoadingBlock(height: 112),
              error: (_, _) => _InlineError(label: '暫時無法載入書卷資料', onRetry: () => ref.invalidate(booksProvider)),
              data: (books) {
                if (lastRead == null) return _StartReadingCard(books: books);
                final book = books[lastRead.bookId - 1];
                return _ContinueCard(book: book, chapter: lastRead.chapter, offset: lastRead.offset);
              },
            ),
            const SizedBox(height: 28),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _sectionLabel(context, '今日讀經計畫'),
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReadingPlansScreen())),
                child: const Text('查看計畫'),
              ),
            ]),
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                leading: const Icon(Icons.event_note_outlined),
                title: const Text('照著你的計畫繼續'),
                subtitle: const Text('既有計畫與完成進度會保留'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReadingPlansScreen())),
              ),
            ),
            const SizedBox(height: 28),
            _sectionLabel(context, '每日經文'),
            const SizedBox(height: 10),
            dailyAsync.when(
              loading: () => const _LoadingBlock(height: 150),
              error: (_, _) => _InlineError(label: '今日經文暫時無法載入', onRetry: () => ref.invalidate(dailyVerseProvider)),
              data: (daily) => daily == null
                  ? const _DailyUnavailableCard()
                  : booksAsync.value == null
                      ? const _LoadingBlock(height: 150)
                      : _DailyVerseCard(daily: daily, book: booksAsync.value![daily.bookId - 1], parentRef: ref),
            ),
            const SizedBox(height: 28),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _sectionLabel(context, '最近'),
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotesScreen())),
                child: const Text('查看筆記'),
              ),
            ]),
            notesAsync.when(
              loading: () => const _LoadingBlock(height: 82),
              error: (_, _) => _InlineError(label: '最近筆記暫時無法載入', onRetry: () => ref.invalidate(allNotesProvider)),
              data: (notes) {
                if (notes.isEmpty) {
                  return Text('還沒有筆記。閱讀時選取一節經文，就可以開始記錄。', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.outline));
                }
                final books = booksAsync.value;
                if (books == null) return const _LoadingBlock(height: 82);
                return Column(children: [for (final note in notes.take(3)) _RecentNoteTile(note: note, book: books[note.bookId - 1])]);
              },
            ),
          ],
        ),
      ),
    );
  }

  static Widget _sectionLabel(BuildContext context, String text) => Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700));

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 11) return '早安';
    if (h < 18) return '下午好';
    return '晚上好';
  }

  static String _dateLabel() {
    final now = DateTime.now();
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return '${now.month} 月 ${now.day} 日・星期${weekdays[now.weekday - 1]}';
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.book, required this.chapter, required this.offset});
  final Book book;
  final int chapter;
  final double offset;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${book.name} $chapter', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        Text('回到上次閱讀的位置', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.outline)),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChapterScreen(bookId: book.id, chapter: chapter, initialOffset: offset))),
          child: const Text('繼續閱讀'),
        ),
      ]),
    ),
  );
}

class _StartReadingCard extends StatelessWidget {
  const _StartReadingCard({required this.books});
  final List<Book> books;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      leading: const Icon(Icons.auto_stories_outlined),
      title: const Text('開始第一次閱讀'),
      subtitle: const Text('從創世記第 1 章開始，之後會自動記住位置'),
      trailing: const Icon(Icons.arrow_forward),
      onTap: books.isEmpty ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChapterScreen(bookId: books.first.id, chapter: 1))),
    ),
  );
}

class _DailyVerseCard extends StatelessWidget {
  const _DailyVerseCard({required this.daily, required this.book, required this.parentRef});
  final dynamic daily;
  final Book book;
  final WidgetRef parentRef;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChapterScreen(bookId: daily.bookId, chapter: daily.chapter, focusVerse: daily.verse, updateReadingPosition: false))),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(daily.text, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.8)),
          const SizedBox(height: 12),
          Text('${book.name} ${daily.chapter}:${daily.verse}', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 4),
          Row(children: [
            const Text('查看上下文 →'),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.more_horiz),
              tooltip: '螢光筆／書籤／筆記／分享',
              onPressed: () => showVerseActionSheet(context, parentRef,
                  book: book, chapter: daily.chapter, verse: daily.verse, text: daily.text),
            ),
          ]),
        ]),
      ),
    ),
  );
}

/// 沒有官方發佈每日經文時的狀態卡（fail-closed，不顯示任何未驗證內容）。
class _DailyUnavailableCard extends StatelessWidget {
  const _DailyUnavailableCard();
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Icon(Icons.event_busy_outlined,
                color: Theme.of(context).colorScheme.outline),
            const SizedBox(width: 12),
            Expanded(
              child: Text('今日尚無官方發佈的每日經文',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline)),
            ),
          ]),
        ),
      );
}

class _RecentNoteTile extends StatelessWidget {
  const _RecentNoteTile({required this.note, required this.book});
  final Note note;
  final Book book;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text('${book.name} ${note.chapter}:${note.verse}'),
    subtitle: Text(note.content, maxLines: 2, overflow: TextOverflow.ellipsis),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChapterScreen(bookId: note.bookId, chapter: note.chapter, focusVerse: note.verse, updateReadingPosition: false))),
  );
}

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock({required this.height});
  final double height;
  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .35), borderRadius: BorderRadius.circular(18)),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.label, required this.onRetry});
  final String label;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(title: Text(label), trailing: TextButton(onPressed: onRetry, child: const Text('再試一次'))),
  );
}
