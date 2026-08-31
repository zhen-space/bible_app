import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import 'books_screen.dart';
import 'chapter_screen.dart';
import 'knowledge_screen.dart';
import 'qa_screen.dart';
import 'search_screen.dart';

/// 「聖經」主頁：閱讀（進 Reader／搜尋）＋理解（問答／研讀內容）。
/// 只負責把人帶到既有畫面，不重寫任何底層功能。
class BibleHubScreen extends ConsumerWidget {
  const BibleHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastRead = ref.watch(lastReadProvider);
    final books = ref.watch(booksProvider).value;
    final outline = Theme.of(context).colorScheme.outline;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          Text('聖經',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('選擇一卷書、搜尋經文，或深入理解。',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: outline)),
          const SizedBox(height: 28),

          // ---- 閱讀 ----
          _sectionTitle(context, '閱讀'),
          const SizedBox(height: 10),
          if (lastRead != null && books != null) ...[
            Card(
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                leading: const Icon(Icons.auto_stories_outlined),
                title:
                    Text('${books[lastRead.bookId - 1].name} 第 ${lastRead.chapter} 章'),
                subtitle: const Text('回到上次閱讀位置'),
                trailing: const Icon(Icons.arrow_forward),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ChapterScreen(
                      bookId: lastRead.bookId,
                      chapter: lastRead.chapter,
                      initialOffset: lastRead.offset),
                )),
              ),
            ),
            const SizedBox(height: 10),
          ],
          _tile(context, Icons.menu_book_outlined, '閱讀聖經', '選擇書卷與章節',
              () => const BooksScreen()),
          _tile(context, Icons.search, '搜尋經文', '全文搜尋、節位快速跳轉',
              () => const SearchScreen()),

          const SizedBox(height: 28),

          // ---- 理解 ----
          _sectionTitle(context, '理解'),
          const SizedBox(height: 10),
          _tile(context, Icons.forum_outlined, '聖經／信仰問答',
              '人工整理的已發布問答', () => const QaScreen()),
          _tile(context, Icons.auto_stories, '研讀內容',
              '時間軸、人物、平行對照、預表、主題', () => const KnowledgeScreen()),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Text(text,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w700));

  Widget _tile(BuildContext context, IconData icon, String title,
          String subtitle, Widget Function() screen) =>
      Card(
        margin: const EdgeInsets.symmetric(vertical: 5),
        child: ListTile(
          leading: Icon(icon),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => screen())),
        ),
      );
}
