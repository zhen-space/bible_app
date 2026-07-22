import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import 'bookmarks_screen.dart';
import 'books_screen.dart';
import 'chapter_screen.dart';
import 'knowledge_screen.dart';
import 'prayers_screen.dart';
import 'qa_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'topics_screen.dart';

/// 全聖經總章數（66 卷合計），讀經進度分母。
const int kTotalChapters = 1189;

/// 首頁：引導式入口——今日經文、繼續閱讀、四大入口卡。
/// 書卷列表在「讀聖經」（BooksScreen）。
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastRead = ref.watch(lastReadProvider);
    final books = ref.watch(booksProvider).value;
    // 禱告事項區塊位置由使用者在設定選（top＝繼續閱讀下、bottom＝整頁下面）
    final prayerPos = ref.watch(prayerPositionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('聖經 · 和合本'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '設定',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _DailyVerseCard(),
          const SizedBox(height: 12),
          if (lastRead != null && books != null) ...[
            _ContinueReadingCard(
              book: books[lastRead.bookId - 1],
              chapter: lastRead.chapter,
              offset: lastRead.offset,
            ),
            const SizedBox(height: 12),
          ],
          if (prayerPos == 'top') ...[
            const _PrayerSection(),
            const SizedBox(height: 12),
          ],
          // 四大入口（2×2；不用 GridView，避免捲動父層衝突）
          Row(
            children: [
              _EntryCard(
                icon: Icons.menu_book,
                label: '讀聖經',
                subtitle: '66 卷書',
                onTap: () => _push(context, const BooksScreen()),
              ),
              const SizedBox(width: 12),
              _EntryCard(
                icon: Icons.category_outlined,
                label: '主題閱讀',
                subtitle: '主題與心情',
                onTap: () => _push(context, const TopicsScreen()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _EntryCard(
                icon: Icons.search,
                label: '搜尋',
                subtitle: '經文與節位',
                onTap: () => _push(context, const SearchScreen()),
              ),
              const SizedBox(width: 12),
              _EntryCard(
                icon: Icons.collections_bookmark_outlined,
                label: '我的標記',
                subtitle: '書籤與筆記',
                onTap: () => _push(context, const BookmarksScreen()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(Icons.forum_outlined,
                  color: Theme.of(context).colorScheme.secondary),
              title: const Text('疑問 Q&A',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('提問、看解答（全人工回答）'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(context, const QaScreen()),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(Icons.account_tree_outlined,
                  color: Theme.of(context).colorScheme.secondary),
              title: const Text('聖經知識庫',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('時間軸、人物、平行對照、預表應驗'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(context, const KnowledgeScreen()),
            ),
          ),
          const SizedBox(height: 16),
          const _ReadingProgressBar(),
          const _RecentNotesSection(),
          if (prayerPos == 'bottom') ...[
            const SizedBox(height: 8),
            const _PrayerSection(),
          ],
        ],
      ),
    );
  }

  static void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}

/// 入口卡（首頁 2×2）。
class _EntryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _EntryCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              children: [
                Icon(icon, size: 32, color: scheme.secondary), // 金
                const SizedBox(height: 8),
                Text(label,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.outline)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 每日經文卡片。
class _DailyVerseCard extends ConsumerWidget {
  const _DailyVerseCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daily = ref.watch(dailyVerseProvider).value;
    final books = ref.watch(booksProvider).value;
    if (daily == null || books == null) {
      // 佔位，避免載入完成時版面跳動
      return const SizedBox(height: 120);
    }
    final book = books[daily.bookId - 1];
    const onCard = Colors.white; // 漸層藍上一律白字

    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.brandGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ChapterScreen(bookId: daily.bookId, chapter: daily.chapter),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('今日經文',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: onCard)),
              const SizedBox(height: 8),
              Text(daily.text,
                  style: TextStyle(
                      fontSize: 17,
                      height: 1.7,
                      color: onCard)),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '—${book.name} ${daily.chapter}:${daily.verse}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: onCard),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 繼續閱讀卡。點了回到上次「讀到的畫面」（還原捲動位置，不只是章頂）。
class _ContinueReadingCard extends StatelessWidget {
  final Book book;
  final int chapter;
  final double offset;

  const _ContinueReadingCard(
      {required this.book, required this.chapter, required this.offset});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.auto_stories),
        title: Text('繼續閱讀：${book.name} 第 $chapter 章'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChapterScreen(
                bookId: book.id, chapter: chapter, initialOffset: offset),
          ),
        ),
      ),
    );
  }
}

/// 讀經進度（已讀章數 / 1189）。
class _ReadingProgressBar extends ConsumerWidget {
  const _ReadingProgressBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(readChapterCountProvider).value ?? 0;
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: count / kTotalChapters,
                minHeight: 6,
                color: AppTheme.accentBlue,
                backgroundColor: AppTheme.paleBlue.withValues(alpha: 0.35),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('已讀 $count / $kTotalChapters 章',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// 首頁「我的筆記」預覽：最近筆記橫向捲動，點開回到該節。
class _RecentNotesSection extends ConsumerWidget {
  const _RecentNotesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(allNotesProvider).value ?? const <Note>[];
    final books = ref.watch(booksProvider).value;
    if (notes.isEmpty || books == null) return const SizedBox.shrink();
    final recent = notes.take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('我的筆記', style: Theme.of(context).textTheme.titleSmall),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const BookmarksScreen(initialTab: 2)),
                ),
                child: const Text('看全部'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: recent.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final n = recent[i];
              final book = books[n.bookId - 1];
              return SizedBox(
                width: 200,
                child: Card(
                  margin: EdgeInsets.zero,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChapterScreen(
                            bookId: n.bookId, chapter: n.chapter),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${book.name} ${n.chapter}:${n.verse}',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary)),
                          const SizedBox(height: 4),
                          Expanded(
                            child: Text(
                              n.content,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 首頁「禱告事項」區塊：預覽最近幾則（分類·子分類｜內容），
/// 點「看全部」進完整頁面新增/編輯；沒有內容時顯示引導卡。
class _PrayerSection extends ConsumerWidget {
  const _PrayerSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prayers = ref.watch(allPrayersProvider).value ?? const <Prayer>[];
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Icon(Icons.volunteer_activism_outlined,
                    size: 18, color: scheme.secondary),
                const SizedBox(width: 6),
                Text('禱告事項',
                    style: Theme.of(context).textTheme.titleSmall),
              ]),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PrayersScreen()),
                ),
                child: Text(prayers.isEmpty ? '新增' : '看全部'),
              ),
            ],
          ),
        ),
        if (prayers.isEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(Icons.add_circle_outline,
                  color: scheme.secondary),
              title: const Text('寫下你的禱告事項'),
              subtitle: const Text('可自訂分類與子分類（例：家人 · 爸爸）'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PrayersScreen()),
              ),
            ),
          )
        else
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final p in prayers.take(3))
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.circle,
                        size: 8, color: scheme.secondary),
                    title: Text(p.content,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text([
                      if (p.category.isNotEmpty) p.category,
                      if (p.subcategory.isNotEmpty) p.subcategory,
                    ].join(' · ')),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const PrayersScreen()),
                    ),
                  ),
                if (prayers.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('共 ${prayers.length} 則',
                        style: Theme.of(context).textTheme.labelSmall),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
