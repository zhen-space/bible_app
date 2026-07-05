import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import 'chapter_screen.dart';

/// 全文搜尋。
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  List<VerseRef> _results = [];
  bool _searched = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      // 確保經文已載入再搜尋
      await ref.read(booksProvider.future);
      if (!mounted) return;
      setState(() {
        _results = ref.read(bibleRepositoryProvider).search(q);
        _searched = q.trim().isNotEmpty;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final booksAsync = ref.watch(booksProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜尋經文…',
            border: InputBorder.none,
          ),
          onChanged: _onQueryChanged,
        ),
      ),
      body: booksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('載入失敗：$e')),
        data: (books) {
          if (!_searched) {
            return const Center(child: Text('輸入關鍵字搜尋全部經文'));
          }
          if (_results.isEmpty) {
            return const Center(child: Text('沒有找到符合的經文'));
          }
          return ListView.separated(
            itemCount: _results.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final r = _results[i];
              final book = books[r.bookId - 1];
              return ListTile(
                title: Text(r.text),
                subtitle: Text('${book.name} ${r.chapter}:${r.verse}'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChapterScreen(
                        bookId: r.bookId, chapter: r.chapter),
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
