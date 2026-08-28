import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';

/// 禱告事項：分類 → 子分類 → 內容。使用者自行新增/編輯/刪除，
/// **不設打勾**（禱告不是待辦清單）。
class PrayersScreen extends ConsumerWidget {
  const PrayersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prayers = ref.watch(allPrayersProvider).value ?? const <Prayer>[];
    final scheme = Theme.of(context).colorScheme;

    // 分類 → 子分類 → 條目（保留 DB 排序：分類、子分類、新到舊）
    final byCategory = <String, Map<String, List<Prayer>>>{};
    for (final p in prayers) {
      final cat = p.category.isEmpty ? '未分類' : p.category;
      final sub = p.subcategory;
      ((byCategory[cat] ??= {})[sub] ??= []).add(p);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('禱告事項')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('新增'),
        onPressed: () => showPrayerEditor(context, ref, null),
      ),
      body: prayers.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('還沒有禱告事項。\n點右下角新增，可自訂分類與子分類。',
                    textAlign: TextAlign.center),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              children: [
                // 每個「分類」＝一張獨立卡片；子分類、內容在卡內縮排巢狀
                for (final cat in byCategory.entries)
                  Card(
                    margin: const EdgeInsets.only(bottom: 14),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 分類標題條（實心底色，最顯眼那層）
                        Container(
                          color: scheme.primary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              const Icon(Icons.folder_outlined,
                                  size: 18, color: Colors.white),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(cat.key,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16)),
                              ),
                              Text(
                                  '${cat.value.values.fold<int>(0, (a, b) => a + b.length)} 則',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                        // 子分類 + 內容
                        for (final sub in cat.value.entries)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (sub.key.isNotEmpty)
                                Container(
                                  width: double.infinity,
                                  color: scheme.primary.withValues(alpha: 0.08),
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 6, 16, 6),
                                  child: Row(
                                    children: [
                                      Icon(Icons.subdirectory_arrow_right,
                                          size: 16, color: scheme.secondary),
                                      const SizedBox(width: 6),
                                      Text(sub.key,
                                          style: TextStyle(
                                              color: scheme.secondary,
                                              fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                              for (final p in sub.value)
                                InkWell(
                                  onTap: () =>
                                      showPrayerEditor(context, ref, p),
                                  child: Padding(
                                    // 有子分類→再縮排；沒有→只縮一層
                                    padding: EdgeInsets.fromLTRB(
                                        sub.key.isNotEmpty ? 34 : 16,
                                        10,
                                        16,
                                        10),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 6),
                                          child: Icon(Icons.circle,
                                              size: 6,
                                              color: scheme.secondary),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (p.title.isNotEmpty)
                                                Text(p.title,
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600)),
                                              Text(p.content,
                                                  style: const TextStyle(
                                                      height: 1.5)),
                                            ],
                                          ),
                                        ),
                                        if (p.status != PrayerStatus.praying)
                                          _statusChip(context, p.status),
                                      ],
                                    ),
                                  ),
                                ),
                              const Divider(height: 1),
                            ],
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

Widget _statusChip(BuildContext context, PrayerStatus s) {
  final scheme = Theme.of(context).colorScheme;
  final color = s == PrayerStatus.answered ? scheme.primary : scheme.outline;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(s.label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w700)),
  );
}

String _ymd(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.year}/${d.month.toString().padLeft(2, '0')}/'
      '${d.day.toString().padLeft(2, '0')}';
}

/// 新增／編輯禱告事項（底部表單，v2）。[existing] 為 null 表示新增。
void showPrayerEditor(BuildContext context, WidgetRef ref, Prayer? existing) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _PrayerEditorSheet(existing: existing, parentRef: ref),
  );
}

class _PrayerEditorSheet extends StatefulWidget {
  final Prayer? existing;
  final WidgetRef parentRef;
  const _PrayerEditorSheet({required this.existing, required this.parentRef});

  @override
  State<_PrayerEditorSheet> createState() => _PrayerEditorSheetState();
}

class _PrayerEditorSheetState extends State<_PrayerEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _category;
  late final TextEditingController _subcategory;
  late final TextEditingController _content;
  late final TextEditingController _reflection;
  late PrayerStatus _status;
  late int _prayerDate;
  late int _reminderAt;
  late int _answeredAt;

  WidgetRef get ref => widget.parentRef;
  Prayer? get existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final e = existing;
    _title = TextEditingController(text: e?.title ?? '');
    _category = TextEditingController(text: e?.category ?? '');
    _subcategory = TextEditingController(text: e?.subcategory ?? '');
    _content = TextEditingController(text: e?.content ?? '');
    _reflection = TextEditingController(text: e?.answeredReflection ?? '');
    _status = e?.status ?? PrayerStatus.praying;
    _prayerDate = e?.prayerDate ?? 0;
    _reminderAt = e?.reminderAt ?? 0;
    _answeredAt = e?.answeredAt ?? 0;
  }

  @override
  void dispose() {
    for (final c in [_title, _category, _subcategory, _content, _reflection]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<int> _pickDate(int current) async {
    final now = DateTime.now();
    final init =
        current > 0 ? DateTime.fromMillisecondsSinceEpoch(current) : now;
    final d = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    return d?.millisecondsSinceEpoch ?? current;
  }

  @override
  Widget build(BuildContext context) {
    final prayers = ref.read(allPrayersProvider).value ?? const <Prayer>[];
    final cats = {
      for (final p in prayers)
        if (p.category.isNotEmpty) p.category
    }.toList();
    final answered = _status != PrayerStatus.praying;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 12,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(existing == null ? '新增禱告事項' : '編輯禱告事項',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          // 狀態
          SegmentedButton<PrayerStatus>(
            segments: const [
              ButtonSegment(
                  value: PrayerStatus.praying, label: Text('禱告中')),
              ButtonSegment(
                  value: PrayerStatus.answered, label: Text('已蒙應允')),
              ButtonSegment(value: PrayerStatus.ended, label: Text('已結束')),
            ],
            selected: {_status},
            onSelectionChanged: (s) => setState(() {
              _status = s.first;
              if (_status != PrayerStatus.praying && _answeredAt == 0) {
                _answeredAt = DateTime.now().millisecondsSinceEpoch;
              }
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
                labelText: '標題（可空）', border: OutlineInputBorder(), isDense: true),
          ),
          const SizedBox(height: 8),
          if (cats.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              children: [
                for (final c in cats)
                  ActionChip(
                      label: Text(c),
                      onPressed: () => setState(() => _category.text = c)),
              ],
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: _category,
            decoration: const InputDecoration(
                labelText: '分類（例：家人、教會、宣教）',
                border: OutlineInputBorder(),
                isDense: true),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _subcategory,
            decoration: const InputDecoration(
                labelText: '子分類（可空，例：爸爸）',
                border: OutlineInputBorder(),
                isDense: true),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _content,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: '禱告內容',
                border: OutlineInputBorder(),
                alignLabelWithHint: true),
          ),
          const SizedBox(height: 8),
          // 禱告日期
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: const Text('禱告日期'),
            subtitle: Text(_prayerDate > 0 ? _ymd(_prayerDate) : '未設定'),
            trailing: _prayerDate > 0
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _prayerDate = 0),
                  )
                : null,
            onTap: () async {
              final v = await _pickDate(_prayerDate);
              setState(() => _prayerDate = v);
            },
          ),
          // 提醒（僅儲存時間；實際推播需 FCM/本地通知，尚未接）
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.alarm),
            title: const Text('提醒（儲存時間）'),
            subtitle: Text(_reminderAt > 0 ? _ymd(_reminderAt) : '未設定'),
            trailing: _reminderAt > 0
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _reminderAt = 0),
                  )
                : null,
            onTap: () async {
              final v = await _pickDate(_reminderAt);
              setState(() => _reminderAt = v);
            },
          ),
          if (answered) ...[
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.check_circle_outline),
              title: Text(_status == PrayerStatus.answered
                  ? '蒙應允日期'
                  : '結束日期'),
              subtitle: Text(_answeredAt > 0 ? _ymd(_answeredAt) : '未設定'),
              onTap: () async {
                final v = await _pickDate(
                    _answeredAt > 0 ? _answeredAt : DateTime.now().millisecondsSinceEpoch);
                setState(() => _answeredAt = v);
              },
            ),
            TextField(
              controller: _reflection,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: '應允後回顧（可空）',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (existing != null)
                TextButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    try {
                      await ref
                          .read(databaseServiceProvider)
                          .deletePrayer(existing!.id!);
                    } finally {
                      ref.invalidate(allPrayersProvider);
                    }
                  },
                  child: const Text('刪除'),
                ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () async {
                  final text = _content.text.trim();
                  final title = _title.text.trim();
                  Navigator.pop(context);
                  if (text.isEmpty && title.isEmpty) return;
                  try {
                    await ref.read(databaseServiceProvider).savePrayer(
                          Prayer(
                            id: existing?.id,
                            category: _category.text.trim(),
                            subcategory: _subcategory.text.trim(),
                            title: title,
                            content: text,
                            prayerDate: _prayerDate,
                            refs: existing?.refs ?? const [],
                            status: _status,
                            reminderAt: _reminderAt,
                            answeredAt: answered ? _answeredAt : 0,
                            answeredReflection:
                                answered ? _reflection.text.trim() : '',
                            createdAt: existing?.createdAt ?? 0,
                            updatedAt: existing?.updatedAt ?? 0,
                          ),
                        );
                  } finally {
                    ref.invalidate(allPrayersProvider);
                  }
                },
                child: const Text('儲存'),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
