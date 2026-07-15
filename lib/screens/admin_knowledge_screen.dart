import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/knowledge.dart';
import '../providers/providers.dart';
import '../services/download_stub.dart'
    if (dart.library.js_interop) '../services/download_web.dart';

/// 知識架構後台：編輯平行經文／預表應驗／時間軸／人物。
/// 存成雲端單一 doc（knowledge/data），讀經端雲端優先合併。
/// ⛔ 內容一律由管理者（使用者本人）撰寫。
class KnowledgeAdminScreen extends ConsumerWidget {
  const KnowledgeAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kb = ref.watch(knowledgeProvider).value ?? KnowledgeBase.empty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('知識架構編輯'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: '匯出 JSON（電腦大量編輯用）',
            onPressed: () => _export(context, kb),
          ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: '匯入 JSON（貼上後整份覆蓋）',
            onPressed: () => _import(context, ref, kb),
          ),
        ],
      ),
      body: ListView(
        children: [
          _tile(context, Icons.compare_arrows, '平行經文對照',
              '${kb.parallels.length} 組', const ParallelsEditor()),
          _tile(context, Icons.link, '預表與應驗',
              '${kb.types.length} 組', const TypesEditor()),
          _tile(context, Icons.timeline, '聖經時間軸',
              '${kb.timeline.length} 個事件', const TimelineEditor()),
          _tile(context, Icons.people_alt_outlined, '人物',
              '${kb.people.length} 位', const PeopleEditor()),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('提示：右上可整份匯出 JSON 到電腦編輯，再匯入貼回（覆蓋雲端）。'
                '格式同 assets/knowledge/knowledge.json。',
                style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  /// 匯出：下載 JSON 檔（網頁），並複製到剪貼簿（各平台都通）。
  Future<void> _export(BuildContext context, KnowledgeBase kb) async {
    final messenger = ScaffoldMessenger.of(context);
    final json = const JsonEncoder.withIndent('  ').convert(kb.toJson());
    await Clipboard.setData(ClipboardData(text: json));
    final downloaded =
        downloadTextFile('knowledge.json', 'application/json', json);
    messenger.showSnackBar(SnackBar(
        content: Text(downloaded
            ? '已下載 knowledge.json，並複製到剪貼簿'
            : '已複製 JSON 到剪貼簿')));
  }

  /// 匯入：貼上 JSON → 解析驗證 → 預覽筆數 → 確認後整份覆蓋雲端。
  void _import(BuildContext context, WidgetRef ref, KnowledgeBase current) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('匯入 JSON'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  '貼上整份 knowledge JSON。匯入會**覆蓋**雲端現有內容'
                  '（目前：平行 ${current.parallels.length}、預表 ${current.types.length}、'
                  '時間軸 ${current.timeline.length}、人物 ${current.people.length}）。',
                  style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLines: 10,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '{ "parallels": [...], "types": [...], ... }',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final KnowledgeBase kb;
              try {
                kb = KnowledgeBase.fromJson(
                    jsonDecode(controller.text) as Map<String, dynamic>);
              } catch (e) {
                messenger.showSnackBar(
                    SnackBar(content: Text('JSON 解析失敗：$e')));
                return;
              }
              Navigator.pop(ctx);
              try {
                await _saveKb(ref, kb);
                messenger.showSnackBar(SnackBar(
                    content: Text('已匯入：平行 ${kb.parallels.length}、'
                        '預表 ${kb.types.length}、時間軸 ${kb.timeline.length}、'
                        '人物 ${kb.people.length}')));
              } catch (e) {
                messenger
                    .showSnackBar(SnackBar(content: Text('匯入失敗：$e')));
              }
            },
            child: const Text('覆蓋匯入'),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext c, IconData icon, String title, String sub,
          Widget screen) =>
      ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(sub),
        trailing: const Icon(Icons.chevron_right),
        onTap: () =>
            Navigator.push(c, MaterialPageRoute(builder: (_) => screen)),
      );
}

/// 存回雲端整份知識資料並刷新。
Future<void> _saveKb(WidgetRef ref, KnowledgeBase kb) async {
  await ref.read(contentServiceProvider).saveKnowledge(kb.toJson());
  ref.invalidate(cloudKnowledgeProvider);
}

List<String> _splitCommas(String s) => s
    .split(RegExp(r'[,，、]'))
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();

// ---------------- 平行經文對照 ----------------

class ParallelsEditor extends ConsumerWidget {
  const ParallelsEditor({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kb = ref.watch(knowledgeProvider).value ?? KnowledgeBase.empty;
    return Scaffold(
      appBar: AppBar(title: const Text('平行經文對照')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context, ref, kb, null),
        child: const Icon(Icons.add),
      ),
      body: kb.parallels.isEmpty
          ? const Center(child: Text('還沒有內容，點右下角新增'))
          : ListView(
              children: [
                for (var i = 0; i < kb.parallels.length; i++)
                  ListTile(
                    title: Text(kb.parallels[i].title.isEmpty
                        ? '（無標題）'
                        : kb.parallels[i].title),
                    subtitle: Text(kb.parallels[i].refs.join('　')),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _remove(ref, kb, i),
                    ),
                    onTap: () => _edit(context, ref, kb, i),
                  ),
              ],
            ),
    );
  }

  Future<void> _remove(WidgetRef ref, KnowledgeBase kb, int i) async {
    final list = [...kb.parallels]..removeAt(i);
    await _saveKb(ref, kb.copyWith(parallels: list));
  }

  void _edit(BuildContext context, WidgetRef ref, KnowledgeBase kb, int? i) {
    final existing = i == null ? null : kb.parallels[i];
    final title = TextEditingController(text: existing?.title ?? '');
    final refs = TextEditingController(text: existing?.refs.join(', ') ?? '');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(i == null ? '新增平行經文' : '編輯'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: '標題')),
              TextField(
                  controller: refs,
                  decoration: const InputDecoration(
                      labelText: '經文（逗號分隔，例：太8:23-27, 可4:35-41）')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final item = ParallelPassage(
                  title: title.text.trim(), refs: _splitCommas(refs.text));
              final list = [...kb.parallels];
              i == null ? list.add(item) : list[i] = item;
              Navigator.pop(ctx);
              await _saveKb(ref, kb.copyWith(parallels: list));
            },
            child: const Text('儲存'),
          ),
        ],
      ),
    );
  }
}

// ---------------- 預表與應驗 ----------------

class TypesEditor extends ConsumerWidget {
  const TypesEditor({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kb = ref.watch(knowledgeProvider).value ?? KnowledgeBase.empty;
    return Scaffold(
      appBar: AppBar(title: const Text('預表與應驗')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context, ref, kb, null),
        child: const Icon(Icons.add),
      ),
      body: kb.types.isEmpty
          ? const Center(child: Text('還沒有內容，點右下角新增'))
          : ListView(
              children: [
                for (var i = 0; i < kb.types.length; i++)
                  ListTile(
                    title: Text(kb.types[i].title.isEmpty
                        ? '（無標題）'
                        : kb.types[i].title),
                    subtitle: Text('${kb.types[i].otRef} → ${kb.types[i].ntRef}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final list = [...kb.types]..removeAt(i);
                        await _saveKb(ref, kb.copyWith(types: list));
                      },
                    ),
                    onTap: () => _edit(context, ref, kb, i),
                  ),
              ],
            ),
    );
  }

  void _edit(BuildContext context, WidgetRef ref, KnowledgeBase kb, int? i) {
    final existing = i == null ? null : kb.types[i];
    final title = TextEditingController(text: existing?.title ?? '');
    final ot = TextEditingController(text: existing?.otRef ?? '');
    final nt = TextEditingController(text: existing?.ntRef ?? '');
    final note = TextEditingController(text: existing?.note ?? '');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(i == null ? '新增預表／應驗' : '編輯'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: '標題')),
              TextField(
                  controller: ot,
                  decoration: const InputDecoration(
                      labelText: '舊約預表經文（例：創22:8）')),
              TextField(
                  controller: nt,
                  decoration: const InputDecoration(
                      labelText: '新約應驗經文（例：約1:29）')),
              TextField(
                  controller: note,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '說明')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final item = TypeFulfillment(
                title: title.text.trim(),
                otRef: ot.text.trim(),
                ntRef: nt.text.trim(),
                note: note.text.trim(),
              );
              final list = [...kb.types];
              i == null ? list.add(item) : list[i] = item;
              Navigator.pop(ctx);
              await _saveKb(ref, kb.copyWith(types: list));
            },
            child: const Text('儲存'),
          ),
        ],
      ),
    );
  }
}

// ---------------- 時間軸 ----------------

class TimelineEditor extends ConsumerWidget {
  const TimelineEditor({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kb = ref.watch(knowledgeProvider).value ?? KnowledgeBase.empty;
    return Scaffold(
      appBar: AppBar(title: const Text('聖經時間軸')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context, ref, kb, null),
        child: const Icon(Icons.add),
      ),
      body: kb.timeline.isEmpty
          ? const Center(child: Text('還沒有內容，點右下角新增'))
          : ListView(
              children: [
                for (var i = 0; i < kb.timeline.length; i++)
                  ListTile(
                    leading: Text('${kb.timeline[i].order}'),
                    title: Text(kb.timeline[i].title),
                    subtitle: Text(
                        '${kb.timeline[i].era}　${kb.timeline[i].when}　${kb.timeline[i].ref}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final list = [...kb.timeline]..removeAt(i);
                        await _saveKb(ref, kb.copyWith(timeline: list));
                      },
                    ),
                    onTap: () => _edit(context, ref, kb, i),
                  ),
              ],
            ),
    );
  }

  void _edit(BuildContext context, WidgetRef ref, KnowledgeBase kb, int? i) {
    final existing = i == null ? null : kb.timeline[i];
    final order =
        TextEditingController(text: existing?.order.toString() ?? '');
    final era = TextEditingController(text: existing?.era ?? '');
    final title = TextEditingController(text: existing?.title ?? '');
    final when = TextEditingController(text: existing?.when ?? '');
    final refC = TextEditingController(text: existing?.ref ?? '');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(i == null ? '新增事件' : '編輯'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: order,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: '排序（數字，小的在前）')),
              TextField(
                  controller: era,
                  decoration:
                      const InputDecoration(labelText: '分期（例：族長時期）')),
              TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: '事件')),
              TextField(
                  controller: when,
                  decoration: const InputDecoration(
                      labelText: '年代（文字，例：約主前 2000 年）')),
              TextField(
                  controller: refC,
                  decoration: const InputDecoration(labelText: '相關經文')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final item = TimelineEvent(
                order: int.tryParse(order.text.trim()) ?? 0,
                era: era.text.trim(),
                title: title.text.trim(),
                when: when.text.trim(),
                ref: refC.text.trim(),
              );
              final list = [...kb.timeline];
              i == null ? list.add(item) : list[i] = item;
              Navigator.pop(ctx);
              await _saveKb(ref, kb.copyWith(timeline: list));
            },
            child: const Text('儲存'),
          ),
        ],
      ),
    );
  }
}

// ---------------- 人物 ----------------

class PeopleEditor extends ConsumerWidget {
  const PeopleEditor({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kb = ref.watch(knowledgeProvider).value ?? KnowledgeBase.empty;
    return Scaffold(
      appBar: AppBar(title: const Text('人物')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context, ref, kb, null),
        child: const Icon(Icons.add),
      ),
      body: kb.people.isEmpty
          ? const Center(child: Text('還沒有內容，點右下角新增'))
          : ListView(
              children: [
                for (var i = 0; i < kb.people.length; i++)
                  ListTile(
                    title: Text(kb.people[i].name),
                    subtitle: Text('id：${kb.people[i].id}　'
                        '事件 ${kb.people[i].events.length}・關係 ${kb.people[i].relations.length}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final list = [...kb.people]..removeAt(i);
                        await _saveKb(ref, kb.copyWith(people: list));
                      },
                    ),
                    onTap: () => _edit(context, ref, kb, i),
                  ),
              ],
            ),
    );
  }

  void _edit(BuildContext context, WidgetRef ref, KnowledgeBase kb, int? i) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PersonEditForm(
            kb: kb, index: i, existing: i == null ? null : kb.people[i]),
      ),
    );
  }
}

/// 人物編輯表單（欄位多，用整頁）。事件、關係用每行一筆的文字格式。
class PersonEditForm extends ConsumerStatefulWidget {
  final KnowledgeBase kb;
  final int? index;
  final Person? existing;

  const PersonEditForm(
      {super.key, required this.kb, required this.index, this.existing});

  @override
  ConsumerState<PersonEditForm> createState() => _PersonEditFormState();
}

class _PersonEditFormState extends ConsumerState<PersonEditForm> {
  late final TextEditingController _id;
  late final TextEditingController _name;
  late final TextEditingController _aka;
  late final TextEditingController _bio;
  late final TextEditingController _events;
  late final TextEditingController _relations;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _id = TextEditingController(text: p?.id ?? '');
    _name = TextEditingController(text: p?.name ?? '');
    _aka = TextEditingController(text: p?.aka.join(', ') ?? '');
    _bio = TextEditingController(text: p?.bio ?? '');
    _events = TextEditingController(
        text: (p?.events ?? [])
            .map((e) => '${e.title}｜${e.ref}')
            .join('\n'));
    _relations = TextEditingController(
        text: (p?.relations ?? [])
            .map((r) => '${r.type}｜${r.personId}｜${r.name}')
            .join('\n'));
  }

  @override
  void dispose() {
    for (final c in [_id, _name, _aka, _bio, _events, _relations]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.index == null ? '新增人物' : '編輯人物')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
              controller: _id,
              decoration: const InputDecoration(
                  labelText: 'id（英文，唯一，關係用來指向此人，例：abraham）',
                  border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: '姓名', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(
              controller: _aka,
              decoration: const InputDecoration(
                  labelText: '別名（逗號分隔）', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(
              controller: _bio,
              maxLines: 5,
              decoration: const InputDecoration(
                  labelText: '生平簡介',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true)),
          const SizedBox(height: 12),
          TextField(
              controller: _events,
              maxLines: 5,
              decoration: const InputDecoration(
                  labelText: '重大事件（每行一筆，格式：事件｜經文）',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true)),
          const SizedBox(height: 12),
          TextField(
              controller: _relations,
              maxLines: 5,
              decoration: const InputDecoration(
                  labelText: '關係（每行一筆，格式：關係｜對方id｜對方名，例：子｜isaac｜以撒）',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true)),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.cloud_upload),
            label: const Text('儲存並發布'),
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final events = _events.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((l) {
      final parts = l.split(RegExp(r'[｜|]'));
      return PersonEvent(
          title: parts[0].trim(),
          ref: parts.length > 1 ? parts[1].trim() : '');
    }).toList();
    final relations = _relations.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((l) {
      final parts = l.split(RegExp(r'[｜|]'));
      return PersonRelation(
        type: parts[0].trim(),
        personId: parts.length > 1 ? parts[1].trim() : '',
        name: parts.length > 2 ? parts[2].trim() : '',
      );
    }).toList();
    final person = Person(
      id: _id.text.trim(),
      name: _name.text.trim(),
      aka: _splitCommas(_aka.text),
      bio: _bio.text.trim(),
      events: events,
      relations: relations,
    );
    final list = [...widget.kb.people];
    widget.index == null ? list.add(person) : list[widget.index!] = person;
    final m = ScaffoldMessenger.of(context);
    try {
      await _save2(list);
      m.showSnackBar(const SnackBar(content: Text('已儲存並發布')));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text('儲存失敗：$e')));
    }
  }

  Future<void> _save2(List<Person> people) =>
      _saveKb(ref, widget.kb.copyWith(people: people));
}
