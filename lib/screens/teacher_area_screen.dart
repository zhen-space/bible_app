import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/study_content.dart';
import '../models/teacher.dart';
import '../providers/providers.dart';
import 'study_content_screen.dart' show StudentStudyContentDetail, churchBadge;

/// 老師專區（Student）——只顯示 **authorized** Book → Chapter → Teaching。
/// Teaching 本體＝Study Content，點擊 reuse StudentStudyContentDetail（不建第二套）。
class TeacherAreaScreen extends ConsumerWidget {
  const TeacherAreaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(authorizedTeacherBooksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('老師專區')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const _Empty('目前無法載入老師專區。'),
        data: (books) => books.isEmpty
            ? const _Empty('目前沒有可瀏覽的老師專區內容。')
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final b in books)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.menu_book_outlined),
                        title: Text(b.title.isEmpty ? b.id : b.title,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (b.audience == Audience.church)
                              churchBadge(context),
                            if (b.description.isNotEmpty)
                              Text(b.description,
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => TeacherBookDetailScreen(book: b))),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class TeacherBookDetailScreen extends ConsumerWidget {
  final TeacherBook book;
  const TeacherBookDetailScreen({super.key, required this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(authorizedTeacherChaptersProvider(book.id));
    return Scaffold(
      appBar: AppBar(title: Text(book.title.isEmpty ? '老師專區' : book.title)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const _Empty('目前無法載入。'),
        data: (chapters) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (book.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(book.description,
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
            if (chapters.isEmpty) const _Empty('此書卷目前沒有可瀏覽的章。'),
            for (final c in chapters)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  title: Text(c.title.isEmpty ? c.id : c.title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle:
                      c.audience == Audience.church ? churchBadge(context) : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => TeacherChapterScreen(chapter: c))),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class TeacherChapterScreen extends ConsumerWidget {
  final TeacherChapter chapter;
  const TeacherChapterScreen({super.key, required this.chapter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(authorizedTeachingsProvider(chapter.id));
    return Scaffold(
      appBar: AppBar(title: Text(chapter.title.isEmpty ? '章' : chapter.title)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const _Empty('目前無法載入。'),
        data: (teachings) => teachings.isEmpty
            ? const _Empty('此章目前沒有可瀏覽的教導內容。')
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final t in teachings)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.article_outlined),
                        title: Text(t.title.isEmpty ? '(未命名)' : t.title,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: t.audience == Audience.church
                            ? churchBadge(context)
                            : null,
                        trailing: const Icon(Icons.chevron_right),
                        // Teaching 本體＝Study Content → reuse detail。
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    StudentStudyContentDetail(item: t))),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String message;
  const _Empty(this.message);
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.outline)),
        ),
      );
}
