import '../models/models.dart';
import '../models/daily_verse_batch.dart';
import 'verse_locator.dart';

/// 每日經文批次的**純函式**核心（無 IO、無 Firestore、無 corpus 寫入）：
/// 確定性排程 → 批次草稿規格 → 整批驗證。內容無關；候選由使用者提供。
class DailyVerseScheduler {
  /// 台北日界的日期加減（純日曆計算，UTC 錨定避免 DST/本地時區干擾）。
  /// 輸入/輸出皆 'YYYY-MM-DD'。
  static String addDaysYmd(String ymd, int n) {
    final p = ymd.split('-');
    final d = DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]))
        .add(Duration(days: n));
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// 確定性排程：把**已核准**候選池依「池內順序」逐日指派到 [startYmd] 起的連續日期。
  ///
  /// Fail-closed：
  /// - 池未核准 → failClosedReason='pool_not_approved'。
  /// - 池為空   → failClosedReason='pool_empty'。
  /// 兩者皆回空 assignments，**絕不從整本聖經任意補位**。
  ///
  /// 候選不足 [days] 且未允許重複（預設）→ 只排候選數那麼多天，warnings 記 'shortfall:N'
  /// （其餘日期留白，交由使用者補足候選；不 fabricate）。allowRepeat=true 才會
  /// 依 round-robin 確定性填滿 [days]（同一組輸入永遠得到同一結果）。
  static DailyVerseScheduleResult scheduleDays(
    DailyVerseCandidatePool pool, {
    required String startYmd,
    int days = 30,
    bool allowRepeat = false,
  }) {
    if (!pool.approved) {
      return const DailyVerseScheduleResult(failClosedReason: 'pool_not_approved');
    }
    if (pool.candidates.isEmpty) {
      return const DailyVerseScheduleResult(failClosedReason: 'pool_empty');
    }
    final n = pool.candidates.length;
    final limit = allowRepeat ? days : (days < n ? days : n);
    final assignments = <DailyVerseAssignment>[
      for (var i = 0; i < limit; i++)
        DailyVerseAssignment(
          date: addDaysYmd(startYmd, i),
          candidate: pool.candidates[allowRepeat ? (i % n) : i],
          poolIndex: allowRepeat ? (i % n) : i,
        ),
    ];
    final warnings = <String>[
      if (!allowRepeat && n < days) 'shortfall:${days - n}',
    ];
    return DailyVerseScheduleResult(assignments: assignments, warnings: warnings);
  }

  /// 依 corpus 把排程結果解析成批次草稿規格（正文只讀取自 corpus，不 fabricate）。
  static List<DailyVerseDraftSpec> buildDraftSpecs(
          DailyVerseScheduleResult schedule, List<Book> books) =>
      [for (final a in schedule.assignments) _spec(a, books)];

  static DailyVerseDraftSpec _spec(DailyVerseAssignment a, List<Book> books) {
    final loc = VerseLocator.parse(a.candidate.ref.trim(), books);
    if (loc == null || loc.verse == null) {
      // 無法解析單節 → 標記需人工修正；不猜測、不補位。
      return DailyVerseDraftSpec(
        date: a.date,
        ref: a.candidate.ref,
        title: a.candidate.title,
        content: a.candidate.content,
        refResolves: false,
      );
    }
    Book? book;
    for (final b in books) {
      if (b.id == loc.bookId) {
        book = b;
        break;
      }
    }
    final text = (book != null &&
            loc.chapter >= 1 &&
            loc.chapter <= book.chapters.length &&
            loc.verse! >= 1 &&
            loc.verse! <= book.chapters[loc.chapter - 1].length)
        ? book.chapters[loc.chapter - 1][loc.verse! - 1]
        : null;
    return DailyVerseDraftSpec(
      date: a.date,
      ref: a.candidate.ref,
      title: a.candidate.title,
      content: a.candidate.content,
      bookId: loc.bookId,
      chapter: loc.chapter,
      verse: loc.verse,
      resolvedText: text,
      refResolves: text != null,
    );
  }

  /// 整批送出前健檢：全部 ref 可解析、日期唯一。
  static DailyVerseBatchValidation validate(List<DailyVerseDraftSpec> specs) {
    final dates = [for (final s in specs) s.date];
    return DailyVerseBatchValidation(
      count: specs.length,
      unresolvedDates: [for (final s in specs) if (!s.refResolves) s.date],
      hasDuplicateDates: dates.length != dates.toSet().length,
    );
  }
}
