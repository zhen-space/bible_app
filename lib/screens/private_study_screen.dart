import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/private_study.dart';
import '../providers/providers.dart' show databaseServiceProvider;
import '../services/app_links.dart';
import '../services/private_study_repository.dart';
import '../widgets/scripture_reference_field.dart';
import '../widgets/student_ux.dart';

final privateStudyRepositoryProvider = Provider<PrivateStudyRepository>(
    (ref) => PrivateStudyRepository(ref.watch(databaseServiceProvider)));
final privateStudyBooksProvider = FutureProvider<List<PrivateStudyBook>>(
    (ref) => ref.watch(privateStudyRepositoryProvider).getBooks());
final privateStudyAllNotesProvider = FutureProvider<List<PrivateStudyNote>>(
    (ref) => ref.watch(privateStudyRepositoryProvider).getNotes());
final privateStudyBookNotesProvider =
    FutureProvider.family<List<PrivateStudyNote>, String>((ref, bookId) =>
        ref.watch(privateStudyRepositoryProvider).getNotes(bookId: bookId));

void _refreshPrivateStudy(WidgetRef ref, {String? bookId}) {
  ref.invalidate(privateStudyBooksProvider);
  ref.invalidate(privateStudyAllNotesProvider);
  if (bookId != null) ref.invalidate(privateStudyBookNotesProvider(bookId));
}

String privateStudyNoteHumanReadable(PrivateStudyNote note,
    {String? bookTitle}) {
  final out = <String>[];
  if (note.quote.trim().isNotEmpty) out.add(note.quote.trim());
  if (note.reflection.trim().isNotEmpty) out.add('我的整理／心得：${note.reflection.trim()}');
  if (note.scriptureRefs.isNotEmpty) {
    out.add('對應經文：${note.scriptureRefs.join('、')}');
  }
  if (note.sourceLocation.trim().isNotEmpty) {
    out.add('來源位置：${note.sourceLocation.trim()}');
  }
  if (note.practice.trim().isNotEmpty) out.add('我的實踐：${note.practice.trim()}');
  if (bookTitle != null && bookTitle.trim().isNotEmpty) {
    out.add('書籍：${bookTitle.trim()}');
  }
  if (note.topics.isNotEmpty) out.add('主題：${note.topics.join('、')}');
  if (out.isEmpty) out.add('未命名筆記');
  return out.join('\n');
}

class PrivateStudyHomeScreen extends ConsumerStatefulWidget {
  const PrivateStudyHomeScreen({super.key});

  @override
  ConsumerState<PrivateStudyHomeScreen> createState() =>
      _PrivateStudyHomeScreenState();
}

class _PrivateStudyHomeScreenState extends ConsumerState<PrivateStudyHomeScreen> {
  bool sortByTitle = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _backgroundSync());
  }

  Future<void> _backgroundSync() async {
    try {
      await ref.read(privateStudyRepositoryProvider).syncCurrentUser();
    } catch (_) {}
    if (mounted) _refreshPrivateStudy(ref);
  }

  @override
  Widget build(BuildContext context) {
    final booksAsync = ref.watch(privateStudyBooksProvider);
    final notesAsync = ref.watch(privateStudyAllNotesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的研讀'),
        actions: [
          IconButton(
            tooltip: '搜尋',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PrivateStudySearchScreen())),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (value) {
              if (value == 'deleted') {
                Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const PrivateStudyDeletedScreen()))
                    .then((_) => _refreshPrivateStudy(ref));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'deleted', child: Text('最近刪除')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _backgroundSync,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 36),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 6),
              child: Row(children: [
                Expanded(
                  child: Text('我的書籍',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                PopupMenuButton<bool>(
                  tooltip: '排序',
                  initialValue: sortByTitle,
                  onSelected: (value) => setState(() => sortByTitle = value),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: false, child: Text('最近研讀')),
                    PopupMenuItem(value: true, child: Text('書名')),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Text(sortByTitle ? '書名' : '最近研讀'),
                  ),
                ),
              ]),
            ),
            booksAsync.when(
              loading: () => const StudentCompactLoading(),
              error: (_, _) => StudentErrorState(onRetry: () => _refreshPrivateStudy(ref)),
              data: (original) {
                if (original.isEmpty) {
                  return StudentEmptyState(
                    title: '開始你的第一本研讀書籍',
                    subtitle: '把重要的話語、心得、經文與實踐整理在這裡。',
                    icon: Icons.auto_stories_outlined,
                    actionLabel: '新增書籍',
                    onAction: () => _addBook(context),
                  );
                }
                final books = [...original];
                if (sortByTitle) books.sort((a, b) => a.title.compareTo(b.title));
                return Column(children: [
                  for (final book in books) ...[
                    ListTile(
                      leading: const Icon(Icons.menu_book_outlined),
                      title: Text(book.title),
                      subtitle: book.author.isEmpty ? null : Text(book.author),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await ref.read(privateStudyRepositoryProvider).touchBook(book.id);
                        if (!context.mounted) return;
                        await Navigator.push(context,
                            MaterialPageRoute(builder: (_) => PrivateStudyBookScreen(bookId: book.id)));
                        _refreshPrivateStudy(ref, bookId: book.id);
                      },
                    ),
                    const Divider(height: 1, indent: 56),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _addBook(context),
                        icon: const Icon(Icons.add),
                        label: const Text('新增書籍'),
                      ),
                    ),
                  ),
                ]);
              },
            ),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Text('全部筆記',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            notesAsync.when(
              loading: () => const StudentCompactLoading(),
              error: (_, _) => const SizedBox.shrink(),
              data: (notes) => ListTile(
                leading: const Icon(Icons.library_books_outlined),
                title: const Text('主題分類'),
                subtitle: Text(notes.isEmpty ? '還沒有研讀筆記' : '${notes.length} 則筆記'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PrivateStudyAllTopicsScreen())),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addBook(BuildContext context) async {
    final title = TextEditingController();
    final author = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新增書籍'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, autofocus: true, decoration: const InputDecoration(labelText: '書名')),
          const SizedBox(height: 12),
          TextField(controller: author, decoration: const InputDecoration(labelText: '作者')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('建立')),
        ],
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    final repo = ref.read(privateStudyRepositoryProvider);
    final now = DateTime.now().millisecondsSinceEpoch;
    await repo.saveBook(PrivateStudyBook(
      id: repo.newBookId(),
      title: title.text.trim(),
      author: author.text.trim(),
      createdAt: now,
      updatedAt: now,
      lastStudiedAt: now,
    ));
    _refreshPrivateStudy(ref);
  }
}

class PrivateStudyBookScreen extends ConsumerWidget {
  const PrivateStudyBookScreen({super.key, required this.bookId});
  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(privateStudyRepositoryProvider);
    final notesAsync = ref.watch(privateStudyBookNotesProvider(bookId));
    return FutureBuilder<PrivateStudyBook?>(
      future: repo.getBook(bookId),
      builder: (context, snap) {
        final book = snap.data;
        if (book == null && snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: StudentCompactLoading());
        }
        if (book == null) {
          return Scaffold(appBar: AppBar(), body: const StudentEmptyState(title: '找不到這本書'));
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(book.title),
            actions: [
              PopupMenuButton<String>(
                tooltip: '更多',
                onSelected: (value) async {
                  if (value != 'delete') return;
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('刪除這本書？'),
                      content: const Text('書籍與其中的研讀筆記會一起移到「最近刪除」。'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('刪除')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await repo.softDeleteBook(bookId);
                    _refreshPrivateStudy(ref, bookId: bookId);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('刪除書籍'))],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 36),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(book.title,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  if (book.author.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(book.author, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.outline)),
                  ],
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () async {
                      await Navigator.push(context,
                          MaterialPageRoute(builder: (_) => PrivateStudyNoteEditorScreen(book: book)));
                      _refreshPrivateStudy(ref, bookId: bookId);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('新增筆記'),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                child: Text('主題分類',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
              notesAsync.when(
                loading: () => const StudentCompactLoading(),
                error: (_, _) => StudentErrorState(onRetry: () => ref.invalidate(privateStudyBookNotesProvider(bookId))),
                data: (notes) => notes.isEmpty
                    ? StudentEmptyState(
                        title: '這本書還沒有研讀筆記',
                        subtitle: '閱讀時遇到重要的話語，可以從這裡記下來。',
                        actionLabel: '新增筆記',
                        onAction: () async {
                          await Navigator.push(context,
                              MaterialPageRoute(builder: (_) => PrivateStudyNoteEditorScreen(book: book)));
                          _refreshPrivateStudy(ref, bookId: bookId);
                        },
                      )
                    : _TopicList(
                        notes: notes,
                        onTopic: (topic) => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PrivateStudyTopicNotesScreen(
                              topic: topic,
                              bookId: bookId,
                              bookTitle: book.title,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class PrivateStudyAllTopicsScreen extends ConsumerWidget {
  const PrivateStudyAllTopicsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(privateStudyAllNotesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('全部筆記')),
      body: async.when(
        loading: () => const StudentCompactLoading(),
        error: (_, _) => StudentErrorState(onRetry: () => ref.invalidate(privateStudyAllNotesProvider)),
        data: (notes) => notes.isEmpty
            ? const StudentEmptyState(title: '還沒有研讀筆記', subtitle: '從「我的書籍」選一本書開始整理。')
            : _TopicList(
                notes: notes,
                onTopic: (topic) => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => PrivateStudyTopicNotesScreen(topic: topic))),
              ),
      ),
    );
  }
}

class _TopicList extends StatelessWidget {
  const _TopicList({required this.notes, required this.onTopic});
  final List<PrivateStudyNote> notes;
  final ValueChanged<String> onTopic;

  @override
  Widget build(BuildContext context) {
    final topics = [...kPrivateStudyTopics, '未分類'];
    int count(String topic) => topic == '未分類'
        ? notes.where((n) => n.topics.isEmpty).length
        : notes.where((n) => n.topics.contains(topic)).length;
    return Column(children: [
      for (final topic in topics) ...[
        ListTile(
          title: Text(topic),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('${count(topic)}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
          ]),
          onTap: () => onTopic(topic),
        ),
        const Divider(height: 1, indent: 20),
      ],
    ]);
  }
}

class PrivateStudyTopicNotesScreen extends ConsumerStatefulWidget {
  const PrivateStudyTopicNotesScreen({super.key, required this.topic, this.bookId, this.bookTitle});
  final String topic;
  final String? bookId;
  final String? bookTitle;

  @override
  ConsumerState<PrivateStudyTopicNotesScreen> createState() => _PrivateStudyTopicNotesScreenState();
}

class _PrivateStudyTopicNotesScreenState extends ConsumerState<PrivateStudyTopicNotesScreen> {
  final SelectionController<String> selection = SelectionController<String>();

  @override
  void initState() {
    super.initState();
    selection.addListener(_refreshState);
  }

  void _refreshState() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    selection
      ..removeListener(_refreshState)
      ..dispose();
    super.dispose();
  }

  Future<void> _delete(List<PrivateStudyNote> notes) async {
    if (notes.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(notes.length == 1 ? '刪除這則筆記？' : '刪除 ${notes.length} 則筆記？'),
        content: const Text('會移到「最近刪除」，之後可以還原。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('刪除')),
        ],
      ),
    );
    if (ok != true) return;
    final repo = ref.read(privateStudyRepositoryProvider);
    for (final note in notes) {
      await repo.softDeleteNote(note.id);
      _refreshPrivateStudy(ref, bookId: note.bookId);
    }
    selection.cancel();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(privateStudyRepositoryProvider);
    return FutureBuilder<List<Object>>(
      future: Future.wait<Object>([
        repo.getNotes(bookId: widget.bookId, topic: widget.topic),
        repo.getBooks(),
      ]),
      builder: (context, snap) {
        final notes = snap.hasData ? snap.data![0] as List<PrivateStudyNote> : const <PrivateStudyNote>[];
        final books = snap.hasData ? snap.data![1] as List<PrivateStudyBook> : const <PrivateStudyBook>[];
        final byId = {for (final b in books) b.id: b};
        final chosen = notes.where((n) => selection.contains(n.id)).toList();
        return Scaffold(
          appBar: selection.active
              ? StudentSelectionAppBar(
                  title: widget.topic,
                  selectionCount: selection.count,
                  totalCount: notes.length,
                  onCancel: selection.cancel,
                  onSelectAll: () => selection.selectAll(notes.map((n) => n.id)),
                )
              : AppBar(
                  title: Text(widget.topic),
                  actions: [
                    if (notes.isNotEmpty)
                      TextButton(onPressed: selection.start, child: const Text('選取')),
                  ],
                ),
          bottomNavigationBar: selection.active
              ? StudentBatchActionBar(actions: [
                  StudentBatchAction(
                    label: '複製',
                    icon: Icons.copy_outlined,
                    onPressed: chosen.isEmpty
                        ? null
                        : () => copyHumanReadable(
                              context,
                              joinHumanReadable(chosen.map((n) => privateStudyNoteHumanReadable(n, bookTitle: byId[n.bookId]?.title))),
                              success: '已複製 ${chosen.length} 則研讀筆記',
                            ),
                  ),
                  StudentBatchAction(
                    label: '刪除',
                    icon: Icons.delete_outline,
                    destructive: true,
                    onPressed: chosen.isEmpty ? null : () => _delete(chosen),
                  ),
                ])
              : null,
          body: !snap.hasData
              ? const StudentCompactLoading()
              : notes.isEmpty
                  ? StudentEmptyState(title: '目前沒有「${widget.topic}」的筆記。')
                  : ListView.separated(
                      itemCount: notes.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 20),
                      itemBuilder: (context, i) {
                        final note = notes[i];
                        final book = byId[note.bookId];
                        final row = ListTile(
                          leading: selection.active
                              ? Checkbox(value: selection.contains(note.id), onChanged: (_) => selection.toggle(note.id))
                              : null,
                          title: Text(note.displayText, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: widget.bookId == null && book != null ? Text(book.title) : null,
                          trailing: selection.active ? null : const Icon(Icons.chevron_right),
                          onLongPress: () => selection.start(note.id),
                          onTap: selection.active
                              ? () => selection.toggle(note.id)
                              : book == null
                                  ? null
                                  : () async {
                                      await Navigator.push(context,
                                          MaterialPageRoute(builder: (_) => PrivateStudyNoteDetailScreen(noteId: note.id, book: book)));
                                      _refreshPrivateStudy(ref, bookId: note.bookId);
                                      setState(() {});
                                    },
                        );
                        if (selection.active) return row;
                        return StudentSwipeRow(
                          dismissKey: ValueKey('private_note_${note.id}'),
                          startLabel: '複製',
                          startIcon: Icons.copy_outlined,
                          endLabel: '刪除',
                          onSwipeStartToEnd: () => copyHumanReadable(
                              context, privateStudyNoteHumanReadable(note, bookTitle: book?.title)),
                          onSwipeEndToStart: () => _delete([note]),
                          child: row,
                        );
                      },
                    ),
        );
      },
    );
  }
}

class PrivateStudyNoteDetailScreen extends ConsumerWidget {
  const PrivateStudyNoteDetailScreen({super.key, required this.noteId, required this.book});
  final String noteId;
  final PrivateStudyBook book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(privateStudyRepositoryProvider);
    return FutureBuilder<PrivateStudyNote?>(
      future: repo.getNote(noteId),
      builder: (context, snap) {
        final note = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: const Text('研讀筆記'),
            actions: [
              if (note != null && !note.isDeleted)
                IconButton(
                  tooltip: '編輯',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    await Navigator.push(context,
                        MaterialPageRoute(builder: (_) => PrivateStudyNoteEditorScreen(book: book, note: note)));
                    _refreshPrivateStudy(ref, bookId: book.id);
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              if (note != null && !note.isDeleted)
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'copy') {
                      await copyHumanReadable(context, privateStudyNoteHumanReadable(note, bookTitle: book.title));
                    } else if (value == 'delete') {
                      await repo.softDeleteNote(noteId);
                      _refreshPrivateStudy(ref, bookId: book.id);
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'copy', child: Text('複製')),
                    PopupMenuItem(value: 'delete', child: Text('刪除筆記')),
                  ],
                ),
            ],
          ),
          body: note == null
              ? const StudentCompactLoading()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
                  children: [
                    if (note.quote.trim().isNotEmpty)
                      _DetailSection(label: '話語／原文摘錄', text: note.quote),
                    if (note.topics.isNotEmpty) ...[
                      Text('主題', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 7),
                      Wrap(spacing: 6, runSpacing: 6, children: [for (final t in note.topics) Chip(label: Text(t))]),
                      const SizedBox(height: 20),
                    ],
                    if (note.reflection.trim().isNotEmpty)
                      _DetailSection(label: '我的整理／心得', text: note.reflection),
                    if (note.scriptureRefs.isNotEmpty) ...[
                      Text('對應經文', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final r in note.scriptureRefs.where((e) => e.trim().isNotEmpty))
                            ActionChip(
                              avatar: const Icon(Icons.menu_book_outlined, size: 16),
                              label: Text(r),
                              onPressed: () => AppLinks.openVerseRef(context, ref, r),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (note.sourceLocation.trim().isNotEmpty)
                      _DetailSection(label: '來源位置', text: note.sourceLocation),
                    if (note.practice.trim().isNotEmpty)
                      _DetailSection(label: '我的實踐', text: note.practice),
                  ],
                ),
        );
      },
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.label, required this.text});
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(height: 1.65)),
        ]),
      );
}

class PrivateStudyNoteEditorScreen extends ConsumerStatefulWidget {
  const PrivateStudyNoteEditorScreen({super.key, required this.book, this.note});
  final PrivateStudyBook book;
  final PrivateStudyNote? note;

  @override
  ConsumerState<PrivateStudyNoteEditorScreen> createState() => _PrivateStudyNoteEditorScreenState();
}

class _PrivateStudyNoteEditorScreenState extends ConsumerState<PrivateStudyNoteEditorScreen>
    with WidgetsBindingObserver {
  late final TextEditingController quote;
  late final TextEditingController reflection;
  late final TextEditingController location;
  late final TextEditingController practice;
  late final String id;
  late final int createdAt;
  late Set<String> topics;
  late List<String> scriptureRefs;
  late final PrivateStudyRepository repo;
  Timer? debounce;
  bool persisted = false;
  String saveState = '';

  @override
  void initState() {
    super.initState();
    repo = ref.read(privateStudyRepositoryProvider);
    WidgetsBinding.instance.addObserver(this);
    final n = widget.note;
    id = n?.id ?? repo.newNoteId();
    createdAt = n?.createdAt ?? DateTime.now().millisecondsSinceEpoch;
    persisted = n != null;
    quote = TextEditingController(text: n?.quote ?? '');
    reflection = TextEditingController(text: n?.reflection ?? '');
    location = TextEditingController(text: n?.sourceLocation ?? '');
    practice = TextEditingController(text: n?.practice ?? '');
    topics = {...?n?.topics};
    scriptureRefs = List<String>.of(n?.scriptureRefs ?? const []);
    for (final c in [quote, reflection, location, practice]) {
      c.addListener(_scheduleSave);
    }
  }

  PrivateStudyNote _draft() => PrivateStudyNote(
        id: id,
        bookId: widget.book.id,
        quote: quote.text,
        topics: topics.toList(),
        reflection: reflection.text,
        scriptureRefs: scriptureRefs,
        sourceLocation: location.text,
        practice: practice.text,
        createdAt: createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

  void _scheduleSave() {
    debounce?.cancel();
    if (mounted) setState(() => saveState = '儲存中…');
    debounce = Timer(const Duration(milliseconds: 550), _save);
  }

  Future<void> _save() async {
    final note = _draft();
    if (!persisted && !note.hasMeaningfulContent) {
      if (mounted) setState(() => saveState = '');
      return;
    }
    final synced = await repo.saveNote(note);
    persisted = true;
    _refreshPrivateStudy(ref, bookId: widget.book.id);
    if (mounted) setState(() => saveState = synced ? '已儲存' : '已儲存在此裝置');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      if (debounce?.isActive ?? false) {
        debounce?.cancel();
        _save();
      }
    }
  }

  @override
  void dispose() {
    final pending = debounce?.isActive ?? false;
    debounce?.cancel();
    if (pending) {
      final note = _draft();
      if (persisted || note.hasMeaningfulContent) repo.saveNote(note);
    }
    WidgetsBinding.instance.removeObserver(this);
    quote.dispose();
    reflection.dispose();
    location.dispose();
    practice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.note == null ? '新增筆記' : '編輯筆記'),
        actions: [
          if (saveState.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(child: Text(saveState, style: Theme.of(context).textTheme.labelSmall)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          TextField(
            controller: quote,
            minLines: 2,
            maxLines: null,
            decoration: const InputDecoration(labelText: '話語／原文摘錄', alignLabelWithHint: true),
          ),
          const SizedBox(height: 20),
          Text('主題', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final topic in kPrivateStudyTopics)
                FilterChip(
                  label: Text(topic),
                  selected: topics.contains(topic),
                  onSelected: (selected) {
                    setState(() => selected ? topics.add(topic) : topics.remove(topic));
                    _scheduleSave();
                  },
                ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: reflection,
            minLines: 3,
            maxLines: null,
            decoration: const InputDecoration(labelText: '我的整理／心得', alignLabelWithHint: true),
          ),
          const SizedBox(height: 18),
          ScriptureReferenceField(
            values: scriptureRefs,
            onChanged: (values) {
              setState(() => scriptureRefs = values);
              _scheduleSave();
            },
          ),
          const SizedBox(height: 18),
          TextField(
            controller: location,
            decoration: const InputDecoration(labelText: '來源位置', hintText: '例如：第 3 章、p.42、第五篇'),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: practice,
            minLines: 3,
            maxLines: null,
            decoration: const InputDecoration(labelText: '我的實踐', alignLabelWithHint: true),
          ),
        ],
      ),
    );
  }
}

class PrivateStudySearchScreen extends ConsumerStatefulWidget {
  const PrivateStudySearchScreen({super.key});

  @override
  ConsumerState<PrivateStudySearchScreen> createState() => _PrivateStudySearchScreenState();
}

class _PrivateStudySearchScreenState extends ConsumerState<PrivateStudySearchScreen> {
  String query = '';
  String bookId = '';
  String topic = '';
  bool? hasScripture;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(privateStudyRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('搜尋我的研讀')),
      body: FutureBuilder<List<PrivateStudyBook>>(
        future: repo.getBooks(),
        builder: (context, booksSnap) {
          final books = booksSnap.data ?? const <PrivateStudyBook>[];
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '搜尋話語、心得、實踐、來源、書名或作者'),
                onChanged: (value) => setState(() => query = value),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                DropdownButton<String>(
                  value: bookId,
                  items: [
                    const DropdownMenuItem(value: '', child: Text('全部書籍')),
                    for (final b in books) DropdownMenuItem(value: b.id, child: Text(b.title)),
                  ],
                  onChanged: (value) => setState(() => bookId = value ?? ''),
                ),
                const SizedBox(width: 14),
                DropdownButton<String>(
                  value: topic,
                  items: [
                    const DropdownMenuItem(value: '', child: Text('全部主題')),
                    for (final t in [...kPrivateStudyTopics, '未分類']) DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: (value) => setState(() => topic = value ?? ''),
                ),
                const SizedBox(width: 14),
                ChoiceChip(
                  label: const Text('有對應經文'),
                  selected: hasScripture == true,
                  onSelected: (value) => setState(() => hasScripture = value ? true : null),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<PrivateStudyNote>>(
                future: repo.search(
                  query: query,
                  bookId: bookId.isEmpty ? null : bookId,
                  topic: topic.isEmpty ? null : topic,
                  hasScripture: hasScripture,
                ),
                builder: (context, resultSnap) {
                  if (!resultSnap.hasData) return const StudentCompactLoading();
                  final notes = resultSnap.data!;
                  final byId = {for (final b in books) b.id: b};
                  if (notes.isEmpty) return const StudentEmptyState(title: '沒有符合的研讀筆記');
                  return ListView.separated(
                    itemCount: notes.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 20),
                    itemBuilder: (context, i) {
                      final n = notes[i];
                      final book = byId[n.bookId];
                      return ListTile(
                        title: Text(n.displayText, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: book == null ? null : Text(book.title),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: book == null
                            ? null
                            : () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => PrivateStudyNoteDetailScreen(noteId: n.id, book: book))),
                      );
                    },
                  );
                },
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class PrivateStudyDeletedScreen extends ConsumerWidget {
  const PrivateStudyDeletedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(privateStudyRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('最近刪除')),
      body: FutureBuilder<List<Object>>(
        future: Future.wait<Object>([
          repo.getBooks(includeDeleted: true),
          repo.getNotes(includeDeleted: true),
        ]),
        builder: (context, snap) {
          if (!snap.hasData) return const StudentCompactLoading();
          final allBooks = snap.data![0] as List<PrivateStudyBook>;
          final books = allBooks.where((b) => b.isDeleted).toList();
          final notes = (snap.data![1] as List<PrivateStudyNote>).where((n) => n.isDeleted).toList();
          final byId = {for (final b in allBooks) b.id: b};
          if (books.isEmpty && notes.isEmpty) return const StudentEmptyState(title: '最近刪除目前是空的');
          return ListView(children: [
            if (books.isNotEmpty) ...[
              _SectionHeader('書籍'),
              for (final b in books)
                _DeletedTile(
                  title: b.title,
                  onRestore: () async {
                    await repo.restoreBook(b.id);
                    _refreshPrivateStudy(ref);
                  },
                  onDelete: () async {
                    await repo.purgeBook(b.id);
                    _refreshPrivateStudy(ref);
                  },
                ),
            ],
            if (notes.isNotEmpty) ...[
              _SectionHeader('筆記'),
              for (final n in notes)
                _DeletedTile(
                  title: n.displayText,
                  subtitle: byId[n.bookId]?.title,
                  onRestore: () async {
                    await repo.restoreNote(n.id);
                    _refreshPrivateStudy(ref, bookId: n.bookId);
                  },
                  onDelete: () async {
                    await repo.purgeNote(n.id);
                    _refreshPrivateStudy(ref, bookId: n.bookId);
                  },
                ),
            ],
          ]);
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      );
}

class _DeletedTile extends StatefulWidget {
  const _DeletedTile({required this.title, this.subtitle, required this.onRestore, required this.onDelete});
  final String title;
  final String? subtitle;
  final Future<void> Function() onRestore;
  final Future<void> Function() onDelete;

  @override
  State<_DeletedTile> createState() => _DeletedTileState();
}

class _DeletedTileState extends State<_DeletedTile> {
  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: widget.subtitle == null ? null : Text(widget.subtitle!),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'restore') await widget.onRestore();
            if (value == 'delete') await widget.onDelete();
            if (mounted) setState(() {});
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'restore', child: Text('還原')),
            PopupMenuItem(value: 'delete', child: Text('永久刪除')),
          ],
        ),
      );
}
