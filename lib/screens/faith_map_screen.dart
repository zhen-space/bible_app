import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import 'books_screen.dart';
import 'chapter_screen.dart';

/// 我的信仰地圖：把 66 卷書畫成方格，依「已讀章數比例」上色，
/// 一眼看到自己讀過哪裡、哪裡還沒去。點方格進該卷。
class FaithMapScreen extends ConsumerWidget {
  const FaithMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(booksProvider);
    final map = ref.watch(faithMapProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('我的信仰地圖')),
      body: booksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('載入失敗：$e')),
        data: (books) {
          final read = map?.read ?? const {};
          final totalRead = read.values.fold<int>(0, (a, b) => a + b);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _legend(context, totalRead),
              const SizedBox(height: 16),
              _section(context, '舊約',
                  books.where((b) => b.testament == 'ot').toList(), read),
              const SizedBox(height: 16),
              _section(context, '新約',
                  books.where((b) => b.testament == 'nt').toList(), read),
            ],
          );
        },
      ),
    );
  }

  Widget _legend(BuildContext context, int totalRead) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('已讀 $totalRead / 1189 章',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Row(
              children: [
                Text('顏色越深＝讀得越多　',
                    style: Theme.of(context).textTheme.bodySmall),
                for (final f in [0.0, 0.3, 0.6, 1.0])
                  Container(
                    width: 22,
                    height: 14,
                    margin: const EdgeInsets.only(right: 3),
                    decoration: BoxDecoration(
                      color: _shade(context, f),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(
      BuildContext context, String title, List<Book> books, Map<int, int> read) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final b in books)
              _BookCell(
                book: b,
                fraction: b.chapterCount == 0
                    ? 0
                    : (read[b.id] ?? 0) / b.chapterCount,
              ),
          ],
        ),
      ],
    );
  }
}

Color _shade(BuildContext context, double fraction) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (fraction <= 0) {
    return isDark ? const Color(0xFF16324B) : const Color(0xFFEDF1F5);
  }
  // 由淺藍到品牌深藍
  return Color.lerp(
      AppTheme.paleBlue.withValues(alpha: 0.4),
      const Color(0xFF005B98),
      fraction.clamp(0, 1))!;
}

class _BookCell extends StatelessWidget {
  final Book book;
  final double fraction;

  const _BookCell({required this.book, required this.fraction});

  @override
  Widget build(BuildContext context) {
    final bg = _shade(context, fraction);
    // 深底用白字、淺底用黑字
    final onBg =
        fraction >= 0.45 ? Colors.white : Theme.of(context).colorScheme.onSurface;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => book.chapterCount == 1
              ? ChapterScreen(bookId: book.id, chapter: 1)
              : const BooksScreen(),
        ),
      ),
      child: Container(
        width: 76,
        height: 56,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(book.name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: onBg,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            Text('${(fraction * 100).round()}%',
                style: TextStyle(
                    color: onBg.withValues(alpha: 0.8), fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
