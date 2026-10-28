import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../utils/todo_list_presentation.dart';
import '../widgets/student_ux.dart';

class TodosScreen extends ConsumerStatefulWidget {
  const TodosScreen({super.key});

  @override
  ConsumerState<TodosScreen> createState() => _TodosScreenState();
}

class _TodosScreenState extends ConsumerState<TodosScreen> {
  static const _filterPreferenceKey = 'todos_list_filter';
  final SelectionController<int> _selection = SelectionController<int>();
  TodoListFilter _filter = TodoListFilter.pending;

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
      () =>
          _filter = decodeTodoListFilter(prefs.getString(_filterPreferenceKey)),
    );
  }

  Future<void> _changeFilter(TodoListFilter filter) async {
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

  Future<void> _refresh() async => ref.invalidate(allTodosProvider);

  Future<void> _setDone(Iterable<Todo> todos, bool done) async {
    final changed = todos.where((todo) => todo.done != done).toList();
    if (changed.isEmpty) return;
    final db = ref.read(databaseServiceProvider);
    var written = 0;
    var failed = false;
    try {
      for (final todo in changed) {
        await db.saveTodo(todo.copyWith(done: done));
        written++;
      }
    } catch (_) {
      failed = true;
    }
    // 不論成敗都重新讀取：寫到一半失敗時，畫面要反映實際已寫入的狀態，
    // 不能停在舊狀態（也讓滑動列正常回彈，不把例外丟回手勢）。
    await _refresh();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    if (failed) {
      // 保留選取，使用者可直接重試尚未寫入的項目。
      final remaining = changed.skip(written).toList();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            written == 0
                ? '更新失敗，代辦狀態沒有變更。'
                : '只更新了 $written / ${changed.length} 項，其餘沒有變更。',
          ),
          action: SnackBarAction(
            label: '重試',
            onPressed: () => _setDone(remaining, done),
          ),
        ),
      );
      return;
    }
    _selection.cancel();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          changed.length == 1
              ? (done ? '已標記為完成' : '已改回待完成')
              : '已更新 ${changed.length} 項代辦',
        ),
        action: SnackBarAction(
          label: '復原',
          onPressed: () => _restoreDone(changed),
        ),
      ),
    );
  }

  /// 復原打勾：寫回原本狀態；失敗時同樣重新讀取並提供重試（寫回原值可重複執行）。
  Future<void> _restoreDone(List<Todo> originals) async {
    final db = ref.read(databaseServiceProvider);
    var failed = false;
    try {
      for (final todo in originals) {
        await db.saveTodo(todo);
      }
    } catch (_) {
      failed = true;
    }
    await _refresh();
    if (!failed || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: const Text('復原失敗，畫面顯示的是目前實際狀態。'),
          action: SnackBarAction(
            label: '重試',
            onPressed: () => _restoreDone(originals),
          ),
        ),
      );
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
    await _performDelete(list);
  }

  /// 已確認後的刪除；重試走這裡，不再重複詢問。
  Future<void> _performDelete(List<Todo> list) async {
    final db = ref.read(databaseServiceProvider);
    var deleted = 0;
    var failed = false;
    try {
      for (final todo in list) {
        await db.deleteTodo(todo.id!);
        deleted++;
      }
    } catch (_) {
      failed = true;
    }
    // 不論成敗都重新讀取：刪到一半失敗時，畫面要反映實際還在的代辦，
    // 不能假裝全部刪除（也不把例外丟回滑動手勢）。
    await _refresh();
    if (!mounted) return;
    if (!failed) {
      _selection.cancel();
      return;
    }
    // 保留選取，使用者可直接重試尚未刪除的項目；已刪的移出選取，計數才與畫面一致。
    final remaining = list.skip(deleted).toList();
    if (_selection.active) {
      _selection.selectAll(remaining.map((todo) => todo.id!));
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            deleted == 0
                ? '刪除失敗，代辦仍保留。'
                : '只刪除了 $deleted / ${list.length} 項，其餘仍保留。',
          ),
          action: SnackBarAction(
            label: '重試',
            onPressed: () => _performDelete(remaining),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(allTodosProvider);
    final todos = async.value ?? const <Todo>[];
    final visibleTodos = filterTodosForList(todos, _filter);
    final selectedTodos = visibleTodos
        .where((t) => t.id != null && _selection.contains(t.id!))
        .toList();
    final selectableIds = visibleTodos
        .where((t) => t.id != null)
        .map((t) => t.id!)
        .toList();

    return Scaffold(
      appBar: _selection.active
          ? StudentSelectionAppBar(
              title: '信仰生活代辦',
              selectionCount: _selection.count,
              totalCount: selectableIds.length,
              onCancel: _selection.cancel,
              onSelectAll: () {
                if (_selection.count == selectableIds.length &&
                    selectableIds.isNotEmpty) {
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
                if (todos.any((todo) => todo.done))
                  IconButton(
                    tooltip: '清除已完成',
                    icon: const Icon(Icons.delete_sweep_outlined),
                    onPressed: () => _delete(todos.where((todo) => todo.done)),
                  ),
                if (todos.isNotEmpty)
                  TextButton(
                    onPressed: _selection.start,
                    child: const Text('選取'),
                  ),
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
          ? StudentBatchActionBar(
              actions: [
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
                  onPressed: selectedTodos.isEmpty
                      ? null
                      : () => _delete(selectedTodos),
                ),
              ],
            )
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
          final visible = filterTodosForList(list, _filter);
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: visible.isEmpty ? 3 : visible.length + 2,
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
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                );
              }
              if (index == 1) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SegmentedButton<TodoListFilter>(
                    segments: [
                      ButtonSegment(
                        value: TodoListFilter.pending,
                        label: Text('待辦 ${list.length - doneCount}'),
                      ),
                      ButtonSegment(
                        value: TodoListFilter.all,
                        label: Text('全部 ${list.length}'),
                      ),
                      ButtonSegment(
                        value: TodoListFilter.completed,
                        label: Text('完成 $doneCount'),
                      ),
                    ],
                    selected: {_filter},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) =>
                        _changeFilter(selection.first),
                  ),
                );
              }
              if (visible.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 56),
                  child: StudentEmptyState(
                    title: _filter == TodoListFilter.completed
                        ? '還沒有已完成的代辦'
                        : '目前沒有待完成的代辦',
                    subtitle: _filter == TodoListFilter.completed
                        ? '完成代辦後會整理在這裡。'
                        : '做得很好，可以新增下一個行動。',
                    icon: _filter == TodoListFilter.completed
                        ? Icons.check_circle_outline
                        : Icons.task_alt,
                    actionLabel: '清除篩選',
                    onAction: () => _changeFilter(TodoListFilter.all),
                  ),
                );
              }
              final todo = visible[index - 2];
              final id = todo.id!;
              final selected = _selection.contains(id);
              final row = ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 4,
                ),
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
  final formKey = GlobalKey<FormState>();
  final category = TextEditingController(text: existing?.category ?? '');
  final content = TextEditingController(text: existing?.content ?? '');
  final todos = ref.read(allTodosProvider).value ?? const <Todo>[];
  final cats = {
    for (final t in todos)
      if (t.category.isNotEmpty) t.category,
  }.toList();
  var saving = false;
  var saveFailed = false;

  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(ctx).bottom + 20,
      ),
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              existing == null ? '新增代辦' : '編輯代辦',
              style: Theme.of(
                ctx,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: content,
              maxLines: 3,
              autofocus: existing == null,
              decoration: const InputDecoration(labelText: '要做的事'),
              validator: (value) =>
                  value?.trim().isEmpty ?? true ? '請輸入要完成的事項' : null,
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
            // 先寫入、成功才關閉：寫入失敗時保留已輸入的文字，可直接重試。
            StatefulBuilder(
              builder: (ctx, setSheetState) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (saveFailed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          '儲存失敗，內容仍保留，請再試一次。',
                          style: TextStyle(
                            color: Theme.of(ctx).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
                            if (!(formKey.currentState?.validate() ?? false)) {
                              return;
                            }
                            setSheetState(() {
                              saving = true;
                              saveFailed = false;
                            });
                            try {
                              await ref
                                  .read(databaseServiceProvider)
                                  .saveTodo(
                                    Todo(
                                      id: existing?.id,
                                      category: category.text.trim(),
                                      content: content.text.trim(),
                                      done: existing?.done ?? false,
                                      createdAt: existing?.createdAt ?? 0,
                                      updatedAt: existing?.updatedAt ?? 0,
                                    ),
                                  );
                            } catch (_) {
                              if (ctx.mounted) {
                                setSheetState(() {
                                  saving = false;
                                  saveFailed = true;
                                });
                              }
                              return;
                            }
                            ref.invalidate(allTodosProvider);
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                    child: Text(saving ? '儲存中…' : (saveFailed ? '重試儲存' : '儲存')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
