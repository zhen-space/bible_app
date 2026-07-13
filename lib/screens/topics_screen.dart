import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/topics.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/verse_locator.dart';
import 'chapter_screen.dart';
import 'reading_plans_screen.dart';

/// 主題式閱讀 + 人生情境入口。
class TopicsScreen extends ConsumerWidget {
  const TopicsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('主題閱讀')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Text('🗓️', style: TextStyle(fontSize: 26)),
              title: const Text('讀經計畫',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('一年通讀、90 天速讀、新約計畫'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ReadingPlansScreen()),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('現在的心情…',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _TopicWrap(items: situations),
          const SizedBox(height: 24),
          Text('依主題讀經',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _TopicWrap(items: topics),
        ],
      ),
    );
  }
}

class _TopicWrap extends StatelessWidget {
  final List<Topic> items;

  const _TopicWrap({required this.items});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in items)
          ActionChip(
            avatar: Text(t.emoji),
            label: Text(t.name),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => TopicDetailScreen(topic: t)),
            ),
          ),
      ],
    );
  }
}

/// 單一主題的經文列表。
class TopicDetailScreen extends ConsumerWidget {
  final Topic topic;

  const TopicDetailScreen({super.key, required this.topic});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(booksProvider);

    return Scaffold(
      appBar: AppBar(title: Text('${topic.emoji} ${topic.name}')),
      body: booksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('載入失敗：$e')),
        data: (books) {
          final verses = <VerseRef>[];
          for (final r in topic.refs) {
            final loc = VerseLocator.parse(r, books);
            if (loc == null || loc.verse == null) continue;
            verses.add(VerseRef(
              bookId: loc.bookId,
              chapter: loc.chapter,
              verse: loc.verse!,
              text: books[loc.bookId - 1].chapters[loc.chapter - 1]
                  [loc.verse! - 1],
            ));
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: verses.length + 1,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              if (i == 0) {
                // 主題導讀卡（有內容才顯示，內容由使用者撰寫）
                if (topic.intro.trim().isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('導讀',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary)),
                          const SizedBox(height: 6),
                          Text(topic.intro,
                              style: const TextStyle(height: 1.7)),
                        ],
                      ),
                    ),
                  ),
                );
              }
              final v = verses[i - 1];
              final book = books[v.bookId - 1];
              return ListTile(
                title: Text(v.text, style: const TextStyle(height: 1.6)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('—${book.name} ${v.chapter}:${v.verse}'),
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChapterScreen(
                        bookId: v.bookId, chapter: v.chapter),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
