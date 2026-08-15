import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/entities.dart';
import '../data/topics.dart';
import '../models/knowledge.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/app_links.dart';
import '../services/verse_locator.dart';
import '../utils/text_utils.dart';
import 'chapter_screen.dart';
import 'topics_screen.dart';

/// 全文搜尋 + 節位快速跳轉（約3:16）+ 搜尋歷史。
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  List<VerseRef> _results = [];
  List<Topic> _topics = [];
  List<BibleEntity> _entities = [];
  ({int bookId, int chapter, int? verse})? _jump;
  bool _searched = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    final books = await ref.read(booksProvider.future);
    if (!mounted) return;
    setState(() {
      _jump = VerseLocator.parse(q, books);
      _topics = [
        for (final t in [...topics, ...situations])
          if (t.name.contains(q.trim()) || q.trim().contains(t.name)) t,
      ];
      _entities = searchEntities(q);
      // 濾掉「只是更長人名一部分」的誤配（搜「以利亞」不列「以利亞撒」的節）
      _results = ref
          .read(bibleRepositoryProvider)
          .search(q)
          .where((r) => !queryOnlyInsideLongerName(r.text, q.trim()))
          .toList();
      _searched = q.trim().isNotEmpty;
    });
  }

  /// 原子化關聯：搜尋到的「人物」若在知識庫（knowledge.people）有同名/別名
  /// 條目，回傳其唯一 id，讓結果列一鍵跨到人物生平頁。
  String? _personIdFor(BibleEntity e) {
    if (e.type != EntityType.person) return null;
    final kb = ref.read(knowledgeProvider).value ?? KnowledgeBase.empty;
    for (final p in kb.people) {
      if (p.name == e.name || p.aka.contains(e.name)) return p.id;
    }
    return null;
  }

  void _openChapter(int bookId, int chapter, {int? verse}) {
    // 有實際打開結果才記進搜尋歷史
    ref.read(searchHistoryProvider.notifier).add(_controller.text);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChapterScreen(
            bookId: bookId, chapter: chapter, focusVerse: verse),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final booksAsync = ref.watch(booksProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜尋經文，或輸入「約3:16」直接跳轉',
            border: InputBorder.none,
          ),
          onChanged: _onQueryChanged,
        ),
        actions: [
          if (_searched)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                setState(() {
                  _results = [];
                  _jump = null;
                  _searched = false;
                });
              },
            ),
        ],
      ),
      body: booksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('載入失敗：$e')),
        data: (books) {
          if (!_searched) {
            return _HistoryView(onTap: (q) {
              _controller.text = q;
              _search(q);
            });
          }
          if (_jump == null &&
              _results.isEmpty &&
              _topics.isEmpty &&
              _entities.isEmpty) {
            return const Center(child: Text('沒有找到符合的結果'));
          }
          return ListView(
            children: [
              if (_jump != null)
                _JumpTile(
                  jump: _jump!,
                  book: books[_jump!.bookId - 1],
                  onTap: () => _openChapter(
                      _jump!.bookId, _jump!.chapter,
                      verse: _jump!.verse),
                ),
              // 主題
              if (_topics.isNotEmpty) ...[
                const _SectionLabel('主題'),
                for (final t in _topics)
                  ListTile(
                    leading: Text(t.emoji,
                        style: const TextStyle(fontSize: 22)),
                    title: Text(t.name),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => TopicDetailScreen(topic: t)),
                    ),
                  ),
              ],
              // 人物／地點／事件（人物若在知識庫有生平頁，可一鍵跨過去）
              if (_entities.isNotEmpty) ...[
                const _SectionLabel('人物・地點・事件'),
                for (final e in _entities)
                  ListTile(
                    leading: Icon(_entityIcon(e.type)),
                    title: Text(e.name),
                    subtitle: Text('${entityTypeLabel(e.type)}　找出全部出現處'),
                    trailing: _personIdFor(e) != null
                        ? IconButton(
                            icon: const Icon(Icons.person_search),
                            tooltip: '人物生平頁',
                            onPressed: () => AppLinks.openPerson(
                                context, _personIdFor(e)!),
                          )
                        : null,
                    onTap: () {
                      _controller.text = e.name;
                      _search(e.name);
                    },
                  ),
              ],
              // 經文（高亮關鍵詞）
              if (_results.isNotEmpty) const _SectionLabel('經文'),
              for (final r in _results)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      // 只顯示「含關鍵詞的那一句」（斷句）＋人名/地名畫私名號
                      title: Text.rich(TextSpan(
                          children: properNameSpans(
                              context,
                              sentenceWithMatch(
                                  r.text, _controller.text.trim()),
                              query: _controller.text.trim()))),
                      subtitle: Text(
                          '${books[r.bookId - 1].name} ${r.chapter}:${r.verse}'),
                      onTap: () =>
                          _openChapter(r.bookId, r.chapter, verse: r.verse),
                    ),
                    const Divider(height: 1),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

IconData _entityIcon(EntityType t) {
  switch (t) {
    case EntityType.person:
      return Icons.person_outline;
    case EntityType.place:
      return Icons.place_outlined;
    case EntityType.event:
      return Icons.event_outlined;
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: Theme.of(context).colorScheme.primary)),
    );
  }
}

class _JumpTile extends StatelessWidget {
  final ({int bookId, int chapter, int? verse}) jump;
  final Book book;
  final VoidCallback onTap;

  const _JumpTile(
      {required this.jump, required this.book, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = jump.verse == null
        ? '${book.name} 第 ${jump.chapter} 章'
        : '${book.name} ${jump.chapter}:${jump.verse}';
    return Material(
      color: scheme.primaryContainer,
      child: ListTile(
        leading: Icon(Icons.arrow_forward, color: scheme.onPrimaryContainer),
        title: Text('跳到 $label',
            style: TextStyle(color: scheme.onPrimaryContainer)),
        onTap: onTap,
      ),
    );
  }
}

class _HistoryView extends ConsumerWidget {
  final void Function(String) onTap;

  const _HistoryView({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(searchHistoryProvider);
    if (history.isEmpty) {
      return const Center(child: Text('輸入關鍵字搜尋，或輸入節位（例：約3:16）'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('搜尋歷史', style: Theme.of(context).textTheme.titleSmall),
            TextButton(
              onPressed: () =>
                  ref.read(searchHistoryProvider.notifier).clear(),
              child: const Text('清除'),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final q in history)
              ActionChip(label: Text(q), onPressed: () => onTap(q)),
          ],
        ),
      ],
    );
  }
}
