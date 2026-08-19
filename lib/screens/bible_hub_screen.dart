import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import 'books_screen.dart';
import 'chapter_screen.dart';

/// 「聖經」主頁只負責把人帶進 Reader，不承擔工具箱角色。
class BibleHubScreen extends ConsumerWidget {
  const BibleHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastRead = ref.watch(lastReadProvider);
    final books = ref.watch(booksProvider).value;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          Text('聖經', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('選擇一卷書，或從上次的位置繼續。', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.outline)),
          const SizedBox(height: 28),
          if (lastRead != null && books != null) ...[
            Text('繼續閱讀', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                leading: const Icon(Icons.auto_stories_outlined),
                title: Text('${books[lastRead.bookId - 1].name} 第 ${lastRead.chapter} 章'),
                subtitle: const Text('回到上次閱讀位置'),
                trailing: const Icon(Icons.arrow_forward),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ChapterScreen(bookId: lastRead.bookId, chapter: lastRead.chapter, initialOffset: lastRead.offset),
                )),
              ),
            ),
            const SizedBox(height: 28),
          ],
          Text('開始閱讀', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BooksScreen())),
            icon: const Icon(Icons.menu_book_outlined),
            label: const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('選擇書卷與章節')),
          ),
          const SizedBox(height: 14),
          Text('進入閱讀後可快速換章、選取經文、螢光筆、書籤與筆記。', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
        ],
      ),
    );
  }
}
