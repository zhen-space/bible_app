import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../utils/note_list_presentation.dart';
import '../widgets/scripture_reference_field.dart';
import '../widgets/student_ux.dart';

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  static const _sortPreferenceKey = 'notes_sort_order';
  static const _groupPreferenceKey = 'notes_group_by_date';
  final SelectionController<int> _selection = SelectionController<int>();
  NoteSortOrder _sortOrder = NoteSortOrder.updated;
  bool _groupByDate = true;

  @override
  void initState() {
    super.initState();
    _selection.addListener(_changed);
    _restoreListPreferences();
  }

  Future<void> _restoreListPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _sortOrder = decodeNoteSortOrder(
        preferences.getString(_sortPreferenceKey),
      );
      _groupByDate = preferences.getBool(_groupPreferenceKey) ?? true;
    });
  }

  Future<void> _saveListPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_sortPreferenceKey, _sortOrder.name);
    await preferences.setBool(_groupPreferenceKey, _groupByDate);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _selection
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  Future<void> _deleteSelected(List<Note> notes) async {
    final selected = notes.where((n) => n.id != null && _selection.contains(n.id!)).toList();
    if (selected.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(selected.length == 1 ? '移到最近刪除？' : '將 ${selected.length} 則筆記移到最近刪除？'),
        content: const Text('可以從「最近刪除」還原。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('刪除')),
        ],
      ),
    );
    if (ok != true) return;
    final db = ref.read(databaseServiceProvider);
    for (final note in selected) {
      await db.softDeleteNoteById(note.id!);
    }
    _selection.cancel();
    ref.invalidate(allNotesProvider);
    ref.invalidate(deletedNotesProvider);
  }

  String _noteCopy(Note note, List<Book>? books) {
    final out = <String>[];
    if (note.title.trim().isNotEmpty) out.add(note.title.trim());
    if (note.content.trim().isNotEmpty) out.add(note.content.trim());
    if (books != null) {
      final anchor = books[note.bookId - 1];
      out.add('經文：${anchor.name} ${note.chapter}:${note.verse}');
      if (note.refs.isNotEmpty) {
        final labels = note.refs.map((raw) =>
            parseLegacyScriptureRef(raw, books)?.label(books) ?? raw);
        out.add('相關經文：${labels.join('、')}');
      }
    }
    if (note.tagList.isNotEmpty) out.add('標籤：${note.tagList.join('、')}');
    return out.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(allNotesProvider).value ?? const <Note>[];
    final ids = notes.where((n) => n.id != null).map((n) => n.id!).toList();
    final selected = notes.where((n) => n.id != null && _selection.contains(n.id!)).toList();
    final books = ref.watch(booksProvider).value;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: _selection.active
            ? StudentSelectionAppBar(
                title: '經文筆記',
                selectionCount: _selection.count,
                totalCount: ids.length,
                onCancel: _selection.cancel,
                onSelectAll: () {
                  if (_selection.count == ids.length && ids.isNotEmpty) {
                    _selection.cancel();
                    _selection.start();
                  } else {
                    _selection.selectAll(ids);
                  }
                },
              )
            : AppBar(
                title: const Text('經文筆記'),
                actions: [
                  if (notes.isNotEmpty)
                    TextButton(onPressed: _selection.start, child: const Text('選取')),
                  PopupMenuButton<String>(
                    tooltip: '更多',
                    onSelected: (value) {
                      if (value == 'deleted') {
                        Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const _DeletedNotesScreen()));
                      } else if (value == 'group') {
                        setState(() => _groupByDate = !_groupByDate);
                        _saveListPreferences();
                      } else if (value.startsWith('sort_')) {
                        final name = value.substring(5);
                        setState(() {
                          _sortOrder = NoteSortOrder.values.firstWhere(
                            (order) => order.name == name,
                          );
                        });
                        _saveListPreferences();
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        enabled: false,
                        child: Text('排序方式'),
                      ),
                      for (final order in NoteSortOrder.values)
                        CheckedPopupMenuItem(
                          value: 'sort_${order.name}',
                          checked: _sortOrder == order,
                          child: Text(order.label),
                        ),
                      const PopupMenuDivider(),
                      CheckedPopupMenuItem(
                        value: 'group',
                        checked: _groupByDate,
                        child: const Text('依日期分組'),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'deleted',
                        child: Text('最近刪除'),
                      ),
                    ],
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
        floatingActionButton: _selection.active
            ? null
            : FloatingActionButton(
                tooltip: '新增筆記',
                onPressed: () => _openEditor(context, null),
                child: const Icon(Icons.add),
              ),
        bottomNavigationBar: _selection.active
            ? StudentBatchActionBar(actions: [
                StudentBatchAction(
                  label: '複製',
                  icon: Icons.copy_outlined,
                  onPressed: selected.isEmpty
                      ? null
                      : () => copyHumanReadable(
                            context,
                            joinHumanReadable(selected.map((n) => _noteCopy(n, books))),
                            success: '已複製 ${selected.length} 則筆記',
                          ),
                ),
                StudentBatchAction(
                  label: '刪除',
                  icon: Icons.delete_outline,
                  destructive: true,
                  onPressed: selected.isEmpty ? null : () => _deleteSelected(notes),
                ),
              ])
            : null,
        body: TabBarView(
          physics: _selection.active ? const NeverScrollableScrollPhysics() : null,
          children: [
            _RecentView(
              selection: _selection,
              onOpen: _openEditor,
              onDelete: _deleteOne,
              onCopy: _copyOne,
              sortOrder: _sortOrder,
              groupByDate: _groupByDate,
            ),
            _ByBookView(selection: _selection, onOpen: _openEditor, onDelete: _deleteOne, onCopy: _copyOne),
            _ByTagView(selection: _selection, onOpen: _openEditor, onDelete: _deleteOne, onCopy: _copyOne),
            _SearchView(selection: _selection, onOpen: _openEditor, onDelete: _deleteOne, onCopy: _copyOne),
          ],
        ),
      ),
    );
  }

  void _openEditor(BuildContext context, Note? note) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => NoteEditorScreen(existing: note)));
  }

  Future<void> _deleteOne(BuildContext context, Note note) async {
    if (note.id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移到最近刪除？'),
        content: const Text('之後仍可還原這則筆記。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('刪除')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(databaseServiceProvider).softDeleteNoteById(note.id!);
    ref.invalidate(allNotesProvider);
    ref.invalidate(deletedNotesProvider);
  }

  Future<void> _copyOne(BuildContext context, Note note) async {
    await copyHumanReadable(context, _noteCopy(note, ref.read(booksProvider).value));
  }
}

typedef NoteOpen = void Function(BuildContext context, Note note);
typedef NoteAction = Future<void> Function(BuildContext context, Note note);

class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.note,
    required this.selection,
    required this.onOpen,
    required this.onDelete,
    required this.onCopy,
  });
  final Note note;
  final SelectionController<int> selection;
  final NoteOpen onOpen;
  final NoteAction onDelete;
  final NoteAction onCopy;

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final books = ref.watch(booksProvider).value;
      final anchor = books == null
          ? '${note.bookId}:${note.chapter}:${note.verse}'
          : '${books[note.bookId - 1].name} ${note.chapter}:${note.verse}';
      final id = note.id;
      final updated = compactNoteDate(noteListTimestamp(note), DateTime.now());
      final preview = note.content.isEmpty ? anchor : note.content;
      final row = ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
        leading: selection.active && id != null
            ? Checkbox(value: selection.contains(id), onChanged: (_) => selection.toggle(id))
            : null,
        title: Text(note.title.isNotEmpty ? note.title : anchor,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('$updated · $preview',
            maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: selection.active ? null : const Icon(Icons.chevron_right),
        onLongPress: id == null ? null : () => selection.start(id),
        onTap: selection.active && id != null
            ? () => selection.toggle(id)
            : () => onOpen(context, note),
      );
      if (selection.active || id == null) return row;
      return StudentSwipeRow(
        dismissKey: ValueKey('note_$id'),
        startLabel: '複製',
        startIcon: Icons.copy_outlined,
        endLabel: '刪除',
        onSwipeStartToEnd: () => onCopy(context, note),
        onSwipeEndToStart: () => onDelete(context, note),
        child: row,
      );
    });
  }
}

Widget _noteList({
  required List<Note> notes,
  required SelectionController<int> selection,
  required NoteOpen onOpen,
  required NoteAction onDelete,
  required NoteAction onCopy,
}) => ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: notes.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 20),
      itemBuilder: (_, i) => _NoteRow(
        note: notes[i],
        selection: selection,
        onOpen: onOpen,
        onDelete: onDelete,
        onCopy: onCopy,
      ),
    );

class _RecentView extends ConsumerWidget {
  const _RecentView({
    required this.selection,
    required this.onOpen,
    required this.onDelete,
    required this.onCopy,
    required this.sortOrder,
    required this.groupByDate,
  });
  final SelectionController<int> selection;
  final NoteOpen onOpen;
  final NoteAction onDelete;
  final NoteAction onCopy;
  final NoteSortOrder sortOrder;
  final bool groupByDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(allNotesProvider).when(
        loading: () => const StudentCompactLoading(),
        error: (_, _) => StudentErrorState(onRetry: () => ref.invalidate(allNotesProvider)),
        data: (notes) {
          if (notes.isEmpty) {
            return const StudentEmptyState(
              title: '還沒有經文筆記',
              subtitle: '閱讀時選取經文，或從這裡新增筆記。',
              icon: Icons.edit_note_outlined,
            );
          }
          final sorted = sortNotesForList(notes, sortOrder);
          if (!groupByDate) {
            return _noteList(
              notes: sorted,
              selection: selection,
              onOpen: onOpen,
              onDelete: onDelete,
              onCopy: onCopy,
            );
          }
          final groups = <String, List<Note>>{};
          final now = DateTime.now();
          final newest = sortNotesForList(notes, NoteSortOrder.updated);
          for (final note in newest) {
            final timestamp = noteListTimestamp(note);
            (groups[noteDateSection(timestamp, now)] ??= []).add(note);
          }
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            children: [
              for (final group in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 5),
                  child: Text(
                    group.key,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                for (final note in sortNotesForList(group.value, sortOrder))
                  _NoteRow(
                    note: note,
                    selection: selection,
                    onOpen: onOpen,
                    onDelete: onDelete,
                    onCopy: onCopy,
                  ),
              ],
            ],
          );
        },
      );
}

class _ByBookView extends ConsumerWidget {
  const _ByBookView({required this.selection, required this.onOpen, required this.onDelete, required this.onCopy});
  final SelectionController<int> selection;
  final NoteOpen onOpen;
  final NoteAction onDelete;
  final NoteAction onCopy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(allNotesProvider).value ?? const <Note>[];
    final books = ref.watch(booksProvider).value;
    if (books == null) return const StudentCompactLoading();
    if (notes.isEmpty) return const StudentEmptyState(title: '還沒有經文筆記');
    final byBook = <int, List<Note>>{};
    for (final n in notes) {
      (byBook[n.bookId] ??= []).add(n);
    }
    final ids = byBook.keys.toList()..sort();
    return ListView(children: [
      for (final id in ids)
        ExpansionTile(
          title: Text(books[id - 1].name),
          subtitle: Text('${byBook[id]!.length} 則'),
          children: [
            for (final n in sortNotesForList(
              byBook[id]!,
              NoteSortOrder.scripture,
            ))
              _NoteRow(note: n, selection: selection, onOpen: onOpen, onDelete: onDelete, onCopy: onCopy),
          ],
        ),
    ]);
  }
}

class _ByTagView extends ConsumerWidget {
  const _ByTagView({required this.selection, required this.onOpen, required this.onDelete, required this.onCopy});
  final SelectionController<int> selection;
  final NoteOpen onOpen;
  final NoteAction onDelete;
  final NoteAction onCopy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(allNotesProvider).value ?? const <Note>[];
    if (notes.isEmpty) return const StudentEmptyState(title: '還沒有經文筆記');
    final byTag = <String, List<Note>>{};
    for (final n in notes) {
      for (final t in n.tagList) {
        (byTag[t] ??= []).add(n);
      }
    }
    final tags = byTag.keys.toList()..sort();
    if (tags.isEmpty) return const StudentEmptyState(title: '目前沒有標籤', subtitle: '編輯筆記時可以加入標籤。');
    return ListView(children: [
      for (final tag in tags)
        ExpansionTile(
          title: Text('#$tag'),
          subtitle: Text('${byTag[tag]!.length} 則'),
          children: [
            for (final n in sortNotesForList(
              byTag[tag]!,
              NoteSortOrder.updated,
            ))
              _NoteRow(note: n, selection: selection, onOpen: onOpen, onDelete: onDelete, onCopy: onCopy),
          ],
        ),
    ]);
  }
}

class _SearchView extends ConsumerStatefulWidget {
  const _SearchView({required this.selection, required this.onOpen, required this.onDelete, required this.onCopy});
  final SelectionController<int> selection;
  final NoteOpen onOpen;
  final NoteAction onDelete;
  final NoteAction onCopy;

  @override
  ConsumerState<_SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends ConsumerState<_SearchView> {
  final _controller = TextEditingController();
  String query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clearQuery() {
    _controller.clear();
    setState(() => query = '');
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(allNotesProvider).value ?? const <Note>[];
    final books = ref.watch(booksProvider).value;
    final q = query.trim();
    final matches = searchNotesForList(
      notes,
      q,
      extraText: (note) {
        final fallback = '${note.bookId} ${note.chapter}:${note.verse}';
        if (books == null || note.bookId < 1 || note.bookId > books.length) {
          return fallback;
        }
        final book = books[note.bookId - 1];
        return '${book.name} ${book.abbr} $fallback';
      },
    );
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: '搜尋標題、內文、標籤或經文位置',
            suffixIcon: q.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除搜尋',
                    onPressed: _clearQuery,
                    icon: const Icon(Icons.clear),
                  ),
          ),
          onChanged: (value) => setState(() => query = value),
        ),
      ),
      if (q.isNotEmpty && matches.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${matches.length} 則結果',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
        ),
      Expanded(
        child: q.isEmpty
            ? const StudentEmptyState(title: '搜尋你的筆記')
            : matches.isEmpty
                ? StudentEmptyState(title: '找不到符合「$q」的筆記')
                : _noteList(notes: matches, selection: widget.selection, onOpen: widget.onOpen, onDelete: widget.onDelete, onCopy: widget.onCopy),
      ),
    ]);
  }
}

class _DeletedNotesScreen extends ConsumerWidget {
  const _DeletedNotesScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deleted = ref.watch(deletedNotesProvider);
    void refresh() {
      ref.invalidate(deletedNotesProvider);
      ref.invalidate(allNotesProvider);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('最近刪除')),
      body: deleted.when(
        loading: () => const StudentCompactLoading(),
        error: (_, _) => StudentErrorState(onRetry: () => ref.invalidate(deletedNotesProvider)),
        data: (list) => list.isEmpty
            ? const StudentEmptyState(title: '沒有最近刪除的筆記')
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 20),
                itemBuilder: (context, i) {
                  final n = list[i];
                  return ListTile(
                    title: Text(n.title.isNotEmpty ? n.title : '經文筆記'),
                    subtitle: Text(n.content, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'restore') await ref.read(databaseServiceProvider).restoreNote(n.id!);
                        if (value == 'delete') await ref.read(databaseServiceProvider).purgeNote(n.id!);
                        refresh();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'restore', child: Text('還原')),
                        PopupMenuItem(value: 'delete', child: Text('永久刪除')),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key, this.existing});
  final Note? existing;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _tags;
  late List<String> _extraRefs;
  int? _id;
  int? _anchorBook;
  int? _anchorChapter;
  int? _anchorVerse;
  Timer? _debounce;
  Future<void> _saveQueue = Future.value();
  String saved = '';
  bool _discardOnDispose = false;

  @override
  void initState() {
    super.initState();
    final n = widget.existing;
    _title = TextEditingController(text: n?.title ?? '');
    _body = TextEditingController(text: n?.content ?? '');
    _tags = TextEditingController(text: n?.tags ?? '');
    _extraRefs = List<String>.of(n?.refs ?? const []);
    _id = n?.id;
    _anchorBook = n?.bookId;
    _anchorChapter = n?.chapter;
    _anchorVerse = n?.verse;
    for (final c in [_title, _body, _tags]) {
      c.addListener(_scheduleSave);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (!_discardOnDispose) _save(silent: true);
    _title.dispose();
    _body.dispose();
    _tags.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), _save);
  }

  List<String> _displayRefs(List<Book> books) {
    final refs = <String>[];
    if (_anchorBook != null) {
      refs.add('b${_anchorBook}_c${_anchorChapter}_v$_anchorVerse');
    }
    refs.addAll(_extraRefs);
    return refs;
  }

  void _setRefs(List<String> values) {
    final books = ref.read(booksProvider).value;
    if (books == null) return;
    int? b, c, v;
    final extras = <String>[];
    for (final raw in values) {
      final parsed = parseLegacyScriptureRef(raw, books);
      if (parsed == null) continue;
      if (b == null) {
        b = parsed.bookId;
        c = parsed.chapter;
        v = parsed.startVerse;
        if (parsed.endVerse != null && parsed.endVerse != parsed.startVerse) {
          extras.add(parsed.label(books));
        }
      } else {
        extras.add(raw);
      }
    }
    setState(() {
      _anchorBook = b;
      _anchorChapter = c;
      _anchorVerse = v;
      _extraRefs = extras;
    });
    _scheduleSave();
  }

  Future<void> _save({bool silent = false}) {
    if (_discardOnDispose) return Future.value();
    final has = _title.text.trim().isNotEmpty || _body.text.trim().isNotEmpty || _anchorBook != null || _extraRefs.isNotEmpty;
    if (!has) return Future.value();
    _anchorBook ??= 1;
    _anchorChapter ??= 1;
    _anchorVerse ??= 1;
    final bookId = _anchorBook!;
    final chapter = _anchorChapter!;
    final verse = _anchorVerse!;
    final title = _title.text.trim();
    final content = _body.text.trim();
    final tags = _tags.text.trim();
    final refs = List<String>.of(_extraRefs);
    final createdAt = widget.existing?.createdAt ?? 0;
    final database = ref.read(databaseServiceProvider);

    _saveQueue = _saveQueue.then((_) async {
      if (_discardOnDispose) return;
      final note = Note(
        id: _id,
        bookId: bookId,
        chapter: chapter,
        verse: verse,
        title: title,
        content: content,
        tags: tags,
        refs: refs,
        createdAt: createdAt,
        updatedAt: 0,
      );
      _id = await database.saveNoteFull(note);
      if (mounted) {
        ref.invalidate(allNotesProvider);
        if (!silent) setState(() => saved = '已儲存');
      }
    });
    return _saveQueue;
  }

  @override
  Widget build(BuildContext context) {
    final books = ref.watch(booksProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? '新筆記' : '編輯筆記'),
        actions: [
          if (_id != null)
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value != 'delete') return;
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('移到最近刪除？'),
                    content: const Text('之後仍可從「最近刪除」還原這則筆記。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('刪除'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true || !mounted) return;
                _debounce?.cancel();
                _discardOnDispose = true;
                await _saveQueue;
                await ref.read(databaseServiceProvider).softDeleteNoteById(_id!);
                ref.invalidate(allNotesProvider);
                ref.invalidate(deletedNotesProvider);
                if (context.mounted) Navigator.pop(context);
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('移到最近刪除'))],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          TextField(controller: _title, decoration: const InputDecoration(labelText: '標題')),
          const SizedBox(height: 14),
          TextField(controller: _body, maxLines: 9, decoration: const InputDecoration(labelText: '筆記', hintText: '寫下你的想法…')),
          const SizedBox(height: 20),
          if (books != null)
            ScriptureReferenceField(
              values: _displayRefs(books),
              onChanged: _setRefs,
              title: '對應經文',
            ),
          const SizedBox(height: 18),
          TextField(controller: _tags, decoration: const InputDecoration(labelText: '標籤', prefixIcon: Icon(Icons.tag))),
          const SizedBox(height: 12),
          Text(saved, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
        ],
      ),
    );
  }
}
