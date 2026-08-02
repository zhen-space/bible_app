import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';

/// 信仰生活代辦事項：分類 → 內容，**可打勾**（完成的畫線、排到分類底部）。
class TodosScreen extends ConsumerWidget {
  const TodosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todos = ref.watch(allTodosProvider).value ?? const <Todo>[];
    final scheme = Theme.of(context).colorScheme;

    // 分類 → 條目（DB 已依 done、分類、時間排序）
    final byCategory = <String, List<Todo>>{};
    for (final t in todos) {
      (byCategory[t.category.isEmpty ? '未分類' : t.category] ??= []).add(t);
    }
    final doneCount = todos.where((t) => t.done).length;

    return Scaffold(
      appBar: AppBar(title: const Text('信仰生活代辦')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('新增'),
        onPressed: () => _editTodo(context, ref, null),
      ),
      body: todos.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('還沒有代辦事項。\n點右下角新增，可自訂分類、完成後打勾。',
                    textAlign: TextAlign.center),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text('已完成 $doneCount / ${todos.length} 項',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
                for (final cat in byCategory.entries)
                  Card(
                    margin: const EdgeInsets.only(bottom: 14),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          color: scheme.primary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              const Icon(Icons.checklist,
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
                                  '${cat.value.where((t) => t.done).length}/${cat.value.length}',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                        for (final t in cat.value)
                          CheckboxListTile(
                            value: t.done,
                            onChanged: (v) async {
                              await ref
                                  .read(databaseServiceProvider)
                                  .saveTodo(t.copyWith(done: v ?? false));
                              ref.invalidate(allTodosProvider);
                            },
                            controlAffinity:
                                ListTileControlAffinity.leading,
                            title: Text(
                              t.content,
                              style: TextStyle(
                                height: 1.4,
                                decoration: t.done
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: t.done ? scheme.outline : null,
                              ),
                            ),
                            secondary: IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              tooltip: '編輯',
                              onPressed: () => _editTodo(context, ref, t),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// 新增／編輯代辦（底部表單）。
void _editTodo(BuildContext context, WidgetRef ref, Todo? existing) {
  final category = TextEditingController(text: existing?.category ?? '');
  final content = TextEditingController(text: existing?.content ?? '');
  final todos = ref.read(allTodosProvider).value ?? const <Todo>[];
  final cats = {
    for (final t in todos)
      if (t.category.isNotEmpty) t.category
  }.toList();

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(ctx).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(existing == null ? '新增代辦' : '編輯代辦',
              style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (cats.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              children: [
                for (final c in cats)
                  ActionChip(
                      label: Text(c), onPressed: () => category.text = c),
              ],
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: category,
            decoration: const InputDecoration(
              labelText: '分類（例：靈修、服事、關懷）',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: content,
            maxLines: 3,
            autofocus: existing == null,
            decoration: const InputDecoration(
              labelText: '要做的事',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (existing != null)
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      await ref
                          .read(databaseServiceProvider)
                          .deleteTodo(existing.id!);
                    } finally {
                      ref.invalidate(allTodosProvider);
                    }
                  },
                  child: const Text('刪除'),
                ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () async {
                  final text = content.text.trim();
                  Navigator.pop(ctx);
                  if (text.isEmpty) return;
                  try {
                    await ref.read(databaseServiceProvider).saveTodo(
                          Todo(
                            id: existing?.id,
                            category: category.text.trim(),
                            content: text,
                            done: existing?.done ?? false,
                            createdAt: existing?.createdAt ?? 0,
                            updatedAt: existing?.updatedAt ?? 0,
                          ),
                        );
                  } finally {
                    ref.invalidate(allTodosProvider);
                  }
                },
                child: const Text('儲存'),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
}
