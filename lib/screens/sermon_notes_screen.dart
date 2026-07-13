import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';

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
      appBar: AppBar(title: const Text('主日・證道筆記')),
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
  late String _who;

  static const _whoOptions = ['', '神', '聖子', '聖靈', '耶穌'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = e?.date ?? DateTime.now().millisecondsSinceEpoch;
    _who = e?.trinityWho ?? '';
    _c = {
      'title': TextEditingController(text: e?.title ?? ''),
      'scripture': TextEditingController(text: e?.scripture ?? ''),
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
    final note = SermonNote(
      id: e?.id,
      date: _date,
      title: _c['title']!.text.trim(),
      scripture: _c['scripture']!.text.trim(),
      content: _c['content']!.text.trim(),
      trinityWho: _who,
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
          const SizedBox(height: 8),
          Text('神／聖子／聖靈／耶穌的話',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              for (final w in _whoOptions)
                ChoiceChip(
                  label: Text(w.isEmpty ? '未選' : w),
                  selected: _who == w,
                  onSelected: (_) => setState(() => _who = w),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _field('trinityWord', '祂的話', maxLines: 3),
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
