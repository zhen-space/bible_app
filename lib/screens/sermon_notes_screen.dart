import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../services/download_stub.dart'
    if (dart.library.js_interop) '../services/download_web.dart';
import '../services/sermon_notes_io.dart';

String _fmtDate(int millis) {
  final d = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}

/// 主日／證道筆記列表。
class SermonNotesScreen extends ConsumerWidget {
  const SermonNotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(allSermonNotesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('主日・證道筆記'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.ios_share),
            tooltip: '匯入／匯出',
            onSelected: (v) {
              if (v == 'export_copy') _exportCopy(context, ref);
              if (v == 'export_file') _exportFile(context, ref);
              if (v == 'import') _import(context, ref);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'export_copy', child: Text('匯出：複製文字')),
              if (canPickFile)
                const PopupMenuItem(
                    value: 'export_file', child: Text('匯出：下載檔案')),
              const PopupMenuDivider(),
              PopupMenuItem(
                  value: 'import',
                  child: Text(canPickFile ? '匯入：從檔案／貼上' : '匯入：貼上文字')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('新增'),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SermonNoteEditor()),
        ),
      ),
      body: notesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('載入失敗：$e')),
        data: (notes) {
          if (notes.isEmpty) {
            return const Center(child: Text('還沒有證道筆記，點右下角「新增」'));
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: notes.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final n = notes[i];
              return ListTile(
                title: Text(n.title.isEmpty ? '(未命名)' : n.title),
                subtitle: Text([
                  _fmtDate(n.date),
                  if (n.scripture.isNotEmpty) n.scripture,
                ].join('　')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => SermonNoteEditor(existing: n)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// 匯出：把全部證道筆記整理成 Markdown 複製到剪貼簿（各平台都通）。
Future<void> _exportCopy(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final notes = await ref.read(allSermonNotesProvider.future);
    if (notes.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('還沒有筆記可匯出')));
      return;
    }
    await Clipboard.setData(ClipboardData(text: sermonNotesToText(notes)));
    messenger.showSnackBar(
        SnackBar(content: Text('已複製 ${notes.length} 則筆記')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('匯出失敗：$e')));
  }
}

/// 匯出：下載成 .md 檔（網頁）。之後可原樣匯回，或自己編輯後匯入。
Future<void> _exportFile(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final notes = await ref.read(allSermonNotesProvider.future);
    if (notes.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('還沒有筆記可匯出')));
      return;
    }
    final ok = downloadTextFile(
        '證道筆記.md', 'text/markdown', sermonNotesToText(notes));
    messenger.showSnackBar(SnackBar(
        content: Text(ok ? '已下載 證道筆記.md' : '此平台不支援下載，請改用「複製文字」')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('匯出失敗：$e')));
  }
}

/// 匯入：從檔案（網頁）或貼上文字取得內容 → 解析成筆記格式 → 確認後新增。
Future<void> _import(BuildContext context, WidgetRef ref) async {
  String? text;
  if (canPickFile) {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('選擇檔案（.txt／.md）'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: const Text('貼上文字'),
              onTap: () => Navigator.pop(ctx, 'paste'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (choice == 'file') {
      text = await pickTextFile();
    } else if (context.mounted) {
      text = await _pasteDialog(context);
    }
  } else {
    text = await _pasteDialog(context);
  }
  if (text == null || text.trim().isEmpty || !context.mounted) return;

  final parsed = parseSermonNotes(text);
  final messenger = ScaffoldMessenger.of(context);
  if (parsed.isEmpty) {
    messenger.showSnackBar(const SnackBar(
        content: Text('讀不到符合格式的筆記。請用「匯出」下載的格式，或每則含 #### 主題／日期…等小標。')));
    return;
  }
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('確認匯入'),
      content: Text('將新增 ${parsed.length} 則證道筆記（不會覆蓋現有筆記）。'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('匯入')),
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

/// 貼上文字的輸入對話框（手機主要靠這個匯入）。
Future<String?> _pasteDialog(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('貼上筆記文字'),
      content: TextField(
        controller: controller,
        maxLines: 10,
        minLines: 6,
        autofocus: true,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          hintText: '貼上匯出的內容，或每則含 #### 主題／日期／經文…等小標',
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('解析')),
      ],
    ),
  );
}

/// 證道筆記編輯（結構化表單）。
class SermonNoteEditor extends ConsumerStatefulWidget {
  final SermonNote? existing;

  const SermonNoteEditor({super.key, this.existing});

  @override
  ConsumerState<SermonNoteEditor> createState() => _SermonNoteEditorState();
}

class _SermonNoteEditorState extends ConsumerState<SermonNoteEditor> {
  late final Map<String, TextEditingController> _c;
  late int _date;

  /// 分類快速點選捷徑（可自填其他值）。
  static const _whoShortcuts = ['神', '聖子', '聖靈', '耶穌'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = e?.date ?? DateTime.now().millisecondsSinceEpoch;
    _c = {
      'title': TextEditingController(text: e?.title ?? ''),
      'scripture': TextEditingController(text: e?.scripture ?? ''),
      'content': TextEditingController(text: e?.content ?? ''),
      'who': TextEditingController(text: e?.trinityWho ?? ''),
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
    final note = SermonNote(
      id: e?.id,
      date: _date,
      title: _c['title']!.text.trim(),
      scripture: _c['scripture']!.text.trim(),
      content: _c['content']!.text.trim(),
      trinityWho: _c['who']!.text.trim(),
      trinityWord: _c['trinityWord']!.text.trim(),
      practice: _c['practice']!.text.trim(),
      reflection: _c['reflection']!.text.trim(),
      createdAt: e?.createdAt ?? 0,
      updatedAt: 0,
    );
    await db.saveSermonNote(note);
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
    if (picked != null) {
      setState(() => _date = picked.millisecondsSinceEpoch);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? '新增證道筆記' : '編輯證道筆記'),
        actions: [
          if (widget.existing != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '刪除',
              onPressed: _delete,
            ),
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: '儲存',
            onPressed: _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: const Text('日期'),
            trailing: Text(_fmtDate(_date)),
            onTap: _pickDate,
          ),
          _field('title', '主題'),
          _field('scripture', '經文（例：約 3:16）'),
          _field('content', '筆記', maxLines: 6),
          const SizedBox(height: 12),
          Text('祂的話・分類（自填，可點下方快選）',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final w in _whoShortcuts)
                ActionChip(
                  label: Text(w),
                  onPressed: () => setState(() => _c['who']!.text = w),
                ),
            ],
          ),
          _field('who', '分類（例：神／聖子／聖靈／耶穌，或自訂）'),
          _field('trinityWord', '祂的話（內容）', maxLines: 3),
          _field('practice', '實踐', maxLines: 3),
          _field('reflection', '感想', maxLines: 3),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _field(String key, String label, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextField(
        controller: _c[key],
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          alignLabelWithHint: true,
        ),
      ),
    );
  }
}
