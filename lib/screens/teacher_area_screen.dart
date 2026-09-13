import 'package:flutter/material.dart' hide Visibility;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/study_content.dart';
import '../models/teacher.dart';
import '../providers/providers.dart';
import 'study_content_screen.dart' show StudentStudyContentDetail;

/// 學生「老師專區」：授權 Books → 授權 Chapters → 授權 Teachings（＝Study Content）。
///
/// 硬性：**全程只用 authorization-aware providers**（authorizedTeacherBooks/Chapters/
/// Teachings、fetchAuthorizedTeachingsAll）；未授權的 Church/Internal 內容永不進入清單、
/// 搜尋、預覽。入口本身由 [teacherEntryVisibleProvider]（capability）於 Bible Hub 控制。
/// teaching 詳情 reuse [StudentStudyContentDetail]，不另建第二套顯示。
class TeacherAreaScreen extends ConsumerWidget {
  const TeacherAreaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(authorizedTeacherBooksProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('老師專區'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜尋老師專區',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TeacherSearchScreen())),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const _TeacherEmpty('內容載入失敗，請稍後再試。'),
        data: (books) => books.isEmpty
            ? const _TeacherEmpty('目前尚無可閱讀的老師專區內容。')
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final b in books)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.menu_book_outlined),
                        title: Text(b.title.isEmpty ? b.id : b.title,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: b.description.isEmpty
                            ? (b.audience == Audience.church
                                ? const Text('教會專屬')
                                : null)
                            : Text(b.description,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => TeacherBookScreen(book: b))),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// 授權 Book → 授權 Chapters。
class TeacherBookScreen extends ConsumerWidget {
  final TeacherBook book;
  const TeacherBookScreen({super.key, required this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(authorizedTeacherChaptersProvider(book.id));
    return Scaffold(
      appBar: AppBar(title: Text(book.title.isEmpty ? book.id : book.title)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const _TeacherEmpty('章節載入失敗，請稍後再試。'),
        data: (chapters) => chapters.isEmpty
            ? const _TeacherEmpty('這個書卷目前沒有可閱讀的章節。')
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final c in chapters)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.article_outlined),
                        title: Text(c.title.isEmpty ? c.id : c.title,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    TeacherChapterScreen(chapter: c))),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// 授權 Chapter → 授權 Teachings（study content）。
class TeacherChapterScreen extends ConsumerWidget {
  final TeacherChapter chapter;
  const TeacherChapterScreen({super.key, required this.chapter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(authorizedTeachingsProvider(chapter.id));
    return Scaffold(
      appBar:
          AppBar(title: Text(chapter.title.isEmpty ? chapter.id : chapter.title)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const _TeacherEmpty('教導內容載入失敗，請稍後再試。'),
        data: (teachings) => teachings.isEmpty
            ? const _TeacherEmpty('這一章目前沒有可閱讀的教導內容。')
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [for (final t in teachings) _teachingTile(context, t)],
              ),
      ),
    );
  }
}

Widget _teachingTile(BuildContext context, StudyContentItem t) => Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.menu_book),
        title: Text(t.title.isEmpty ? '(未命名)' : t.title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: t.body.isEmpty
            ? (t.audience == Audience.church ? const Text('教會專屬') : null)
            : Text(t.body, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => StudentStudyContentDetail(item: t))),
      ),
    );

/// 老師專區內搜尋：只搜**已授權** teacher teaching 的 title + body。
/// 授權 universe 由 [authorizedTeachingsAllProvider] 提供，未授權內容永不出現。
class TeacherSearchScreen extends ConsumerStatefulWidget {
  const TeacherSearchScreen({super.key});
  @override
  ConsumerState<TeacherSearchScreen> createState() =>
      _TeacherSearchScreenState();
}

class _TeacherSearchScreenState extends ConsumerState<TeacherSearchScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(authorizedTeachingsAllProvider);
    final q = _q.trim().toLowerCase();
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
              hintText: '搜尋老師專區教導（標題、內文）', border: InputBorder.none),
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const _TeacherEmpty('搜尋暫時無法使用，請稍後再試。'),
        data: (all) {
          if (q.isEmpty) {
            return const _TeacherEmpty('輸入關鍵字，搜尋你可閱讀的老師專區教導。');
          }
          final hits = all
              .where((t) =>
                  t.title.toLowerCase().contains(q) ||
                  t.body.toLowerCase().contains(q))
              .toList();
          if (hits.isEmpty) return const _TeacherEmpty('找不到符合的教導內容。');
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [for (final t in hits) _teachingTile(context, t)],
          );
        },
      ),
    );
  }
}

class _TeacherEmpty extends StatelessWidget {
  final String message;
  const _TeacherEmpty(this.message);
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline)),
        ),
      );
}
