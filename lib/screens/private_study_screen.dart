import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/private_study.dart';
import '../providers/providers.dart' show databaseServiceProvider;
import '../services/app_links.dart';
import '../services/private_study_repository.dart';

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

class PrivateStudyHomeScreen extends ConsumerStatefulWidget {
  const PrivateStudyHomeScreen({super.key});

  @override
  ConsumerState<PrivateStudyHomeScreen> createState() =>
      _PrivateStudyHomeScreenState();
}

class _PrivateStudyHomeScreenState extends ConsumerState<PrivateStudyHomeScreen> {
  bool _sortByTitle = false;

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
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrivateStudySearchScreen()),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'deleted') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const PrivateStudyDeletedScreen()),
                ).then((_) => _refreshPrivateStudy(ref));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'deleted', child: Text('最近刪除')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(privateStudyRepositoryProvider).syncCurrentUser();
          _refreshPrivateStudy(ref);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('我的書籍',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                PopupMenuButton<bool>(
                  tooltip: '排序',
                  initialValue: _sortByTitle,
                  onSelected: (v) => setState(() => _sortByTitle = v),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: false, child: Text('最近研讀')),
                    PopupMenuItem(value: true, child: Text('書名')),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.sort, size: 18),
                      const SizedBox(width: 4),
                      Text(_sortByTitle ? '書名' : '最近研讀'),
                    ]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            booksAsync.when(
              loading: () => const Center(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator())),
              error: (_, _) => const _PrivateStudyEmpty(
                  title: '暫時無法載入', subtitle: '本機資料仍會保留，請稍後再試。'),
              data: (original) {
                if (original.isEmpty) {
                  return _PrivateStudyEmpty(
                    title: '開始你的第一本研讀書籍',
                    subtitle: '把閱讀時重要的話語、心得、經文與實踐整理在這裡。',
                    actionLabel: '＋新增書籍',
                    onAction: () => _addBook(context),
                  );
                }
                final books = [...original];
                if (_sortByTitle) {
                  books.sort((a, b) => a.title.compareTo(b.title));
                }
                return Column(children: [
                  for (final book in books)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.menu_book_outlined),
                        title: Text(book.title,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle:
                            book.author.isEmpty ? null : Text(book.author),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await ref
                              .read(privateStudyRepositoryProvider)
                              .touchBook(book.id);
                          if (!context.mounted) return;
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    PrivateStudyBookScreen(bookId: book.id)),
                          );
                          _refreshPrivateStudy(ref, bookId: book.id);
                        },
                      ),
                    ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('新增書籍'),
                    onPressed: () => _addBook(context),
                  ),
                ]);
              },
            ),
            const SizedBox(height: 28),
            Text('全部筆記',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            notesAsync.when(
              loading: () => const SizedBox(height: 72),
              error: (_, _) => const SizedBox.shrink(),
              data: (notes) => Card(
                child: ListTile(
                  leading: const Icon(Icons.library_books_outlined),
                  title: const Text('主題分類'),
                  subtitle: Text(notes.isEmpty ? '還沒有研讀筆記。' : '${notes.length} 則筆記'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const PrivateStudyAllTopicsScreen()),
                  ),
                ),
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
      builder: (dialogContext) => AlertDialog(
        title: const Text('新增書籍'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: title,
            autofocus: true,
            decoration: const InputDecoration(labelText: '書名 *'),
          ),
          TextField(
            controller: author,
            decoration: const InputDecoration(labelText: '作者（選填）'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('建立')),
        ],
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    final repo = ref.read(privateStudyRepositoryProvider);
    final now = DateTime.now().millisecondsSinceEpoch;
    final book = PrivateStudyBook(
      id: repo.newBookId(),
      title: title.text.trim(),
      author: author.text.trim(),
      createdAt: now,
      updatedAt: now,
      lastStudiedAt: now,
    );
    await repo.saveBook(book);
    _refreshPrivateStudy(ref);
  }
}

class PrivateStudyBookScreen extends ConsumerWidget {
  final String bookId;
  const PrivateStudyBookScreen({super.key, required this.bookId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(privateStudyRepositoryProvider);
    final notesAsync = ref.watch(privateStudyBookNotesProvider(bookId));
    return FutureBuilder<PrivateStudyBook?>(
      future: repo.getBook(bookId),
      builder: (context, bookSnap) {
        final book = bookSnap.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(book?.title ?? '我的研讀'),
            actions: [
              if (book != null)
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v != 'delete') return;
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('刪除這本書？'),
                        content: const Text('這本書和其中的研讀筆記會一起移到「最近刪除」。'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('取消')),
                          FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('刪除')),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await repo.softDeleteBook(bookId);
                      _refreshPrivateStudy(ref, bookId: bookId);
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'delete', child: Text('刪除書籍')),
                  ],
                ),
            ],
          ),
          body: book == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    Text(book.title,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    if (book.author.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(book.author,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ],
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('新增筆記'),
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  PrivateStudyNoteEditorScreen(book: book)),
                        );
                        _refreshPrivateStudy(ref, bookId: bookId);
                      },
                    ),
                    const SizedBox(height: 28),
                    Text('主題分類',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    notesAsync.when(
                      loading: () => const Center(
                          child: Padding(
                              padding: EdgeInsets.all(24),
                              child: CircularProgressIndicator())),
                      error: (_, _) => const Text('暫時無法載入筆記。'),
                      data: (notes) {
                        if (notes.isEmpty) {
                          return _PrivateStudyEmpty(
                            title: '這本書還沒有研讀筆記',
                            subtitle: '閱讀時遇到重要的話語，可以從這裡記下來。',
                            actionLabel: '＋新增筆記',
                            onAction: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        PrivateStudyNoteEditorScreen(book: book)),
                              );
                              _refreshPrivateStudy(ref, bookId: bookId);
                            },
                          );
                        }
                        return _TopicGrid(
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
                        );
                      },
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
    final notesAsync = ref.watch(privateStudyAllNotesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('全部筆記')),
      body: notesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('暫時無法載入筆記。')),
        data: (notes) {
          if (notes.isEmpty) {
            return const _PrivateStudyEmpty(
              title: '還沒有研讀筆記。',
              subtitle: '從「我的書籍」選一本書開始整理。',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('主題分類',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _TopicGrid(
                notes: notes,
                onTopic: (topic) => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PrivateStudyTopicNotesScreen(topic: topic),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TopicGrid extends StatelessWidget {
  final List<PrivateStudyNote> notes;
  final void Function(String topic) onTopic;
  const _TopicGrid({required this.notes, required this.onTopic});

  @override
  Widget build(BuildContext context) {
    final topics = [...kPrivateStudyTopics, '未分類'];
    int countFor(String topic) => topic == '未分類'
        ? notes.where((n) => n.topics.isEmpty).length
        : notes.where((n) => n.topics.contains(topic)).length;
    return Column(
      children: [
        for (final topic in topics)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              title: Text(topic),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${countFor(topic)}',
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right),
              ]),
              onTap: () => onTopic(topic),
            ),
          ),
      ],
    );
  }
}

class PrivateStudyTopicNotesScreen extends ConsumerWidget {
  final String topic;
  final String? bookId;
  final String? bookTitle;
  const PrivateStudyTopicNotesScreen({
    super.key,
    required this.topic,
    this.bookId,
    this.bookTitle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(privateStudyRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(topic)),
      body: FutureBuilder<List<Object>>(
        future: Future.wait<Object>([
          repo.getNotes(bookId: bookId, topic: topic),
          repo.getBooks(),
        ]),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final notes = snap.data![0] as List<PrivateStudyNote>;
          final books = snap.data![1] as List<PrivateStudyBook>;
          final byId = {for (final b in books) b.id: b};
          if (notes.isEmpty) {
            return _PrivateStudyEmpty(title: '目前沒有「$topic」的筆記。');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: notes.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final note = notes[i];
              final sourceBook = byId[note.bookId];
              return ListTile(
                title: Text(note.displayText,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: bookId == null && sourceBook != null
                    ? Text(sourceBook.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis)
                    : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  if (sourceBook == null) return;
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PrivateStudyNoteDetailScreen(
                        noteId: note.id,
                        book: sourceBook,
                      ),
                    ),
                  );
                  _refreshPrivateStudy(ref, bookId: note.bookId);
                },
              );
            },
          );
        },
      ),
    );
  }
}

class PrivateStudyNoteDetailScreen extends ConsumerWidget {
  final String noteId;
  final PrivateStudyBook book;
  const PrivateStudyNoteDetailScreen({
    super.key,
    required this.noteId,
    required this.book,
  });

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
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PrivateStudyNoteEditorScreen(
                            book: book, note: note),
                      ),
                    );
                    _refreshPrivateStudy(ref, bookId: book.id);
                    if (context.mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PrivateStudyNoteDetailScreen(
                              noteId: noteId, book: book),
                        ),
                      );
                    }
                  },
                ),
              if (note != null && !note.isDeleted)
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v != 'delete') return;
                    await repo.softDeleteNote(noteId);
                    _refreshPrivateStudy(ref, bookId: book.id);
                    if (context.mounted) Navigator.pop(context);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'delete', child: Text('刪除筆記')),
                  ],
                ),
            ],
          ),
          body: note == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
                  children: [
                    if (note.quote.trim().isNotEmpty)
                      _DetailSection(label: '話語／原文摘錄', text: note.quote),
                    if (note.topics.isNotEmpty) ...[
                      Text('主題',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [for (final t in note.topics) Chip(label: Text(t))],
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (note.reflection.trim().isNotEmpty)
                      _DetailSection(label: '我的整理／心得', text: note.reflection),
                    if (note.scriptureRefs.isNotEmpty) ...[
                      Text('對應經文',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
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
  final String label;
  final String text;
  const _DetailSection({required this.label, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(height: 1.65)),
        ]),
      );
}

class PrivateStudyNoteEditorScreen extends ConsumerStatefulWidget {
  final PrivateStudyBook book;
  final PrivateStudyNote? note;
  const PrivateStudyNoteEditorScreen({
    super.key,
    required this.book,
    this.note,
  });

  @override
  ConsumerState<PrivateStudyNoteEditorScreen> createState() =>
      _PrivateStudyNoteEditorScreenState();
}

class _PrivateStudyNoteEditorScreenState
    extends ConsumerState<PrivateStudyNoteEditorScreen> {
  late final TextEditingController _quote;
  late final TextEditingController _reflection;
  late final TextEditingController _refs;
  late final TextEditingController _location;
  late final TextEditingController _practice;
  late final String _id;
  late final int _createdAt;
  late Set<String> _topics;
  Timer? _debounce;
  bool _persisted = false;
  String _saveState = '';

  @override
  void initState() {
    super.initState();
    final note = widget.note;
    _id = note?.id ?? 'psn_${DateTime.now().microsecondsSinceEpoch}';
    _createdAt = note?.createdAt ?? DateTime.now().millisecondsSinceEpoch;
    _persisted = note != null;
    _quote = TextEditingController(text: note?.quote ?? '');
    _reflection = TextEditingController(text: note?.reflection ?? '');
    _refs = TextEditingController(text: note?.scriptureRefs.join('\n') ?? '');
    _location = TextEditingController(text: note?.sourceLocation ?? '');
    _practice = TextEditingController(text: note?.practice ?? '');
    _topics = {...?note?.topics};
    for (final c in [_quote, _reflection, _refs, _location, _practice]) {
      c.addListener(_scheduleSave);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _quote.dispose();
    _reflection.dispose();
    _refs.dispose();
    _location.dispose();
    _practice.dispose();
    super.dispose();
  }

  PrivateStudyNote _draft() {
    final refs = _refs.text
        .split(RegExp(r'[\n,，]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return PrivateStudyNote(
      id: _id,
      bookId: widget.book.id,
      quote: _quote.text,
      topics: _topics.toList(),
      reflection: _reflection.text,
      scriptureRefs: refs,
      sourceLocation: _location.text,
      practice: _practice.text,
      createdAt: _createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  void _scheduleSave() {
    _debounce?.cancel();
    if (mounted) setState(() => _saveState = '儲存中…');
    _debounce = Timer(const Duration(milliseconds: 550), _save);
  }

  Future<void> _save() async {
    final note = _draft();
    if (!_persisted && !note.hasMeaningfulContent) {
      if (mounted) setState(() => _saveState = '');
      return;
    }
    final synced = await ref.read(privateStudyRepositoryProvider).saveNote(note);
    _persisted = true;
    _refreshPrivateStudy(ref, bookId: widget.book.id);
    if (mounted) {
      setState(() => _saveState = synced ? '已儲存' : '已儲存在此裝置');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.note == null ? '新增筆記' : '編輯筆記'),
        actions: [
          if (_saveState.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: Text(_saveState,
                    style: Theme.of(context).textTheme.labelSmall),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          TextField(
            controller: _quote,
            minLines: 2,
            maxLines: null,
            decoration: const InputDecoration(
              labelText: '話語／原文摘錄',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 20),
          Text('主題（可複選）',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final topic in kPrivateStudyTopics)
                FilterChip(
                  label: Text(topic),
                  selected: _topics.contains(topic),
                  onSelected: (selected) {
                    setState(() {
                      selected ? _topics.add(topic) : _topics.remove(topic);
                    });
                    _scheduleSave();
                  },
                ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _reflection,
            minLines: 3,
            maxLines: null,
            decoration: const InputDecoration(
                labelText: '我的整理／心得', alignLabelWithHint: true),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _refs,
            minLines: 2,
            maxLines: null,
            decoration: const InputDecoration(
              labelText: '對應經文',
              hintText: '一行一段，例如：約翰福音 3:16',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _location,
            decoration: const InputDecoration(
              labelText: '來源位置',
              hintText: '例如：第 3 章、p.42、第五篇',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _practice,
            minLines: 3,
            maxLines: null,
            decoration: const InputDecoration(
                labelText: '我的實踐', alignLabelWithHint: true),
          ),
        ],
      ),
    );
  }
}

class PrivateStudySearchScreen extends ConsumerStatefulWidget {
  const PrivateStudySearchScreen({super.key});
  @override
  ConsumerState<PrivateStudySearchScreen> createState() =>
      _PrivateStudySearchScreenState();
}

class _PrivateStudySearchScreenState
    extends ConsumerState<PrivateStudySearchScreen> {
  String _query = '';
  String _bookId = '';
  String _topic = '';
  bool? _hasScripture;

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
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: TextField(
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '搜尋話語、心得、實踐、來源、書名或作者'),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                DropdownButton<String>(
                  value: _bookId,
                  items: [
                    const DropdownMenuItem(value: '', child: Text('全部書籍')),
                    for (final b in books)
                      DropdownMenuItem(value: b.id, child: Text(b.title)),
                  ],
                  onChanged: (v) => setState(() => _bookId = v ?? ''),
                ),
                const SizedBox(width: 14),
                DropdownButton<String>(
                  value: _topic,
                  items: [
                    const DropdownMenuItem(value: '', child: Text('全部主題')),
                    for (final t in [...kPrivateStudyTopics, '未分類'])
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: (v) => setState(() => _topic = v ?? ''),
                ),
                const SizedBox(width: 14),
                ChoiceChip(
                  label: const Text('有對應經文'),
                  selected: _hasScripture == true,
                  onSelected: (v) =>
                      setState(() => _hasScripture = v ? true : null),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<PrivateStudyNote>>(
                future: repo.search(
                  query: _query,
                  bookId: _bookId.isEmpty ? null : _bookId,
                  topic: _topic.isEmpty ? null : _topic,
                  hasScripture: _hasScripture,
                ),
                builder: (context, resultSnap) {
                  if (!resultSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final notes = resultSnap.data!;
                  final byId = {for (final b in books) b.id: b};
                  if (notes.isEmpty) {
                    return const Center(child: Text('沒有符合的研讀筆記。'));
                  }
                  return ListView.separated(
                    itemCount: notes.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final n = notes[i];
                      final book = byId[n.bookId];
                      return ListTile(
                        title: Text(n.displayText,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: book == null ? null : Text(book.title),
                        onTap: book == null
                            ? null
                            : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PrivateStudyNoteDetailScreen(
                                        noteId: n.id, book: book),
                                  ),
                                ),
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
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final books = (snap.data![0] as List<PrivateStudyBook>)
              .where((b) => b.isDeleted)
              .toList();
          final notes = (snap.data![1] as List<PrivateStudyNote>)
              .where((n) => n.isDeleted)
              .toList();
          final allBooks = snap.data![0] as List<PrivateStudyBook>;
          final byId = {for (final b in allBooks) b.id: b};
          if (books.isEmpty && notes.isEmpty) {
            return const Center(child: Text('最近刪除目前是空的。'));
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (books.isNotEmpty) ...[
                Text('書籍',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
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
                const SizedBox(height: 20),
                Text('筆記',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
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
            ],
          );
        },
      ),
    );
  }
}

class _DeletedTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Future<void> Function() onRestore;
  final Future<void> Function() onDelete;
  const _DeletedTile({
    required this.title,
    this.subtitle,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: subtitle == null ? null : Text(subtitle!),
          trailing: PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'restore') {
                await onRestore();
              } else if (v == 'delete') {
                await onDelete();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'restore', child: Text('還原')),
              PopupMenuItem(value: 'delete', child: Text('永久刪除')),
            ],
          ),
        ),
      );
}

class _PrivateStudyEmpty extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _PrivateStudyEmpty({
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.auto_stories_outlined,
              size: 40, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 10),
          Text(title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!, textAlign: TextAlign.center),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ]),
      );
}
