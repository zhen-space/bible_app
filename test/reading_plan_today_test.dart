import 'package:bible_app/data/reading_plans.dart';
import 'package:bible_app/models/models.dart';
import 'package:bible_app/services/reading_plan_today.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final books = [
    Book(
      id: 1,
      name: '測試書',
      abbr: '測',
      testament: 'ot',
      chapters: List.generate(4, (i) => ['第 ${i + 1} 章']),
    ),
  ];
  const plan = ReadingPlan(
    id: 'test',
    name: '測試計畫',
    subtitle: '',
    emoji: '📖',
    days: 2,
  );

  test('沒有任何完成項目時視為尚未開始', () {
    final result = selectReadingPlanToday(
      plans: const [plan],
      books: books,
      progressByPlan: const {'test': {}},
    );
    expect(result, isNull);
  });

  test('回到第一個未完成日並計算當日進度', () {
    final result = selectReadingPlanToday(
      plans: const [plan],
      books: books,
      progressByPlan: const {
        'test': {'b1_c1', 'b1_c2', 'b1_c3'},
      },
    );
    expect(result, isNotNull);
    expect(result!.day, 2);
    expect(result.completed, 1);
    expect(result.chapters.length, 2);
    expect(result.planCompleted, isFalse);
  });

  test('全計畫完成時保留最後一天並顯示完成', () {
    final result = selectReadingPlanToday(
      plans: const [plan],
      books: books,
      progressByPlan: const {
        'test': {'b1_c1', 'b1_c2', 'b1_c3', 'b1_c4'},
      },
    );
    expect(result!.day, 2);
    expect(result.completed, 2);
    expect(result.planCompleted, isTrue);
  });

  test('多個進行中計畫選擇完成章數最多者', () {
    const other = ReadingPlan(
      id: 'other',
      name: '另一計畫',
      subtitle: '',
      emoji: '✝️',
      days: 2,
    );
    final result = selectReadingPlanToday(
      plans: const [plan, other],
      books: books,
      progressByPlan: const {
        'test': {'b1_c1'},
        'other': {'b1_c1', 'b1_c2'},
      },
    );
    expect(result!.plan.id, 'other');
  });
}
