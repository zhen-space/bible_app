import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/reading_plans.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import 'chapter_screen.dart';

/// 讀經計畫列表（v2）：內建機械排程計畫，顯示「已完成項目 / 總項目」進度，
/// 點進去逐「讀經項目（章）」勾選。官方 Published 計畫需後端，之後接。
class ReadingPlansScreen extends ConsumerWidget {
  const ReadingPlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(planItemDoneCountsProvider).value ?? const {};
    final booksAsync = ref.watch(booksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('讀經計畫')),
      body: booksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('載入失敗：$e')),
        data: (books) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final p in readingPlans)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Text(p.emoji, style: const TextStyle(fontSize: 28)),
                  title: Text(p.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.subtitle),
                        const SizedBox(height: 8),
                        _ProgressBar(
                            done: counts[p.id] ?? 0,
                            total: p.flatChapters(books).length,
                            unit: '章'),
                      ],
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ReadingPlanDetailScreen(plan: p)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final int done;
  final int total;
  final String unit;

  const _ProgressBar(
      {required this.done, required this.total, this.unit = ''});

  @override
  Widget build(BuildContext context) {
    final frac = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: frac, minHeight: 7),
          ),
        ),
        const SizedBox(width: 8),
        Text('$done / $total$unit',
            style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

/// 單一計畫（v2）：逐「讀經項目」勾選；今日進度與整體進度分離；漏讀保留。
class ReadingPlanDetailScreen extends ConsumerStatefulWidget {
  final ReadingPlan plan;

  const ReadingPlanDetailScreen({super.key, required this.plan});

  @override
  ConsumerState<ReadingPlanDetailScreen> createState() =>
      _ReadingPlanDetailScreenState();
}

class _ReadingPlanDetailScreenState
    extends ConsumerState<ReadingPlanDetailScreen> {
  bool _seeded = false;

  ReadingPlan get plan => widget.plan;

  /// 一次性把舊版「整天完成」攤平成逐項目（只在還沒有 v2 進度時）。
  Future<void> _maybeSeedFromLegacy(List<List<ChapterRef>> schedule) async {
    if (_seeded) return;
    _seeded = true;
    final dayItems = <int, List<List<int>>>{
      for (var i = 0; i < schedule.length; i++)
        i + 1: [for (final c in schedule[i]) [c.bookId, c.chapter]],
    };
    final n = await ref
        .read(databaseServiceProvider)
        .seedPlanItemsFromDays(plan.id, dayItems);
    if (n > 0 && mounted) {
      ref.invalidate(planItemProgressProvider(plan.id));
      ref.invalidate(planItemDoneCountsProvider);
    }
  }

  Future<void> _setItem(int day, ChapterRef c, bool done) async {
    await ref
        .read(databaseServiceProvider)
        .setPlanItemDone(plan.id, day, c.bookId, c.chapter, done);
    ref.invalidate(planItemProgressProvider(plan.id));
    ref.invalidate(planItemDoneCountsProvider);
  }

  Future<void> _setDay(
      int day, List<ChapterRef> chapters, bool done) async {
    final db = ref.read(databaseServiceProvider);
    for (final c in chapters) {
      await db.setPlanItemDone(plan.id, day, c.bookId, c.chapter, done);
    }
    ref.invalidate(planItemProgressProvider(plan.id));
    ref.invalidate(planItemDoneCountsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final booksAsync = ref.watch(booksProvider);
    final progress = ref.watch(planItemProgressProvider(plan.id)).value;

    return Scaffold(
      appBar: AppBar(title: Text('${plan.emoji} ${plan.name}')),
      body: booksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('載入失敗：$e')),
        data: (books) {
          final schedule = plan.schedule(books);
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _maybeSeedFromLegacy(schedule));
          final done = progress ?? const <String>{};
          String key(ChapterRef c) => 'b${c.bookId}_c${c.chapter}';
          bool itemDone(ChapterRef c) => done.contains(key(c));
          bool dayDone(List<ChapterRef> ch) => ch.every(itemDone);

          final total = schedule.fold<int>(0, (a, d) => a + d.length);
          final overallDone = schedule.fold<int>(
              0, (a, d) => a + d.where(itemDone).length);

          // 「今日」＝第一個尚未全部完成的天（進行中的那一天）；全完成則停在最後一天。
          var todayIdx = schedule.indexWhere((d) => !dayDone(d));
          if (todayIdx < 0) todayIdx = schedule.length - 1;
          final todayChapters =
              schedule.isEmpty ? <ChapterRef>[] : schedule[todayIdx];
          final todayDoneCount = todayChapters.where(itemDone).length;

          return ListView.builder(
            itemCount: schedule.length + 1,
            itemBuilder: (context, idx) {
              if (idx == 0) {
                return _HeaderCard(
                  todayDay: todayIdx + 1,
                  todayDone: todayDoneCount,
                  todayTotal: todayChapters.length,
                  overallDone: overallDone,
                  overallTotal: total,
                  books: books,
                  todayChapters: todayChapters,
                  onOpen: (c) => _openReader(c),
                );
              }
              final i = idx - 1;
              final day = i + 1;
              final chapters = schedule[i];
              final isToday = i == todayIdx;
              // 漏讀＝在「今日」之前、卻還沒全部完成的天（保留、不自動清）。
              final isMissed = i < todayIdx && !dayDone(chapters);
              return ExpansionTile(
                initiallyExpanded: isToday,
                leading: Checkbox(
                  value: dayDone(chapters),
                  tristate: true,
                  onChanged: (_) =>
                      _setDay(day, chapters, !dayDone(chapters)),
                ),
                title: Row(
                  children: [
                    Text('第 $day 天',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            decoration: dayDone(chapters)
                                ? TextDecoration.lineThrough
                                : null)),
                    const SizedBox(width: 8),
                    if (isToday) _tag(context, '今日', Theme.of(context).colorScheme.primary),
                    if (isMissed) _tag(context, '漏讀', Theme.of(context).colorScheme.error),
                  ],
                ),
                subtitle: Text(
                    '${_rangeLabel(books, chapters)}　'
                    '(${chapters.where(itemDone).length}/${chapters.length})'),
                children: [
                  for (final c in chapters)
                    CheckboxListTile(
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      contentPadding:
                          const EdgeInsets.only(left: 52, right: 8),
                      value: itemDone(c),
                      onChanged: (v) => _setItem(day, c, v ?? false),
                      title: Text(
                          '${books[c.bookId - 1].name} 第 ${c.chapter} 章'),
                      secondary: IconButton(
                        icon: const Icon(Icons.menu_book, size: 18),
                        tooltip: '閱讀',
                        onPressed: () => _openReader(c),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _openReader(ChapterRef c) => Navigator.push(
        context,
        MaterialPageRoute(
          // Plan Reader context 不覆蓋一般 Reading Position
          builder: (_) => ChapterScreen(
              bookId: c.bookId,
              chapter: c.chapter,
              updateReadingPosition: false),
        ),
      );

  Widget _tag(BuildContext context, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700)),
      );

  /// 例：「創世記 1 – 創世記 4」或單章「約翰福音 3」。
  String _rangeLabel(List<Book> books, List<ChapterRef> chapters) {
    if (chapters.isEmpty) return '';
    final first = chapters.first;
    final last = chapters.last;
    final a = '${books[first.bookId - 1].name} ${first.chapter}';
    if (first.bookId == last.bookId && first.chapter == last.chapter) {
      return a;
    }
    final b = '${books[last.bookId - 1].name} ${last.chapter}';
    return '$a – $b（共 ${chapters.length} 章）';
  }
}

class _HeaderCard extends StatelessWidget {
  final int todayDay;
  final int todayDone;
  final int todayTotal;
  final int overallDone;
  final int overallTotal;
  final List<Book> books;
  final List<ChapterRef> todayChapters;
  final void Function(ChapterRef) onOpen;

  const _HeaderCard({
    required this.todayDay,
    required this.todayDone,
    required this.todayTotal,
    required this.overallDone,
    required this.overallTotal,
    required this.books,
    required this.todayChapters,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('今日進度（第 $todayDay 天）',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _ProgressBar(done: todayDone, total: todayTotal, unit: '章'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final c in todayChapters)
                  ActionChip(
                    avatar: const Icon(Icons.menu_book, size: 16),
                    label: Text(
                        '${books[c.bookId - 1].name} ${c.chapter}'),
                    onPressed: () => onOpen(c),
                  ),
              ],
            ),
            const Divider(height: 24),
            Text('整體進度',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 8),
            _ProgressBar(done: overallDone, total: overallTotal, unit: '章'),
          ],
        ),
      ),
    );
  }
}
