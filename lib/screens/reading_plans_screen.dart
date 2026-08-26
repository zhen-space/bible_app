import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/reading_plans.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import 'chapter_screen.dart';

/// 讀經計畫列表：內建機械排程計畫，顯示各自進度，點進去逐日勾選。
class ReadingPlansScreen extends ConsumerWidget {
  const ReadingPlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(planDoneCountsProvider).value ?? const {};
    return Scaffold(
      appBar: AppBar(title: const Text('讀經計畫')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final p in readingPlans)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Text(p.emoji,
                    style: const TextStyle(fontSize: 28)),
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
                          done: counts[p.id] ?? 0, total: p.days),
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
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final int done;
  final int total;

  const _ProgressBar({required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    final frac = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
                value: frac, minHeight: 7),
          ),
        ),
        const SizedBox(width: 8),
        Text('$done / $total',
            style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

/// 單一計畫：逐日列表，可勾選完成、點章進入讀經。
class ReadingPlanDetailScreen extends ConsumerWidget {
  final ReadingPlan plan;

  const ReadingPlanDetailScreen({super.key, required this.plan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(booksProvider);
    final done = ref.watch(planProgressProvider(plan.id)).value ?? const {};

    return Scaffold(
      appBar: AppBar(title: Text('${plan.emoji} ${plan.name}')),
      body: booksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('載入失敗：$e')),
        data: (books) {
          final schedule = plan.schedule(books);
          return ListView.builder(
            itemCount: schedule.length,
            itemBuilder: (context, i) {
              final day = i + 1;
              final chapters = schedule[i];
              final isDone = done.contains(day);
              return ExpansionTile(
                leading: Checkbox(
                  value: isDone,
                  onChanged: (v) async {
                    await ref
                        .read(databaseServiceProvider)
                        .setPlanDayDone(plan.id, day, v ?? false);
                    ref.invalidate(planProgressProvider(plan.id));
                    ref.invalidate(planDoneCountsProvider);
                  },
                ),
                title: Text('第 $day 天',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration:
                            isDone ? TextDecoration.lineThrough : null)),
                subtitle: Text(_rangeLabel(books, chapters)),
                children: [
                  for (final c in chapters)
                    ListTile(
                      dense: true,
                      contentPadding:
                          const EdgeInsets.only(left: 72, right: 16),
                      title: Text(
                          '${books[c.bookId - 1].name} 第 ${c.chapter} 章'),
                      trailing: const Icon(Icons.menu_book, size: 18),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          // Plan Reader context 不覆蓋一般 Reading Position
                          builder: (_) => ChapterScreen(
                              bookId: c.bookId,
                              chapter: c.chapter,
                              updateReadingPosition: false),
                        ),
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
