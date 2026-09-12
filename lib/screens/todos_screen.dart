import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../widgets/student_ux.dart';

class TodosScreen extends ConsumerStatefulWidget {
  const TodosScreen({super.key});

  @override
  ConsumerState<TodosScreen> createState() => _TodosScreenState();
}

class _TodosScreenState extends ConsumerState<TodosScreen> {
  final SelectionController<int> _selection = SelectionController<int>();

  @override
  void initState() {
    super.initState();
    _selection.addListener(_changed);
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

  Future<void> _refresh() async => ref.invalidate(allTodosProvider);

  Future<void> _setDone(Iterable<Todo> todos, bool done) async {
    final db = ref.read(databaseServiceProvider);
    for (final todo in todos) {
      await db.saveTodo(todo.copyWith(done: done));
    }
    _selection.cancel();
    await _refresh();
  }

  Future<void> _delete(Iterable<Todo> todos) async {
    final list = todos.where((t) => t.id != null).toList();
    if (list.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(list.length == 1 ? '刪除這項代辦？' : '刪除 ${list.length} 項代辦？'),
        content: const Text('會沿用既有刪除與同步紀錄，不會由滑動手勢直接做永久刪除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('刪除')),
        ],
      ),
    );
    if (ok != true) return;
    final db = ref.read(databaseServiceProvider);
    for (final todo in list) {
      await db.deleteTodo(todo.id!);
    }
    _selection.cancel();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(allTodosProvider);
    final todos = async.value ?? const <Todo>[];
    final selectedTodos = todos
        .where((t) => t.id != null && _selection.contains(t.id!))
        .toList();
    final selectableIds = todos.where((t) => t.id != null).map((t) => t.id!).toList();

    return Scaffold(
      appBar: _selection.active
          ? StudentSelectionAppBar(
              title: '信仰生活代辦',
              selectionCount: _selection.count,
              totalCount: selectableIds.length,
              onCancel: _selection.cancel,
              onSelectAll: () {
                if (_selection.count == selectableIds.length && selectableIds.isNotEmpty) {
                  _selection.cancel();
                  _selection.start();
                } else {
                  _selection.selectAll(selectableIds);
                }
              },
            )
          : AppBar(
              title: const Text('信仰生活代辦'),
              actions: [
                if (todos.isNotEmpty)
                  TextButton(onPressed: _selection.start, child: const Text('選取')),
              ],
            ),
      floatingActionButton: _selection.active
          ? null
          : FloatingActionButton(
              tooltip: '新增代辦',
              onPressed: () => _editTodo(context, ref, null),
              child: const Icon(Icons.add),
            ),
      bottomNavigationBar: _selection.active
          ? StudentBatchActionBar(actions: [
              StudentBatchAction(
                label: '完成',
                icon: Icons.check_circle_outline,
                onPressed: selectedTodos.isEmpty
                    ? null
                    : () => _setDone(selectedTodos, true),
              ),
              StudentBatchAction(
                label: '未完成',
                icon: Icons.radio_button_unchecked,
                onPressed: selectedTodos.isEmpty
                    ? null
                    : () => _setDone(selectedTodos, false),
              ),
              StudentBatchAction(
                label: '刪除',
                icon: Icons.delete_outline,
                destructive: true,
                onPressed:
                    selectedTodos.isEmpty ? null : () => _delete(selectedTodos),
              ),
            ])
          : null,
      body: async.when(
        loading: () => const StudentCompactLoading(),
        error: (_, _) =>
            StudentErrorState(onRetry: () => ref.invalidate(allTodosProvider)),
        data: (list) {
          if (list.isEmpty) {
            return StudentEmptyState(
              title: '還沒有代辦事項',
              subtitle: '把想完成的信仰生活事項記在這裡。',
              icon: Icons.checklist,
              actionLabel: '新增代辦',
              onAction: () => _editTodo(context, ref, null),
            );
          }
          final doneCount = list.where((t) => t.done).length;
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: list.length + 1,
            separatorBuilder: (_, i) => i == 0
                ? const SizedBox.shrink()
                : const Divider(height: 1, indent: 56),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Text(
                    '已完成 $doneCount / ${list.length} 項',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline),
                  ),
                );
              }
              final todo = list[index - 1];
              final id = todo.id!;
              final selected = _selection.contains(id);
              final row = ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                leading: _selection.active
                    ? Checkbox(
                        value: selected,
                        onChanged: (_) => _selection.toggle(id),
                      )
                    : Checkbox(
                        value: todo.done,
                        onChanged: (v) => _setDone([todo], v ?? false),
                      ),
                title: Text(
                  todo.content,
                  style: TextStyle(
                    decoration: todo.done ? TextDecoration.lineThrough : null,
                    color: todo.done
                        ? Theme.of(context).colorScheme.outline
                        : null,
                  ),
                ),
                subtitle: todo.category.isEmpty ? null : Text(todo.category),
                onLongPress: () => _selection.start(id),
                onTap: _selection.active
                    ? () => _selection.toggle(id)
                    : () => _editTodo(context, ref, todo),
              );
              if (_selection.active) return row;
              return StudentSwipeRow(
                dismissKey: ValueKey('todo_$id'),
                startLabel: todo.done ? '未完成' : '完成',
                startIcon: todo.done
                    ? Icons.radio_button_unchecked
                    : Icons.check,
                endLabel: '刪除',
                onSwipeStartToEnd: () => _setDone([todo], !todo.done),
                onSwipeEndToStart: () => _delete([todo]),
                child: row,
              );
            },
          );
        },
      ),
    );
  }
}

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
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.viewInsetsOf(ctx).bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            existing == null ? '新增代辦' : '編輯代辦',
            style: Theme.of(ctx)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: content,
            maxLines: 3,
            autofocus: existing == null,
            decoration: const InputDecoration(labelText: '要做的事'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: category,
            decoration: const InputDecoration(labelText: '分類'),
          ),
          if (cats.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in cats)
                  ActionChip(
                    label: Text(c),
                    onPressed: () => category.text = c,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () async {
              final text = content.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(ctx);
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
              ref.invalidate(allTodosProvider);
            },
            child: const Text('儲存'),
          ),
        ],
      ),
    ),
  );
}
