import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../services/verse_locator.dart';
import 'chapter_screen.dart';

/// 筆記 v2：最近／書卷／標籤／搜尋四種檢視，可進「最近刪除」還原或永久刪除。
/// 每則筆記可有可選標題、內文、多個經文引用、多個標籤；經文引用點了開臨時
/// 閱讀（不動一般 Reading Position），返回原筆記。⛔ 內容由使用者自行撰寫。
class NotesScreen extends ConsumerWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('我的筆記'),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '最近刪除',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const _DeletedNotesScreen())),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: '最近'),
              Tab(text: '書卷'),
              Tab(text: '標籤'),
              Tab(text: '搜尋'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _openEditor(context, ref, null),
          child: const Icon(Icons.add),
        ),
        body: const TabBarView(
          children: [
            _RecentView(),
            _ByBookView(),
            _ByTagView(),
            _SearchView(),
          ],
        ),
      ),
    );
  }
}

void _openEditor(BuildContext context, WidgetRef ref, Note? note) {
  Navigator.push(context,
      MaterialPageRoute(builder: (_) => NoteEditorScreen(existing: note)));
}

/// 共用的筆記卡片。
class _NoteTile extends ConsumerWidget {
  final Note note;
  const _NoteTile(this.note);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(booksProvider).value;
    final anchor = books == null
        ? '${note.bookId}:${note.chapter}:${note.verse}'
        : '${books[note.bookId - 1].name} ${note.chapter}:${note.verse}';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        title: Text(note.title.isNotEmpty ? note.title : anchor,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (note.title.isNotEmpty)
              Text(anchor,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary)),
            Text(note.content,
                maxLines: 2, overflow: TextOverflow.ellipsis),
            if (note.tagList.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (final t in note.tagList)
                      Text('#$t',
                          style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              ),
          ],
        ),
        onTap: () => _openEditor(context, ref, note),
      ),
    );
  }
}

Widget _emptyHint(BuildContext context, String text) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(text,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.outline)),
      ),
    );

class _RecentView extends ConsumerWidget {
  const _RecentView();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(allNotesProvider);
    return notes.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('載入失敗：$e')),
      data: (list) => list.isEmpty
          ? _emptyHint(context, '還沒有筆記。點右下角 + 新增，或在讀經時選取經文記錄。')
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [for (final n in list) _NoteTile(n)]),
    );
  }
}

class _ByBookView extends ConsumerWidget {
  const _ByBookView();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(allNotesProvider).value ?? const [];
    final books = ref.watch(booksProvider).value;
    if (books == null) return const Center(child: CircularProgressIndicator());
    if (notes.isEmpty) return _emptyHint(context, '還沒有筆記。');
    final byBook = <int, List<Note>>{};
    for (final n in notes) {
      (byBook[n.bookId] ??= []).add(n);
    }
    final bookIds = byBook.keys.toList()..sort();
    return ListView(
      children: [
        for (final id in bookIds)
          ExpansionTile(
            title: Text('${books[id - 1].name}（${byBook[id]!.length}）',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            children: [for (final n in byBook[id]!) _NoteTile(n)],
          ),
      ],
    );
  }
}

class _ByTagView extends ConsumerWidget {
  const _ByTagView();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(allNotesProvider).value ?? const [];
    if (notes.isEmpty) return _emptyHint(context, '還沒有筆記。');
    final byTag = <String, List<Note>>{};
    var untagged = 0;
    for (final n in notes) {
      if (n.tagList.isEmpty) {
        untagged++;
        continue;
      }
      for (final t in n.tagList) {
        (byTag[t] ??= []).add(n);
      }
    }
    final tags = byTag.keys.toList()..sort();
    if (tags.isEmpty) {
      return _emptyHint(context, '目前的筆記都還沒有標籤。編輯筆記可加標籤。');
    }
    return ListView(
      children: [
        for (final t in tags)
          ExpansionTile(
            title: Text('#$t（${byTag[t]!.length}）',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            children: [for (final n in byTag[t]!) _NoteTile(n)],
          ),
        if (untagged > 0)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('另有 $untagged 則未加標籤',
                style: Theme.of(context).textTheme.labelSmall),
          ),
      ],
    );
  }
}

class _SearchView extends ConsumerStatefulWidget {
  const _SearchView();
  @override
  ConsumerState<_SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends ConsumerState<_SearchView> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(allNotesProvider).value ?? const [];
    final q = _q.trim();
    final matches = q.isEmpty
        ? <Note>[]
        : notes
            .where((n) =>
                n.title.contains(q) ||
                n.content.contains(q) ||
                n.tags.contains(q))
            .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜尋標題、內文或標籤…',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        Expanded(
          child: q.isEmpty
              ? _emptyHint(context, '輸入關鍵字搜尋你的筆記。')
              : matches.isEmpty
                  ? _emptyHint(context, '找不到符合「$q」的筆記。')
                  : ListView(
                      children: [for (final n in matches) _NoteTile(n)]),
        ),
      ],
    );
  }
}

class _DeletedNotesScreen extends ConsumerWidget {
  const _DeletedNotesScreen();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deleted = ref.watch(deletedNotesProvider);
    final books = ref.watch(booksProvider).value;
    void refresh() {
      ref.invalidate(deletedNotesProvider);
      ref.invalidate(allNotesProvider);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('最近刪除')),
      body: deleted.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('載入失敗：$e')),
        data: (list) => list.isEmpty
            ? _emptyHint(context, '沒有最近刪除的筆記。')
            : ListView(
                children: [
                  for (final n in list)
                    ListTile(
                      title: Text(n.title.isNotEmpty
                          ? n.title
                          : (books == null
                              ? '${n.bookId}:${n.chapter}:${n.verse}'
                              : '${books[n.bookId - 1].name} ${n.chapter}:${n.verse}')),
                      subtitle: Text(n.content,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () async {
                              await ref
                                  .read(databaseServiceProvider)
                                  .restoreNote(n.id!);
                              refresh();
                            },
                            child: const Text('還原'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_forever),
                            tooltip: '永久刪除',
                            onPressed: () async {
                              await ref
                                  .read(databaseServiceProvider)
                                  .purgeNote(n.id!);
                              refresh();
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// 筆記編輯器：標題／內文／引用／標籤，自動儲存（debounce）。
class NoteEditorScreen extends ConsumerStatefulWidget {
  final Note? existing;
  const NoteEditorScreen({super.key, this.existing});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _tags;
  late List<String> _refs; // 額外引用（除錨點外）
  int? _noteId;
  int? _anchorBook, _anchorChapter, _anchorVerse;
  Timer? _debounce;
  String _savedLabel = '';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _body = TextEditingController(text: e?.content ?? '');
    _tags = TextEditingController(text: e?.tags ?? '');
    _refs = List.of(e?.refs ?? const []);
    _noteId = e?.id;
    _anchorBook = e?.bookId;
    _anchorChapter = e?.chapter;
    _anchorVerse = e?.verse;
    for (final c in [_title, _body, _tags]) {
      c.addListener(_scheduleSave);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // 離開前把未存的最後一版寫入（有內容才存）。
    _saveNow(silent: true);
    _title.dispose();
    _body.dispose();
    _tags.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () => _saveNow());
  }

  bool get _hasContent =>
      _title.text.trim().isNotEmpty ||
      _body.text.trim().isNotEmpty ||
      _refs.isNotEmpty;

  Future<void> _saveNow({bool silent = false}) async {
    if (!_hasContent) return; // 空筆記不建立
    final db = ref.read(databaseServiceProvider);
    // 新筆記若沒有錨點，用第一個引用；再沒有就以創1:1 當佔位錨點。
    if (_anchorBook == null) {
      if (_refs.isNotEmpty) {
        final m = RegExp(r'^b(\d+)_c(\d+)_v(\d+)$').firstMatch(_refs.first);
        if (m != null) {
          _anchorBook = int.parse(m.group(1)!);
          _anchorChapter = int.parse(m.group(2)!);
          _anchorVerse = int.parse(m.group(3)!);
          _refs.removeAt(0); // 錨點不重複列在 refs
        }
      }
      _anchorBook ??= 1;
      _anchorChapter ??= 1;
      _anchorVerse ??= 1;
    }
    final note = Note(
      id: _noteId,
      bookId: _anchorBook!,
      chapter: _anchorChapter!,
      verse: _anchorVerse!,
      title: _title.text.trim(),
      content: _body.text.trim(),
      tags: _tags.text.trim(),
      refs: _refs,
      createdAt: widget.existing?.createdAt ?? 0,
      updatedAt: 0,
    );
    final id = await db.saveNoteFull(note);
    _noteId = id;
    ref.invalidate(allNotesProvider);
    if (!silent && mounted) {
      setState(() => _savedLabel = '已自動儲存');
    }
  }

  Future<void> _addRefDialog() async {
    final books = ref.read(booksProvider).value;
    if (books == null) return;
    final ctrl = TextEditingController();
    final ref0 = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('加入經文引用'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例：約3:16 或 創 1:1'),
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('加入')),
        ],
      ),
    );
    if (ref0 == null || ref0.trim().isEmpty) return;
    final loc = VerseLocator.parse(ref0.trim(), books);
    if (loc == null || loc.verse == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('無法解析這個經文引用')));
      }
      return;
    }
    final key = 'b${loc.bookId}_c${loc.chapter}_v${loc.verse}';
    setState(() {
      if (_anchorBook == null) {
        _anchorBook = loc.bookId;
        _anchorChapter = loc.chapter;
        _anchorVerse = loc.verse;
      } else if (!_refs.contains(key) &&
          !(loc.bookId == _anchorBook &&
              loc.chapter == _anchorChapter &&
              loc.verse == _anchorVerse)) {
        _refs.add(key);
      }
    });
    _scheduleSave();
  }

  void _openRef(int bookId, int chapter, int verse) {
    Navigator.push(
      context,
      MaterialPageRoute(
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
    final books = ref.watch(booksProvider).value;
    String label(int b, int c, int v) =>
        books == null ? '$b:$c:$v' : '${books[b - 1].name} $c:$v';
    final allRefs = <({int bookId, int chapter, int verse})>[
      if (_anchorBook != null)
        (bookId: _anchorBook!, chapter: _anchorChapter!, verse: _anchorVerse!),
      for (final r in _refs)
        if (RegExp(r'^b(\d+)_c(\d+)_v(\d+)$').firstMatch(r) case final m?)
          (
            bookId: int.parse(m.group(1)!),
            chapter: int.parse(m.group(2)!),
            verse: int.parse(m.group(3)!),
          ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? '新筆記' : '編輯筆記'),
        actions: [
          if (_noteId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '移到最近刪除',
              onPressed: () async {
                await ref
                    .read(databaseServiceProvider)
                    .softDeleteNoteById(_noteId!);
                ref.invalidate(allNotesProvider);
                ref.invalidate(deletedNotesProvider);
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(
                labelText: '標題（可留空）', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            maxLines: 8,
            decoration: const InputDecoration(
                labelText: '內文',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
                hintText: '寫下你的想法…'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('經文引用', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('加入'),
                onPressed: _addRefDialog,
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in allRefs)
                InputChip(
                  avatar: const Icon(Icons.menu_book, size: 16),
                  label: Text(label(r.bookId, r.chapter, r.verse)),
                  onPressed: () => _openRef(r.bookId, r.chapter, r.verse),
                  onDeleted: () {
                    final key = 'b${r.bookId}_c${r.chapter}_v${r.verse}';
                    setState(() {
                      if (r.bookId == _anchorBook &&
                          r.chapter == _anchorChapter &&
                          r.verse == _anchorVerse) {
                        // 移除錨點：把第一個 ref 升為錨點（若有）
                        if (_refs.isNotEmpty) {
                          final m = RegExp(r'^b(\d+)_c(\d+)_v(\d+)$')
                              .firstMatch(_refs.removeAt(0));
                          _anchorBook = int.parse(m!.group(1)!);
                          _anchorChapter = int.parse(m.group(2)!);
                          _anchorVerse = int.parse(m.group(3)!);
                        } else {
                          _anchorBook = null;
                          _anchorChapter = null;
                          _anchorVerse = null;
                        }
                      } else {
                        _refs.remove(key);
                      }
                    });
                    _scheduleSave();
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _tags,
            decoration: const InputDecoration(
              labelText: '標籤（空格分隔）',
              prefixIcon: Icon(Icons.tag),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text(_savedLabel,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline)),
        ],
      ),
    );
  }
}
