import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../services/verse_locator.dart';
import 'chapter_screen.dart';

/// 全文搜尋 + 節位快速跳轉（約3:16）+ 搜尋歷史。
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  List<VerseRef> _results = [];
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
      _results = ref.read(bibleRepositoryProvider).search(q);
      _searched = q.trim().isNotEmpty;
    });
  }

  void _openChapter(int bookId, int chapter) {
    // 有實際打開結果才記進搜尋歷史
    ref.read(searchHistoryProvider.notifier).add(_controller.text);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChapterScreen(bookId: bookId, chapter: chapter),
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
          if (_jump == null && _results.isEmpty) {
            return const Center(child: Text('沒有找到符合的經文'));
          }
          return ListView(
            children: [
              if (_jump != null)
                _JumpTile(
                  jump: _jump!,
                  book: books[_jump!.bookId - 1],
                  onTap: () =>
                      _openChapter(_jump!.bookId, _jump!.chapter),
                ),
              for (final r in _results)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      title: Text(r.text),
                      subtitle: Text(
                          '${books[r.bookId - 1].name} ${r.chapter}:${r.verse}'),
                      onTap: () => _openChapter(r.bookId, r.chapter),
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
