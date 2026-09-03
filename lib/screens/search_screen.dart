import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/entities.dart';
import '../models/models.dart';
import '../models/study_content.dart';
import '../providers/providers.dart';
import '../services/qa_service.dart';
import '../services/verse_locator.dart';
import '../utils/text_utils.dart';
import 'chapter_screen.dart';
import 'qa_screen.dart' show QuestionDetailScreen;
import 'study_content_screen.dart';

/// 全文搜尋 + 節位快速跳轉（約3:16）+ 搜尋歷史。
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  List<VerseRef> _results = [];
  // Church/Teacher R1：「內容」＝授權後的 study content（含 teacher teaching）＋Q&A。
  // **不再依賴 legacy knowledge/data 或 hard-coded topics。**
  List<StudyContentItem> _content = [];
  List<Question> _qa = [];
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
    final term = q.trim();
    // 「內容」＝**已授權 universe FIRST**（public ∪ my-church）→ 再 client 端文字比對。
    // church B 從未進 universe，故 count/title/preview 皆不含（rules-not-filter 契約）。
    final universe = await ref.read(authorizedStudyContentProvider.future);
    final questions = await ref.read(publishedQuestionsProvider('').future);
    if (!mounted) return;
    bool hit(String s) => term.isNotEmpty && s.contains(term);
    setState(() {
      _jump = VerseLocator.parse(q, books);
      _entities = searchEntities(q);
      _content = term.isEmpty
          ? const []
          : universe
              .where((i) =>
                  hit(i.title) ||
                  hit(i.body) ||
                  i.tags.any(hit) ||
                  i.scriptureRefs.any(hit))
              .toList();
      _qa = term.isEmpty
          ? const []
          : questions
              .where((question) =>
                  hit(question.title) || hit(question.body))
              .toList();
      _results = ref
          .read(bibleRepositoryProvider)
          .search(q)
          .where((r) => !queryOnlyInsideLongerName(r.text, term))
          .toList();
      _searched = term.isNotEmpty;
    });
  }

  void _openChapter(int bookId, int chapter, {int? verse}) {
    // 有實際打開結果才記進搜尋歷史
    ref.read(searchHistoryProvider.notifier).add(_controller.text);
    Navigator.push(
      context,
      MaterialPageRoute(
        // 搜尋結果＝臨時瀏覽，不更新一般 Reading Position
        builder: (_) => ChapterScreen(
            bookId: bookId,
            chapter: chapter,
            focusVerse: verse,
            updateReadingPosition: false),
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
                  _content = [];
                  _qa = [];
                  _entities = [];
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
              _content.isEmpty &&
              _qa.isEmpty &&
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
              // 內容（授權後的研讀內容／老師教導；church B 不會出現）
              if (_content.isNotEmpty) ...[
                const _SectionLabel('內容'),
                for (final i in _content)
                  ListTile(
                    leading: const Icon(Icons.auto_stories_outlined),
                    title: Text(i.title.isEmpty ? '(未命名)' : i.title),
                    subtitle: Text([
                      studyTypeLabel(i.contentType),
                      if (i.teacherChapterId.isNotEmpty) '老師專區',
                      if (i.audience == Audience.church) '教會專屬',
                    ].join('・')),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                StudentStudyContentDetail(item: i))),
                  ),
              ],
              // 問答
              if (_qa.isNotEmpty) ...[
                const _SectionLabel('問答'),
                for (final question in _qa)
                  ListTile(
                    leading: const Icon(Icons.forum_outlined),
                    title: Text(question.title),
                    subtitle: const Text('聖經／信仰問答'),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                QuestionDetailScreen(id: question.id))),
                  ),
              ],
              // 人物・地點・事件（名稱索引；非 knowledge/data）
              if (_entities.isNotEmpty) ...[
                const _SectionLabel('人物・地點・事件'),
                for (final e in _entities)
                  ListTile(
                    leading: Icon(_entityIcon(e.type)),
                    title: Text(e.name),
                    subtitle: Text('${entityTypeLabel(e.type)}　找出全部出現處'),
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
                      // 只顯示「含關鍵詞的那一句」（斷句），保持乾淨易讀。
                      // 私名號與關鍵詞強調只在讀經頁呈現；搜尋片段用純文字，
                      // 避免在密集清單中的 Rich text 造成過重/破圖的呈現。
                      title: Text(sentenceWithMatch(
                          r.text, _controller.text.trim())),
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
