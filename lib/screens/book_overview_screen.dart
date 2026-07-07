import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';

/// 導讀 / 統整 的種類。
enum OverviewKind { intro, summary }

/// 整卷書的「導讀」或「統整」頁（獨立於各章）。
/// 內容由使用者自行填在 annotations.json 的 books 區；沒有就顯示待填空白。
class BookOverviewScreen extends ConsumerWidget {
  final int bookId;
  final String bookName;
  final OverviewKind kind;

  const BookOverviewScreen({
    super.key,
    required this.bookId,
    required this.bookName,
    required this.kind,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = kind == OverviewKind.intro ? '導讀' : '統整';
    final annAsync = ref.watch(bookAnnotationProvider(bookId));

    return Scaffold(
      appBar: AppBar(title: Text('$bookName · $label')),
      body: annAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('載入失敗：$e')),
        data: (ann) {
          final hasContent = kind == OverviewKind.intro
              ? (ann?.hasIntro ?? false)
              : (ann?.hasSummary ?? false);
          if (!hasContent) return _EmptyState(label: label);
          return kind == OverviewKind.intro
              ? _IntroBody(intro: ann!.intro!)
              : _SummaryBody(text: ann!.summary!);
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String label;

  const _EmptyState({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_note, size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            Text('這卷書的$label尚未填寫',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('內容由你自己撰寫，填入 annotations.json 後這裡就會顯示。',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.outline)),
          ],
        ),
      ),
    );
  }
}

class _IntroBody extends StatelessWidget {
  final ChapterAnnotation intro;

  const _IntroBody({required this.intro});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (intro.summary != null) _field(context, '大意', intro.summary!),
        if (intro.purpose != null) _field(context, '目的', intro.purpose!),
        if (intro.author != null) _field(context, '作者', intro.author!),
        if (intro.background != null)
          _field(context, '背景', intro.background!),
        if (intro.outline.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('分段',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.secondary)),
          const SizedBox(height: 4),
          for (final line in intro.outline)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text('• $line',
                  style: Theme.of(context).textTheme.bodyLarge),
            ),
        ],
      ],
    );
  }

  Widget _field(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: scheme.secondary)),
          const SizedBox(height: 2),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(height: 1.7)),
        ],
      ),
    );
  }
}

class _SummaryBody extends StatelessWidget {
  final String text;

  const _SummaryBody({required this.text});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(text,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.8)),
      ],
    );
  }
}
