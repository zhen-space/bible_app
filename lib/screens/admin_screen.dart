import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';

/// 內容管理後台（只有管理者帳號看得到入口）。
/// 在這裡撰寫：整卷導讀/統整、章導讀/章重點、每節註解。
/// 存進 Firestore `annotations`，所有讀者即時看到；asset JSON 只是離線底稿。
class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(booksProvider);
    final pendingCount =
        ref.watch(pendingSubmissionsProvider).value?.length ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('內容管理')),
      body: booksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('載入失敗：$e')),
        data: (books) => ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.rate_review_outlined),
              title: const Text('公開註解審核'),
              subtitle: Text(
                  pendingCount > 0 ? '$pendingCount 則待審' : '目前沒有待審投稿'),
              trailing: pendingCount > 0
                  ? CircleAvatar(
                      radius: 12,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: Text('$pendingCount',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white)))
                  : const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminReviewScreen()),
              ),
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('撰寫導讀／註解'),
            ),
            for (final book in books)
              ListTile(
                leading: CircleAvatar(child: Text(book.abbr)),
                title: Text(book.name),
                subtitle: Text('${book.chapterCount} 章'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => AdminBookScreen(book: book)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 公開註解審核佇列。通過→公開；退回→不顯示。
class AdminReviewScreen extends ConsumerWidget {
  const AdminReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingSubmissionsProvider);
    final books = ref.watch(booksProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('公開註解審核')),
      body: pendingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('載入失敗：$e')),
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('目前沒有待審投稿'));
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final s = items[i];
              final ref2 = books != null
                  ? '${books[s.bookId - 1].name} ${s.chapter}:${s.verse}'
                  : '${s.bookId}:${s.chapter}:${s.verse}';
              return ListTile(
                title: Text(s.content),
                subtitle: Text(
                    '$ref2　${s.author.isEmpty ? "匿名" : s.author}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.check_circle_outline),
                      color: Colors.green,
                      tooltip: '通過',
                      onPressed: () async {
                        final m = ScaffoldMessenger.of(context);
                        try {
                          await ref
                              .read(contentServiceProvider)
                              .approveSubmission(s);
                          ref.invalidate(pendingSubmissionsProvider);
                          m.showSnackBar(
                              const SnackBar(content: Text('已通過並公開')));
                        } catch (e) {
                          m.showSnackBar(
                              SnackBar(content: Text('操作失敗：$e')));
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.cancel_outlined),
                      color: Colors.red,
                      tooltip: '退回',
                      onPressed: () async {
                        final m = ScaffoldMessenger.of(context);
                        try {
                          await ref
                              .read(contentServiceProvider)
                              .rejectSubmission(s.id);
                          ref.invalidate(pendingSubmissionsProvider);
                          m.showSnackBar(
                              const SnackBar(content: Text('已退回')));
                        } catch (e) {
                          m.showSnackBar(
                              SnackBar(content: Text('操作失敗：$e')));
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// 單卷管理：編輯卷導讀/統整 + 選章。
class AdminBookScreen extends ConsumerWidget {
  final Book book;

  const AdminBookScreen({super.key, required this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text('管理 · ${book.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            icon: const Icon(Icons.auto_stories),
            label: const Text('編輯整卷「導讀」與「統整」'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => AdminBookEditor(book: book)),
            ),
          ),
          const SizedBox(height: 16),
          Text('選一章編輯章導讀與節註解',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var c = 1; c <= book.chapterCount; c++)
                ActionChip(
                  label: Text('$c'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AdminChapterScreen(book: book, chapter: c),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 單章管理：編輯章導讀 + 選節編輯註解。
class AdminChapterScreen extends ConsumerWidget {
  final Book book;
  final int chapter;

  const AdminChapterScreen(
      {super.key, required this.book, required this.chapter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final verses = book.chapters[chapter - 1];
    final ann = ref
        .watch(
            chapterAnnotationProvider((bookId: book.id, chapter: chapter)))
        .value;
    final annotated = ann?.verses.keys.toSet() ?? const <int>{};

    return Scaffold(
      appBar: AppBar(title: Text('管理 · ${book.name} $chapter')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            icon: const Icon(Icons.article_outlined),
            label: const Text('編輯本章「導讀」與「重點」'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    AdminChapterEditor(book: book, chapter: chapter),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('選一節編輯註解（📖 = 已有註解）',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var v = 1; v <= verses.length; v++)
                ActionChip(
                  avatar: annotated.contains(v)
                      ? const Icon(Icons.menu_book_outlined, size: 14)
                      : null,
                  label: Text('$v'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdminVerseEditor(
                          book: book, chapter: chapter, verse: v),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------- 編輯表單 ----------

/// 多欄位表單的共用骨架：載入現有值 → 編輯 → 儲存到 Firestore。
class _EditorScaffold extends ConsumerStatefulWidget {
  final String title;
  final String? contextText; // 顯示在表單上方的經文（節編輯用）
  final List<_Field> fields;
  final Future<Map<String, String>> Function() loadValues;
  final Future<void> Function(Map<String, String> values) save;

  const _EditorScaffold({
    required this.title,
    this.contextText,
    required this.fields,
    required this.loadValues,
    required this.save,
  });

  @override
  ConsumerState<_EditorScaffold> createState() => _EditorScaffoldState();
}

class _Field {
  final String key;
  final String label;
  final String hint;
  final int maxLines;

  const _Field(this.key, this.label, {this.hint = '', this.maxLines = 3});
}

class _EditorScaffoldState extends ConsumerState<_EditorScaffold> {
  final Map<String, TextEditingController> _controllers = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      _controllers[f.key] = TextEditingController();
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await widget.loadValues();
      values.forEach((k, v) => _controllers[k]?.text = v);
    } catch (_) {
      // 載入失敗就從空白開始
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.save(
          {for (final e in _controllers.entries) e.key: e.value.text.trim()});
      // 讓讀經端立刻看到新內容
      ref.invalidate(cloudAnnotationsProvider);
      messenger.showSnackBar(const SnackBar(content: Text('已儲存並發布')));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('儲存失敗：$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.contextText != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      widget.contextText!,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(height: 1.6),
                    ),
                  ),
                for (final f in widget.fields) ...[
                  TextField(
                    controller: _controllers[f.key],
                    maxLines: f.maxLines,
                    minLines: 1,
                    decoration: InputDecoration(
                      labelText: f.label,
                      hintText: f.hint,
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton.icon(
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.cloud_upload),
                  label: Text(_saving ? '儲存中…' : '儲存並發布'),
                  onPressed: _saving ? null : _save,
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

String _lines(List<String> items) => items.join('\n');

List<String> _splitLines(String s) => s
    .split('\n')
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();

/// 空字串 → null（Firestore 不存空欄位）。
String? _nn(String s) => s.isEmpty ? null : s;

/// 整卷導讀＋統整編輯。
class AdminBookEditor extends ConsumerWidget {
  final Book book;

  const AdminBookEditor({super.key, required this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _EditorScaffold(
      title: '${book.name} · 卷導讀/統整',
      fields: const [
        _Field('summary', '大意', hint: '整卷書在講什麼', maxLines: 4),
        _Field('purpose', '目的', maxLines: 3),
        _Field('author', '作者', maxLines: 1),
        _Field('background', '歷史／文化背景', maxLines: 4),
        _Field('outline', '分段（每行一項，例：1-11 太古史）', maxLines: 8),
        _Field('conclusion', '統整（整卷重點）', maxLines: 5),
      ],
      loadValues: () async {
        final ann = await ref.read(bookAnnotationProvider(book.id).future);
        return {
          'summary': ann?.intro?.summary ?? '',
          'purpose': ann?.intro?.purpose ?? '',
          'author': ann?.intro?.author ?? '',
          'background': ann?.intro?.background ?? '',
          'outline': _lines(ann?.intro?.outline ?? []),
          'conclusion': ann?.summary ?? '',
        };
      },
      save: (v) => ref.read(contentServiceProvider).saveBook(book.id, {
        'intro': {
          if (_nn(v['summary']!) != null) 'summary': v['summary'],
          if (_nn(v['purpose']!) != null) 'purpose': v['purpose'],
          if (_nn(v['author']!) != null) 'author': v['author'],
          if (_nn(v['background']!) != null) 'background': v['background'],
        },
        'outline': _splitLines(v['outline']!),
        if (_nn(v['conclusion']!) != null) 'summary': v['conclusion'],
      }),
    );
  }
}

/// 章導讀＋章重點編輯。
class AdminChapterEditor extends ConsumerWidget {
  final Book book;
  final int chapter;

  const AdminChapterEditor(
      {super.key, required this.book, required this.chapter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _EditorScaffold(
      title: '${book.name} $chapter · 章導讀',
      fields: const [
        _Field('summary', '段落大意整理', maxLines: 4),
        _Field('purpose', '目的', maxLines: 3),
        _Field('author', '作者', maxLines: 1),
        _Field('background', '歷史／文化背景說明', maxLines: 4),
        _Field('outline', '分段（每行一項，例：1-5 光的創造）', maxLines: 8),
        _Field('conclusion', '本章重點（一句話）', maxLines: 2),
      ],
      loadValues: () async {
        final ann = await ref.read(chapterAnnotationProvider(
            (bookId: book.id, chapter: chapter)).future);
        final c = ann.chapter;
        return {
          'summary': c?.summary ?? '',
          'purpose': c?.purpose ?? '',
          'author': c?.author ?? '',
          'background': c?.background ?? '',
          'outline': _lines(c?.outline ?? []),
          'conclusion': c?.conclusion ?? '',
        };
      },
      save: (v) =>
          ref.read(contentServiceProvider).saveChapter(book.id, chapter, {
        'intro': {
          if (_nn(v['summary']!) != null) 'summary': v['summary'],
          if (_nn(v['purpose']!) != null) 'purpose': v['purpose'],
          if (_nn(v['author']!) != null) 'author': v['author'],
          if (_nn(v['background']!) != null) 'background': v['background'],
        },
        'outline': _splitLines(v['outline']!),
        if (_nn(v['conclusion']!) != null) 'conclusion': v['conclusion'],
      }),
    );
  }
}

/// 節註解編輯。
class AdminVerseEditor extends ConsumerWidget {
  final Book book;
  final int chapter;
  final int verse;

  const AdminVerseEditor({
    super.key,
    required this.book,
    required this.chapter,
    required this.verse,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = book.chapters[chapter - 1][verse - 1];
    return _EditorScaffold(
      title: '${book.name} $chapter:$verse · 註解',
      contextText: '「$text」',
      fields: const [
        _Field('commentary', '注釋（這句背後的意義）', maxLines: 5),
        _Field('keywords', '關鍵字解釋（每行一個，格式：詞｜解釋）', maxLines: 6),
        _Field('category', '生活應用分類（例：信心）', maxLines: 1),
        _Field('application', '生活應用建議', maxLines: 4),
        _Field('crossRefs', '相關經文（逗號分隔，例：約1:1, 詩33:6）', maxLines: 2),
      ],
      loadValues: () async {
        final ann = await ref.read(chapterAnnotationProvider(
            (bookId: book.id, chapter: chapter)).future);
        final v = ann.verses[verse];
        return {
          'commentary': v?.commentary ?? '',
          'keywords':
              _lines(v?.keywords.map((k) => '${k.word}｜${k.note}').toList() ?? []),
          'category': v?.applicationCategory ?? '',
          'application': v?.application ?? '',
          'crossRefs': (v?.crossRefs ?? []).join(', '),
        };
      },
      save: (v) {
        final keywords = _splitLines(v['keywords']!)
            .map((line) {
              final parts = line.split(RegExp(r'[｜|]'));
              if (parts.length < 2) return null;
              return {
                'word': parts[0].trim(),
                'note': parts.sublist(1).join('｜').trim(),
              };
            })
            .whereType<Map<String, String>>()
            .toList();
        final crossRefs = v['crossRefs']!
            .split(RegExp(r'[,，、]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        return ref
            .read(contentServiceProvider)
            .saveVerse(book.id, chapter, verse, {
          if (_nn(v['commentary']!) != null) 'commentary': v['commentary'],
          if (keywords.isNotEmpty) 'keywords': keywords,
          if (_nn(v['application']!) != null)
            'application': {
              if (_nn(v['category']!) != null) 'category': v['category'],
              'text': v['application'],
            },
          if (crossRefs.isNotEmpty) 'crossRefs': crossRefs,
        });
      },
    );
  }
}
