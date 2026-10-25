import '../models/models.dart';

enum TodoListFilter { pending, all, completed }

List<Todo> filterTodosForList(Iterable<Todo> values, TodoListFilter filter) =>
    switch (filter) {
      TodoListFilter.pending => values.where((todo) => !todo.done).toList(),
      TodoListFilter.all => values.toList(),
      TodoListFilter.completed => values.where((todo) => todo.done).toList(),
    };
