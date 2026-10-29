import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';

/// 讀經頁「同一節多則經文筆記」：清單（看全部／選一則編輯／刪除／新增）與單則編輯器。
///
/// 每則筆記以 id 操作：新增一律建立新的一則（不會覆蓋同節既有筆記）；
/// 編輯只改選中的那一則（保留它的標題與額外引用）；刪除＝移到「最近刪除」（可還原）。
/// 寫入或刪除失敗時不關閉、保留輸入內容，畫面重新讀取實際資料，並提供重試。

/// 筆記摘要：有標題用標題，否則取內文第一個非空行。
String verseNoteSummary(Note n) {
  final title = n.title.trim();
  if (title.isNotEmpty) return title;
  for (final line in n.content.split('\n')) {
    final t = line.trim();
    if (t.isNotEmpty) return t;
  }
  return '（空白筆記）';
}

String _fmtUpdated(int millis) {
  final d = DateTime.fromMillisecondsSinceEpoch(millis);
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    return '今天 ${two(d.hour)}:${two(d.minute)}';
  }
  if (d.year == now.year) return '${d.month}/${d.day}';
  return '${d.year}/${d.month}/${d.day}';
}

/// 開同節筆記清單。[onChanged] 在任何寫入嘗試後呼叫（讓讀經頁重抓標記）。
Future<void> showVerseNotesSheet(
  BuildContext context, {
  required String bookName,
  required int bookId,
  required int chapter,
  required int verse,
  required VoidCallback onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => VerseNotesSheet(
      bookName: bookName,
      bookId: bookId,
      chapter: chapter,
      verse: verse,
      onChanged: onChanged,
    ),
  );
}

/// 開單則編輯器（[existing] 為 null＝新增一則）。成功儲存或刪除回傳 true。
Future<bool?> showVerseNoteEditor(
  BuildContext context, {
  required String bookName,
  required int bookId,
  required int chapter,
  required int verse,
  Note? existing,
  required VoidCallback onChanged,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => VerseNoteEditorSheet(
      bookName: bookName,
      bookId: bookId,
      chapter: chapter,
      verse: verse,
      existing: existing,
      onChanged: onChanged,
    ),
  );
}

Future<bool> _confirmMoveToTrash(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('移到最近刪除？'),
      content: const Text('之後仍可從「最近刪除」還原這則筆記。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('刪除'),
        ),
      ],
    ),
  );
  return ok == true;
}

Widget _errorLine(BuildContext context, String text) => Semantics(
  liveRegion: true,
  child: Text(
    text,
    style: TextStyle(color: Theme.of(context).colorScheme.error),
  ),
);

class VerseNotesSheet extends ConsumerStatefulWidget {
  final String bookName;
  final int bookId;
  final int chapter;
  final int verse;
  final VoidCallback onChanged;

  const VerseNotesSheet({
    super.key,
    required this.bookName,
    required this.bookId,
    required this.chapter,
    required this.verse,
    required this.onChanged,
  });

  @override
  ConsumerState<VerseNotesSheet> createState() => _VerseNotesSheetState();
}

class _VerseNotesSheetState extends ConsumerState<VerseNotesSheet> {
  List<Note>? _notes;
  bool _loadFailed = false;

  /// 刪除失敗的那則（重試用，不再重複詢問）。
  Note? _failedDelete;
  int? _deletingId;
  String? _status;

  String get _ref => '${widget.bookName} ${widget.chapter}:${widget.verse}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadFailed = false);
    try {
      final notes = await ref
          .read(databaseServiceProvider)
          .getVerseNotes(widget.bookId, widget.chapter, widget.verse);
      if (!mounted) return;
      setState(() => _notes = notes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  Future<void> _openEditor(Note? existing) async {
    final ok = await showVerseNoteEditor(
      context,
      bookName: widget.bookName,
      bookId: widget.bookId,
      chapter: widget.chapter,
      verse: widget.verse,
      existing: existing,
      onChanged: widget.onChanged,
    );
    if (!mounted) return;
    setState(() {
      _failedDelete = null;
      _status = ok == true ? (existing == null ? '已新增筆記' : '已儲存') : null;
    });
    await _load();
  }

  Future<void> _delete(Note note) async {
    if (!await _confirmMoveToTrash(context) || !mounted) return;
    await _performDelete(note);
  }

  /// 已確認後移到最近刪除；重試走這裡。成功或失敗都重讀清單，顯示實際狀態。
  Future<void> _performDelete(Note note) async {
    if (note.id == null || _deletingId != null) return;
    setState(() {
      _deletingId = note.id;
      _status = null;
    });
    var failed = false;
    try {
      await ref.read(databaseServiceProvider).softDeleteNoteById(note.id!);
    } catch (_) {
      failed = true;
    } finally {
      widget.onChanged();
    }
    if (!mounted) return;
    setState(() {
      _deletingId = null;
      _failedDelete = failed ? note : null;
      _status = failed ? null : '已移到最近刪除，可在「經文筆記」還原';
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final notes = _notes;
    final Widget body;
    if (notes == null && _loadFailed) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            _errorLine(context, '筆記暫時無法載入。'),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('重試')),
          ],
        ),
      );
    } else if (notes == null) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: CircularProgressIndicator(semanticsLabel: '正在載入筆記'),
        ),
      );
    } else if (notes.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          '這一節還沒有筆記。',
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: scheme.outline),
        ),
      );
    } else {
      body = Column(
        children: [
          for (final n in notes)
            ListTile(
              key: ValueKey('verse-note-${n.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                verseNoteSummary(n),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  if (n.title.trim().isNotEmpty && n.content.trim().isNotEmpty)
                    n.content.trim().replaceAll('\n', ' '),
                  _fmtUpdated(n.updatedAt),
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: _deletingId == null ? () => _openEditor(n) : null,
              trailing: IconButton(
                tooltip: '刪除這則筆記',
                icon: const Icon(Icons.delete_outline),
                onPressed: _deletingId == null ? () => _delete(n) : null,
              ),
            ),
        ],
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                notes == null || notes.isEmpty
                    ? '$_ref 筆記'
                    : '$_ref 筆記（${notes.length} 則）',
                style: text.titleMedium,
              ),
            ),
            const SizedBox(height: 4),
            if (_failedDelete != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _errorLine(context, '刪除失敗，筆記仍保留。')),
                  TextButton(
                    onPressed: _deletingId == null
                        ? () => _performDelete(_failedDelete!)
                        : null,
                    child: const Text('重試'),
                  ),
                ],
              ),
            ],
            if (_status != null)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _status!,
                    style: text.bodySmall?.copyWith(color: scheme.outline),
                  ),
                ),
              ),
            if (notes != null && _loadFailed)
              Row(
                children: [
                  Expanded(child: _errorLine(context, '筆記暫時無法重新整理。')),
                  TextButton(onPressed: _load, child: const Text('重試')),
                ],
              ),
            body,
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('新增筆記'),
              onPressed: _deletingId == null ? () => _openEditor(null) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class VerseNoteEditorSheet extends ConsumerStatefulWidget {
  final String bookName;
  final int bookId;
  final int chapter;
  final int verse;
  final Note? existing;
  final VoidCallback onChanged;

  const VerseNoteEditorSheet({
    super.key,
    required this.bookName,
    required this.bookId,
    required this.chapter,
    required this.verse,
    this.existing,
    required this.onChanged,
  });

  @override
  ConsumerState<VerseNoteEditorSheet> createState() =>
      _VerseNoteEditorSheetState();
}

class _VerseNoteEditorSheetState extends ConsumerState<VerseNoteEditorSheet> {
  late final TextEditingController _content = TextEditingController(
    text: widget.existing?.content ?? '',
  );
  late final TextEditingController _tags = TextEditingController(
    text: widget.existing?.tags ?? '',
  );
  bool _busy = false;
  bool _saveFailed = false;
  bool _deleteFailed = false;

  @override
  void initState() {
    super.initState();
    _content.addListener(_onContentChanged);
  }

  void _onContentChanged() => setState(() {});

  @override
  void dispose() {
    _content.removeListener(_onContentChanged);
    _content.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final content = _content.text.trim();
    if (content.isEmpty || _busy) return;
    final e = widget.existing;
    // 新增：id 為 null → 一定建立新的一則，不會覆蓋同節既有筆記。
    // 編輯：以 id 只改這一則，保留標題與額外引用。
    final note = Note(
      id: e?.id,
      bookId: widget.bookId,
      chapter: widget.chapter,
      verse: widget.verse,
      title: e?.title ?? '',
      content: content,
      tags: _tags.text.trim(),
      refs: e?.refs ?? const [],
      createdAt: e?.createdAt ?? 0,
      updatedAt: e?.updatedAt ?? 0,
    );
    setState(() {
      _busy = true;
      _saveFailed = false;
      _deleteFailed = false;
    });
    var ok = false;
    try {
      await ref.read(databaseServiceProvider).saveNoteFull(note);
      ok = true;
    } catch (_) {
      ok = false;
    } finally {
      widget.onChanged();
    }
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _saveFailed = true;
    });
  }

  Future<void> _delete() async {
    final id = widget.existing?.id;
    if (id == null || _busy) return;
    if (!_deleteFailed && !await _confirmMoveToTrash(context)) return;
    if (!mounted) return;
    setState(() {
      _busy = true;
      _saveFailed = false;
    });
    var ok = false;
    try {
      await ref.read(databaseServiceProvider).softDeleteNoteById(id);
      ok = true;
    } catch (_) {
      ok = false;
    } finally {
      widget.onChanged();
    }
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _deleteFailed = true;
    });
  }

  void _insertTemplate() {
    // 觀察 / 相信 / 行動 三欄整理模板
    final t = _content.text;
    _content.text = '${t.isEmpty ? '' : '$t\n'}【觀察】\n\n【相信】\n\n【行動】\n';
    _content.selection = TextSelection.collapsed(
      offset: _content.text.indexOf('\n【相信】'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    final canSave = !_busy && _content.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      '${widget.bookName} ${widget.chapter}:${widget.verse} '
                      '${isNew ? '新增筆記' : '編輯筆記'}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.view_column_outlined, size: 18),
                  label: const Text('三欄模板'),
                  onPressed: _busy ? null : _insertTemplate,
                ),
              ],
            ),
            if (!isNew && widget.existing!.title.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '標題：${widget.existing!.title.trim()}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _content,
              maxLines: 5,
              autofocus: true,
              readOnly: _busy,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '筆記內容',
                hintText: '寫下你的想法…',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _tags,
              maxLines: 1,
              readOnly: _busy,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.tag, size: 18),
                labelText: '標籤',
                hintText: '空格分隔，例：信心 禱告',
                isDense: true,
              ),
            ),
            if (_saveFailed) ...[
              const SizedBox(height: 8),
              _errorLine(context, '儲存失敗，內容仍保留，請再試一次。'),
            ],
            if (_deleteFailed) ...[
              const SizedBox(height: 8),
              _errorLine(context, '刪除失敗，筆記仍保留，請再試一次。'),
            ],
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                if (!isNew)
                  TextButton(
                    onPressed: _busy ? null : _delete,
                    child: Text(_deleteFailed ? '重試刪除' : '刪除'),
                  ),
                FilledButton(
                  onPressed: canSave ? _save : null,
                  child: Text(_busy ? '儲存中…' : (_saveFailed ? '重試儲存' : '儲存')),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
