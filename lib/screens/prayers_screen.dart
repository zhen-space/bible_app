import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../utils/prayer_list_presentation.dart';
import '../widgets/scripture_reference_field.dart';
import '../widgets/student_ux.dart';

class PrayersScreen extends ConsumerStatefulWidget {
  const PrayersScreen({super.key});

  @override
  ConsumerState<PrayersScreen> createState() => _PrayersScreenState();
}

class _PrayersScreenState extends ConsumerState<PrayersScreen> {
  static const _filterPreferenceKey = 'prayers_list_filter';
  final SelectionController<int> _selection = SelectionController<int>();
  PrayerListFilter _filter = PrayerListFilter.praying;

  @override
  void initState() {
    super.initState();
    _selection.addListener(_changed);
    _loadFilter();
  }

  Future<void> _loadFilter() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(
      () => _filter = decodePrayerListFilter(
        prefs.getString(_filterPreferenceKey),
      ),
    );
  }

  Future<void> _changeFilter(PrayerListFilter filter) async {
    _selection.cancel();
    setState(() => _filter = filter);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_filterPreferenceKey, filter.name);
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

  Future<void> _setStatus(Iterable<Prayer> prayers, PrayerStatus status) async {
    final changed = prayers.where((prayer) => prayer.status != status).toList();
    if (changed.isEmpty) return;
    final db = ref.read(databaseServiceProvider);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final prayer in changed) {
      await db.savePrayer(
        prayer.copyWith(
          status: status,
          answeredAt: status == PrayerStatus.praying
              ? 0
              : (prayer.answeredAt == 0 ? now : prayer.answeredAt),
        ),
      );
    }
    _selection.cancel();
    ref.invalidate(allPrayersProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            changed.length == 1
                ? '已更新為「${status.label}」'
                : '已更新 ${changed.length} 則禱告事項',
          ),
          action: SnackBarAction(
            label: '復原',
            onPressed: () async {
              for (final prayer in changed) {
                await db.savePrayer(prayer);
              }
              ref.invalidate(allPrayersProvider);
            },
          ),
        ),
      );
  }

  Future<void> _delete(Iterable<Prayer> prayers) async {
    final list = prayers.where((p) => p.id != null).toList();
    if (list.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          list.length == 1 ? '刪除這則禱告事項？' : '刪除 ${list.length} 則禱告事項？',
        ),
        content: const Text('刪除會沿用現有同步刪除紀錄。'),
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
    if (ok != true) return;
    final db = ref.read(databaseServiceProvider);
    for (final prayer in list) {
      await db.deletePrayer(prayer.id!);
    }
    _selection.cancel();
    ref.invalidate(allPrayersProvider);
  }

  String _copyPrayer(Prayer prayer, List<Book>? books) {
    String refLabel(String raw) {
      if (books == null) return raw;
      return parseLegacyScriptureRef(raw, books)?.label(books) ?? raw;
    }

    final out = <String>[];
    if (prayer.title.trim().isNotEmpty) out.add(prayer.title.trim());
    if (prayer.content.trim().isNotEmpty) out.add(prayer.content.trim());
    if (prayer.refs.isNotEmpty) {
      out.add('對應經文：${prayer.refs.map(refLabel).join('、')}');
    }
    if (prayer.category.trim().isNotEmpty) {
      out.add(
        '分類：${prayer.category.trim()}${prayer.subcategory.trim().isEmpty ? '' : ' · ${prayer.subcategory.trim()}'}',
      );
    }
    if (prayer.status != PrayerStatus.praying) {
      out.add('狀態：${prayer.status.label}');
    }
    return out.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(allPrayersProvider);
    final prayers = async.value ?? const <Prayer>[];
    final visiblePrayers = filterPrayersForList(prayers, _filter);
    final books = ref.watch(booksProvider).value;
    final ids = visiblePrayers
        .where((p) => p.id != null)
        .map((p) => p.id!)
        .toList();
    final selected = visiblePrayers
        .where((p) => p.id != null && _selection.contains(p.id!))
        .toList();

    return Scaffold(
      appBar: _selection.active
          ? StudentSelectionAppBar(
              title: '禱告事項',
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
              title: const Text('禱告事項'),
              actions: [
                if (prayers.isNotEmpty)
                  TextButton(
                    onPressed: _selection.start,
                    child: const Text('選取'),
                  ),
              ],
            ),
      floatingActionButton: _selection.active
          ? null
          : FloatingActionButton(
              tooltip: '新增禱告事項',
              onPressed: () => showPrayerEditor(context, ref, null),
              child: const Icon(Icons.add),
            ),
      bottomNavigationBar: _selection.active
          ? StudentBatchActionBar(
              actions: [
                StudentBatchAction(
                  label: '複製',
                  icon: Icons.copy_outlined,
                  onPressed: selected.isEmpty
                      ? null
                      : () => copyHumanReadable(
                          context,
                          joinHumanReadable(
                            selected.map((p) => _copyPrayer(p, books)),
                          ),
                          success: '已複製 ${selected.length} 則禱告事項',
                        ),
                ),
                StudentBatchAction(
                  label: '已蒙應允',
                  icon: Icons.check_circle_outline,
                  onPressed: selected.isEmpty
                      ? null
                      : () => _setStatus(selected, PrayerStatus.answered),
                ),
                StudentBatchAction(
                  label: '已結束',
                  icon: Icons.stop_circle_outlined,
                  onPressed: selected.isEmpty
                      ? null
                      : () => _setStatus(selected, PrayerStatus.ended),
                ),
                StudentBatchAction(
                  label: '刪除',
                  icon: Icons.delete_outline,
                  destructive: true,
                  onPressed: selected.isEmpty ? null : () => _delete(selected),
                ),
              ],
            )
          : null,
      body: async.when(
        loading: () => const StudentCompactLoading(),
        error: (_, _) => StudentErrorState(
          onRetry: () => ref.invalidate(allPrayersProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return StudentEmptyState(
              title: '還沒有禱告事項',
              subtitle: '把正在禱告的事情整理在這裡。',
              icon: Icons.volunteer_activism_outlined,
              actionLabel: '新增禱告事項',
              onAction: () => showPrayerEditor(context, ref, null),
            );
          }
          final visible = filterPrayersForList(list, _filter);
          String? lastCategory;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    for (final filter in PrayerListFilter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(_prayerFilterLabel(filter, list)),
                          selected: _filter == filter,
                          onSelected: (_) => _changeFilter(filter),
                        ),
                      ),
                  ],
                ),
              ),
              if (visible.isEmpty)
                Expanded(
                  child: StudentEmptyState(
                    title: _prayerFilterEmptyTitle(_filter),
                    subtitle: '可切換其他狀態查看禱告事項。',
                    icon: Icons.volunteer_activism_outlined,
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final p = visible[index];
                      final id = p.id!;
                      final category = p.category.isEmpty ? '未分類' : p.category;
                      final showHeader = category != lastCategory;
                      lastCategory = category;
                      final row = ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 5,
                        ),
                        leading: _selection.active
                            ? Checkbox(
                                value: _selection.contains(id),
                                onChanged: (_) => _selection.toggle(id),
                              )
                            : null,
                        title: Text(
                          p.title.isNotEmpty
                              ? p.title
                              : (p.content.isEmpty ? '禱告事項' : p.content),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                            if (p.title.isNotEmpty && p.content.isNotEmpty)
                              p.content,
                            if (p.subcategory.isNotEmpty) p.subcategory,
                          ].where((e) => e.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: p.status == PrayerStatus.praying
                            ? null
                            : _statusChip(context, p.status),
                        onLongPress: () => _selection.start(id),
                        onTap: _selection.active
                            ? () => _selection.toggle(id)
                            : () => showPrayerEditor(context, ref, p),
                      );
                      final swipe = _selection.active
                          ? row
                          : StudentSwipeRow(
                              dismissKey: ValueKey('prayer_$id'),
                              startLabel: '複製',
                              startIcon: Icons.copy_outlined,
                              endLabel: '刪除',
                              onSwipeStartToEnd: () => copyHumanReadable(
                                context,
                                _copyPrayer(p, books),
                              ),
                              onSwipeEndToStart: () => _delete([p]),
                              child: row,
                            );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showHeader)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 18, 20, 5),
                              child: Text(
                                category,
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          swipe,
                          const Divider(height: 1, indent: 20),
                        ],
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

String _prayerFilterLabel(PrayerListFilter filter, List<Prayer> prayers) {
  final count = filterPrayersForList(prayers, filter).length;
  return switch (filter) {
    PrayerListFilter.praying => '禱告中 $count',
    PrayerListFilter.all => '全部 $count',
    PrayerListFilter.answered => '已蒙應允 $count',
    PrayerListFilter.ended => '已結束 $count',
  };
}

String _prayerFilterEmptyTitle(PrayerListFilter filter) => switch (filter) {
  PrayerListFilter.praying => '目前沒有禱告中的事項',
  PrayerListFilter.all => '還沒有禱告事項',
  PrayerListFilter.answered => '還沒有已蒙應允的事項',
  PrayerListFilter.ended => '還沒有已結束的事項',
};

Widget _statusChip(BuildContext context, PrayerStatus s) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      s.label,
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: scheme.outline),
    ),
  );
}

String _ymd(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}

void showPrayerEditor(BuildContext context, WidgetRef ref, Prayer? existing) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => _PrayerEditorSheet(existing: existing, parentRef: ref),
  );
}

class _PrayerEditorSheet extends StatefulWidget {
  const _PrayerEditorSheet({required this.existing, required this.parentRef});
  final Prayer? existing;
  final WidgetRef parentRef;

  @override
  State<_PrayerEditorSheet> createState() => _PrayerEditorSheetState();
}

class _PrayerEditorSheetState extends State<_PrayerEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _category;
  late final TextEditingController _subcategory;
  late final TextEditingController _content;
  late final TextEditingController _reflection;
  late List<String> _refs;
  late PrayerStatus _status;
  late int _prayerDate;
  late int _reminderAt;
  late int _answeredAt;
  String? _validationError;

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
    _refs = List<String>.of(e?.refs ?? const []);
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
    final init = current > 0
        ? DateTime.fromMillisecondsSinceEpoch(current)
        : now;
    final d = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    return d?.millisecondsSinceEpoch ?? current;
  }

  void _clearValidation() {
    if (_validationError != null) setState(() => _validationError = null);
  }

  @override
  Widget build(BuildContext context) {
    final answered = _status != PrayerStatus.praying;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(
            existing == null ? '新增禱告事項' : '編輯禱告事項',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 18),
          SegmentedButton<PrayerStatus>(
            segments: const [
              ButtonSegment(value: PrayerStatus.praying, label: Text('禱告中')),
              ButtonSegment(value: PrayerStatus.answered, label: Text('已蒙應允')),
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
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            onChanged: (_) => _clearValidation(),
            decoration: const InputDecoration(labelText: '標題'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _content,
            onChanged: (_) => _clearValidation(),
            maxLines: 4,
            decoration: const InputDecoration(labelText: '禱告內容'),
          ),
          const SizedBox(height: 16),
          ScriptureReferenceField(
            values: _refs,
            onChanged: (values) => setState(() {
              _refs = values;
              _validationError = null;
            }),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _category,
                  decoration: const InputDecoration(labelText: '分類'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _subcategory,
                  decoration: const InputDecoration(labelText: '子分類'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: const Text('禱告日期'),
            subtitle: Text(_prayerDate > 0 ? _ymd(_prayerDate) : '未設定'),
            onTap: () async {
              final value = await _pickDate(_prayerDate);
              if (mounted) setState(() => _prayerDate = value);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.alarm_outlined),
            title: const Text('提醒'),
            subtitle: Text(_reminderAt > 0 ? _ymd(_reminderAt) : '未設定'),
            onTap: () async {
              final value = await _pickDate(_reminderAt);
              if (mounted) setState(() => _reminderAt = value);
            },
          ),
          if (answered) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _reflection,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '應允後回顧'),
            ),
          ],
          if (_validationError != null) ...[
            const SizedBox(height: 12),
            Text(
              _validationError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () async {
              final text = _content.text.trim();
              final title = _title.text.trim();
              if (text.isEmpty && title.isEmpty && _refs.isEmpty) {
                setState(() => _validationError = '請填寫標題、禱告內容或至少一處對應經文');
                return;
              }
              Navigator.pop(context);
              await ref
                  .read(databaseServiceProvider)
                  .savePrayer(
                    Prayer(
                      id: existing?.id,
                      category: _category.text.trim(),
                      subcategory: _subcategory.text.trim(),
                      title: title,
                      content: text,
                      prayerDate: _prayerDate,
                      refs: _refs,
                      status: _status,
                      reminderAt: _reminderAt,
                      answeredAt: answered ? _answeredAt : 0,
                      answeredReflection: answered
                          ? _reflection.text.trim()
                          : '',
                      createdAt: existing?.createdAt ?? 0,
                      updatedAt: existing?.updatedAt ?? 0,
                    ),
                  );
              ref.invalidate(allPrayersProvider);
            },
            child: const Text('儲存'),
          ),
        ],
      ),
    );
  }
}
