import '../data/reading_plans.dart';
import '../models/models.dart';

ChapterRef? firstIncompleteChapter(
  List<ChapterRef> chapters,
  Set<String> progress,
) {
  for (final chapter in chapters) {
    if (!progress.contains('b${chapter.bookId}_c${chapter.chapter}')) {
      return chapter;
    }
  }
  return null;
}

class ReadingPlanToday {
  final ReadingPlan plan;
  final int day;
  final List<ChapterRef> chapters;
  final int completed;
  final bool planCompleted;

  const ReadingPlanToday({
    required this.plan,
    required this.day,
    required this.chapters,
    required this.completed,
    required this.planCompleted,
  });
}

/// 從既有逐章進度找出使用者目前正在進行的計畫與下一個未完成日。
///
/// 尚未開始任何計畫時回傳 null；同時有多個計畫時，選擇完成章數最多者，
/// 讓首頁穩定回到使用者投入最多的計畫，不任意重設進度。
ReadingPlanToday? selectReadingPlanToday({
  required List<ReadingPlan> plans,
  required List<Book> books,
  required Map<String, Set<String>> progressByPlan,
}) {
  ReadingPlan? active;
  Set<String> activeProgress = const {};

  for (final plan in plans) {
    final progress = progressByPlan[plan.id] ?? const <String>{};
    if (progress.isEmpty) continue;
    if (active == null || progress.length > activeProgress.length) {
      active = plan;
      activeProgress = progress;
    }
  }
  if (active == null) return null;

  final schedule = active.schedule(books);
  if (schedule.isEmpty) return null;
  bool done(ChapterRef chapter) =>
      activeProgress.contains('b${chapter.bookId}_c${chapter.chapter}');

  var dayIndex = schedule.indexWhere((day) => !day.every(done));
  final planCompleted = dayIndex < 0;
  if (planCompleted) dayIndex = schedule.length - 1;
  final chapters = schedule[dayIndex];

  return ReadingPlanToday(
    plan: active,
    day: dayIndex + 1,
    chapters: chapters,
    completed: chapters.where(done).length,
    planCompleted: planCompleted,
  );
}
