import '../models/models.dart';

enum TodoListFilter { pending, all, completed }

TodoListFilter decodeTodoListFilter(String? value) {
  for (final filter in TodoListFilter.values) {
    if (filter.name == value) return filter;
  }
  return TodoListFilter.pending;
}

List<Todo> filterTodosForList(Iterable<Todo> values, TodoListFilter filter) =>
    switch (filter) {
      TodoListFilter.pending => values.where((todo) => !todo.done).toList(),
      TodoListFilter.all => values.toList(),
      TodoListFilter.completed => values.where((todo) => todo.done).toList(),
    };
