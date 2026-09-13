import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../services/download_stub.dart'
    if (dart.library.js_interop) '../services/download_web.dart';
import '../services/sermon_notes_io.dart';
import '../widgets/scripture_reference_field.dart';
import '../widgets/student_ux.dart';

String _fmtDate(int millis) {
  final d = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}

class SermonNotesScreen extends ConsumerStatefulWidget {
  const SermonNotesScreen({super.key});

  @override
  ConsumerState<SermonNotesScreen> createState() => _SermonNotesScreenState();
}

class _SermonNotesScreenState extends ConsumerState<SermonNotesScreen> {
  final SelectionController<int> selection = SelectionController<int>();

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

  Future<void> _delete(List<SermonNote> notes) async {
    final valid = notes.where((n) => n.id != null).toList();
    if (valid.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(valid.length == 1 ? '刪除這則證道筆記？' : '刪除 ${valid.length} 則證道筆記？'),
        content: const Text('會沿用現有同步刪除紀錄。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('刪除')),
        ],
      ),
    );
    if (ok != true) return;
    final db = ref.read(databaseServiceProvider);
    for (final n in valid) {
      await db.deleteSermonNote(n.id!);
    }
    selection.cancel();
    ref.invalidate(allSermonNotesProvider);
    ref.invalidate(statsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(allSermonNotesProvider);
    final notes = async.value ?? const <SermonNote>[];
    final ids = notes.where((n) => n.id != null).map((n) => n.id!).toList();
    final selected = notes.where((n) => n.id != null && selection.contains(n.id!)).toList();

    return Scaffold(
      appBar: selection.active
          ? StudentSelectionAppBar(
              title: '證道筆記',
              selectionCount: selection.count,
              totalCount: ids.length,
              onCancel: selection.cancel,
              onSelectAll: () => selection.selectAll(ids),
            )
          : AppBar(
              title: const Text('主日・證道筆記'),
              actions: [
                if (notes.isNotEmpty)
                  TextButton(onPressed: selection.start, child: const Text('選取')),
                PopupMenuButton<String>(
                  tooltip: '更多',
                  onSelected: (v) {
                    if (v == 'export_copy') _exportCopy(context, ref);
                    if (v == 'export_file') _exportFile(context, ref);
                    if (v == 'import') _import(context, ref);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'export_copy', child: Text('匯出：複製文字')),
                    if (canPickFile)
                      const PopupMenuItem(value: 'export_file', child: Text('匯出：下載檔案')),
                    const PopupMenuDivider(),
                    PopupMenuItem(value: 'import', child: Text(canPickFile ? '匯入：從檔案／貼上' : '匯入：貼上文字')),
                  ],
                ),
              ],
            ),
      floatingActionButton: selection.active
          ? null
          : FloatingActionButton(
              tooltip: '新增證道筆記',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SermonNoteEditor()),
              ),
              child: const Icon(Icons.add),
            ),
      bottomNavigationBar: selection.active
          ? StudentBatchActionBar(actions: [
              StudentBatchAction(
                label: '複製',
                icon: Icons.copy_outlined,
                onPressed: selected.isEmpty
                    ? null
                    : () => copyHumanReadable(
                          context,
                          sermonNotesToText(selected),
                          success: '已複製 ${selected.length} 則證道筆記',
                        ),
              ),
              StudentBatchAction(
                label: '刪除',
                icon: Icons.delete_outline,
                destructive: true,
                onPressed: selected.isEmpty ? null : () => _delete(selected),
              ),
            ])
          : null,
      body: async.when(
        loading: () => const StudentCompactLoading(),
        error: (_, _) => StudentErrorState(onRetry: () => ref.invalidate(allSermonNotesProvider)),
        data: (list) {
          if (list.isEmpty) {
            return StudentEmptyState(
              title: '還沒有證道筆記',
              subtitle: '把聚會或信息中的重點整理在這裡。',
              icon: Icons.record_voice_over_outlined,
              actionLabel: '新增證道筆記',
              onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SermonNoteEditor())),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 20),
            itemBuilder: (context, i) {
              final n = list[i];
              final id = n.id!;
              final row = ListTile(
                leading: selection.active
                    ? Checkbox(value: selection.contains(id), onChanged: (_) => selection.toggle(id))
                    : const Icon(Icons.record_voice_over_outlined),
                title: Text(n.title.isEmpty ? '未命名筆記' : n.title),
                subtitle: Text([_fmtDate(n.date), if (n.scripture.isNotEmpty) n.scripture.replaceAll('\n', '、')].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: selection.active ? null : const Icon(Icons.chevron_right),
                onLongPress: () => selection.start(id),
                onTap: selection.active
                    ? () => selection.toggle(id)
                    : () => Navigator.push(context, MaterialPageRoute(builder: (_) => SermonNoteEditor(existing: n))),
              );
              if (selection.active) return row;
              return StudentSwipeRow(
                dismissKey: ValueKey('sermon_$id'),
                startLabel: '複製',
                startIcon: Icons.copy_outlined,
                endLabel: '刪除',
                onSwipeStartToEnd: () => copyHumanReadable(context, sermonNotesToText([n])),
                onSwipeEndToStart: () => _delete([n]),
                child: row,
              );
            },
          );
        },
      ),
    );
  }
}

Future<void> _exportCopy(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final notes = await ref.read(allSermonNotesProvider.future);
    if (notes.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('還沒有筆記可匯出')));
      return;
    }
    await Clipboard.setData(ClipboardData(text: sermonNotesToText(notes)));
    messenger.showSnackBar(SnackBar(content: Text('已複製 ${notes.length} 則筆記')));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('暫時無法匯出，請稍後再試。')));
  }
}

Future<void> _exportFile(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final notes = await ref.read(allSermonNotesProvider.future);
    if (notes.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('還沒有筆記可匯出')));
      return;
    }
    final ok = downloadTextFile('證道筆記.md', 'text/markdown', sermonNotesToText(notes));
    messenger.showSnackBar(SnackBar(content: Text(ok ? '已下載 證道筆記.md' : '此平台不支援下載，請改用「複製文字」')));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('暫時無法匯出，請稍後再試。')));
  }
}

Future<void> _import(BuildContext context, WidgetRef ref) async {
  String? text;
  if (canPickFile) {
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(leading: const Icon(Icons.upload_file), title: const Text('選擇檔案（.txt／.md）'), onTap: () => Navigator.pop(ctx, 'file')),
          ListTile(leading: const Icon(Icons.content_paste), title: const Text('貼上文字'), onTap: () => Navigator.pop(ctx, 'paste')),
        ],
      ),
    );
    if (choice == null) return;
    text = choice == 'file' ? await pickTextFile() : (context.mounted ? await _pasteDialog(context) : null);
  } else {
    text = await _pasteDialog(context);
  }
  if (text == null || text.trim().isEmpty || !context.mounted) return;
  final parsed = parseSermonNotes(text);
  final messenger = ScaffoldMessenger.of(context);
  if (parsed.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('讀不到符合格式的筆記。')));
    return;
  }
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('確認匯入'),
      content: Text('將新增 ${parsed.length} 則證道筆記，不會覆蓋現有筆記。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('匯入')),
      ],
    ),
  );
  if (confirm != true) return;
  final db = ref.read(databaseServiceProvider);
  for (final n in parsed) {
    await db.saveSermonNote(n);
  }
  ref.invalidate(allSermonNotesProvider);
  ref.invalidate(statsProvider);
  messenger.showSnackBar(SnackBar(content: Text('已匯入 ${parsed.length} 則筆記')));
}

Future<String?> _pasteDialog(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('貼上筆記文字'),
      content: TextField(controller: controller, maxLines: 10, minLines: 6, autofocus: true, decoration: const InputDecoration(hintText: '貼上匯出的內容')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('解析')),
      ],
    ),
  );
}

class SermonNoteEditor extends ConsumerStatefulWidget {
  const SermonNoteEditor({super.key, this.existing});
  final SermonNote? existing;

  @override
  ConsumerState<SermonNoteEditor> createState() => _SermonNoteEditorState();
}

class _SermonNoteEditorState extends ConsumerState<SermonNoteEditor> {
  late final Map<String, TextEditingController> _c;
  late int _date;
  late List<String> _scriptureRefs;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = e?.date ?? DateTime.now().millisecondsSinceEpoch;
    _scriptureRefs = (e?.scripture ?? '')
        .split(RegExp(r'[\n,，]+'))
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList();
    _c = {
      'title': TextEditingController(text: e?.title ?? ''),
      'content': TextEditingController(text: e?.content ?? ''),
      'trinityWord': TextEditingController(text: e?.trinityWord ?? ''),
      'practice': TextEditingController(text: e?.practice ?? ''),
      'reflection': TextEditingController(text: e?.reflection ?? ''),
    };
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final db = ref.read(databaseServiceProvider);
    final e = widget.existing;
    await db.saveSermonNote(SermonNote(
      id: e?.id,
      date: _date,
      title: _c['title']!.text.trim(),
      scripture: _scriptureRefs.join('\n'),
      content: _c['content']!.text.trim(),
      trinityWho: e?.trinityWho ?? '',
      trinityWord: _c['trinityWord']!.text.trim(),
      practice: _c['practice']!.text.trim(),
      reflection: _c['reflection']!.text.trim(),
      createdAt: e?.createdAt ?? 0,
      updatedAt: 0,
    ));
    ref.invalidate(allSermonNotesProvider);
    ref.invalidate(statsProvider);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (widget.existing?.id == null) return;
    await ref.read(databaseServiceProvider).deleteSermonNote(widget.existing!.id!);
    ref.invalidate(allSermonNotesProvider);
    ref.invalidate(statsProvider);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.fromMillisecondsSinceEpoch(_date),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked.millisecondsSinceEpoch);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? '新增證道筆記' : '編輯證道筆記'),
        actions: [
          if (widget.existing != null)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete') _delete();
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('刪除'))],
            ),
          TextButton(onPressed: _save, child: const Text('完成')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: const Text('日期'),
            trailing: Text(_fmtDate(_date)),
            onTap: _pickDate,
          ),
          _field('title', '主題'),
          const SizedBox(height: 18),
          ScriptureReferenceField(
            values: _scriptureRefs,
            onChanged: (values) => setState(() => _scriptureRefs = values),
          ),
          _field('content', '筆記', maxLines: 6),
          _field('trinityWord', '祂的話', maxLines: 3),
          _field('practice', '實踐', maxLines: 3),
          _field('reflection', '感想', maxLines: 3),
        ],
      ),
    );
  }

  Widget _field(String key, String label, {int maxLines = 1}) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: TextField(
          controller: _c[key],
          maxLines: maxLines,
          decoration: InputDecoration(labelText: label, alignLabelWithHint: true),
        ),
      );
}
