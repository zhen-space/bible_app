import 'package:bible_app/models/models.dart';
import 'package:bible_app/utils/todo_list_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const todos = [
    Todo(id: 1, category: '讀經', content: '讀一章', done: false),
    Todo(id: 2, category: '禱告', content: '為家人禱告', done: true),
    Todo(id: 3, category: '', content: '背經', done: false),
  ];

  test('待完成篩選只保留未完成項目', () {
    expect(
      filterTodosForList(todos, TodoListFilter.pending).map((todo) => todo.id),
      [1, 3],
    );
  });

  test('全部與已完成篩選會回傳正確項目', () {
    expect(filterTodosForList(todos, TodoListFilter.all), hasLength(3));
    expect(
      filterTodosForList(
        todos,
        TodoListFilter.completed,
      ).map((todo) => todo.id),
      [2],
    );
  });
}
