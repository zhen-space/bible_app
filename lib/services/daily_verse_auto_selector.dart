import '../data/daily_verse_catalog.dart';
import '../models/daily_verse_batch.dart';
import '../models/models.dart';
import 'daily_verse_scheduler.dart';
import 'verse_locator.dart';

/// 每日經文「自動選取」的**純函式**核心（無 IO、無 Firestore）。
///
/// 硬性原則（配合正式需求）：
/// - 系統從 [kDailyVerseCatalog]（curated 節位）＋ corpus 正文解析選取。
/// - 經文正文**只由 corpus 解析取得**，絕不由程式生成／改寫／補寫。
/// - **deterministic**：同一組輸入（catalog／corpus／startYmd／days／已發布歷史）永遠得到同一結果。
/// - **fail-closed**：某日找不到符合規則的候選 → 該日留白（failClosed），不 fabricate、不從整本聖經亂補。
/// - 已 Published 的日期**鎖定**：不重新產生、不覆寫（只讀顯示，並納入防重複／分散計算）。
/// - 「有意義」判定**不假裝靠關鍵字判斷神學意義**：意義由 curated catalog 承載；
///   本層只做**機械式**排除（長度／數字比例／家譜列表／清單式）與**建議性**旗標（代名詞開頭）。
class DailyVerseAutoSelector {
  /// 卡片長度上下限（中文字元數，含標點）。
  static const int minLen = 5;
  static const int maxLen = 90;

  /// 一節在 corpus 的正文；解析不到回 null（不猜測）。
  static String? resolveText(List<Book> books, int bookId, int chapter, int verse) {
    for (final b in books) {
      if (b.id != bookId) continue;
      if (chapter < 1 || chapter > b.chapters.length) return null;
      final vs = b.chapters[chapter - 1];
      if (verse < 1 || verse > vs.length) return null;
      return vs[verse - 1];
    }
    return null;
  }

  /// 顯示節位字串（abbr + 章:節），如「約3:16」；找不到書卷回數字節位。
  static String refString(List<Book> books, int bookId, int chapter, int verse) {
    for (final b in books) {
      if (b.id == bookId) return '${b.abbr}$chapter:$verse';
    }
    return '$bookId:$chapter:$verse';
  }

  /// **機械式硬排除**（回傳非空 = 不適合當每日經文）。純機械，不判斷神學意義。
  /// - too_short / too_long：不適合首頁卡片長度。
  /// - digit_heavy：數字比例過高（尺寸／清冊／年代等）。
  /// - genealogy：家譜／後裔敘述（含「生了／的兒子／的後裔」且含數字）。
  /// - list_like：四個以上頓號的列舉式（清單）。
  static List<String> hardIssues(String text) {
    final chars = text.runes.length;
    final digits = RegExp(r'[0-9]').allMatches(text).length;
    final commas = '、'.allMatches(text).length;
    final issues = <String>[];
    if (chars < minLen) issues.add('too_short');
    if (chars > maxLen) issues.add('too_long');
    if (chars > 0 && digits / chars > 0.15) issues.add('digit_heavy');
    if (digits > 0 && RegExp(r'(生了|的兒子|的後裔)').hasMatch(text)) {
      issues.add('genealogy');
    }
    if (commas >= 4) issues.add('list_like');
    return issues;
  }

  /// **建議性旗標**（不阻擋，只提醒 Admin 檢視）。目前：pronoun_start＝
  /// 以代名詞／連接詞開頭，單獨摘錄較可能需要前文（但許多名句仍以「我／你」開頭，故不排除）。
  static List<String> advisoryFlags(String text) {
    final flags = <String>[];
    if (RegExp(r'^(他|她|它|他們|她們|你們|我們|因此|所以|於是|這|那|但|又|然後)')
        .hasMatch(text.trimLeft())) {
      flags.add('pronoun_start');
    }
    return flags;
  }

  /// UTC 錨定的日序（天數），供 365 天防重複與分散視窗計算。
  static int _ordinal(String ymd) {
    final p = ymd.split('-');
    return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]))
        .difference(DateTime.utc(1970, 1, 1))
        .inDays;
  }

  static String _verseKey(int bookId, int chapter, int verse) =>
      '$bookId:$chapter:$verse';

  /// 依 catalog 宣告順序過濾出「可解析且通過硬排除」的條目（確定性順序）。
  static List<DailyVersePlanDay> _resolvedCatalog(
      List<Book> books, List<DailyVerseCatalogEntry> catalog) {
    final out = <DailyVersePlanDay>[];
    for (final e in catalog) {
      final text = resolveText(books, e.book, e.chapter, e.verse);
      if (text == null) continue; // 解析不到 → 不納入（測試守著 catalog 全可解析）
      if (hardIssues(text).isNotEmpty) continue; // 機械排除
      out.add(DailyVersePlanDay(
        date: '', // 稍後指派
        ref: refString(books, e.book, e.chapter, e.verse),
        bookId: e.book,
        chapter: e.chapter,
        verse: e.verse,
        resolvedText: text,
        flags: advisoryFlags(text),
      ));
    }
    return out;
  }

  /// 自動產生未來 [days] 天計畫。
  ///
  /// - [publishedByDate]：日期 → 已 Published 的節位（鎖定，不覆寫）。
  /// - [history]：已 Published 的使用紀錄（含 [publishedByDate] 以外的過去日期），
  ///   供 [noRepeatDays] 防重複；每筆 (date, bookId, chapter, verse)。
  /// - [noRepeatDays]：同一節在此天數內不重複（預設 365）。
  /// - [maxSameBookInWindow]/[sameBookWindow]：同書卷在滑動視窗內至多出現次數（分散）。
  static DailyVerseAutoPlan generate({
    required List<Book> books,
    required String startYmd,
    int days = 30,
    List<DailyVerseCatalogEntry> catalog = kDailyVerseCatalog,
    Map<String, ({int bookId, int chapter, int verse})> publishedByDate = const {},
    List<({String date, int bookId, int chapter, int verse})> history = const [],
    int noRepeatDays = 365,
    int maxSameBookInWindow = 2,
    int sameBookWindow = 7,
    int catalogVersion = kDailyVerseCatalogVersion,
    int algoVersion = kDailyVerseSelectionAlgoVersion,
  }) {
    final resolved = _resolvedCatalog(books, catalog);
    // 使用紀錄（防重複）：verseKey → 使用日序清單。先灌入歷史與 published。
    final usage = <String, List<int>>{};
    void addUsage(int bookId, int chapter, int verse, String date) {
      usage.putIfAbsent(_verseKey(bookId, chapter, verse), () => []).add(_ordinal(date));
    }
    for (final h in history) {
      addUsage(h.bookId, h.chapter, h.verse, h.date);
    }
    publishedByDate.forEach((date, v) => addUsage(v.bookId, v.chapter, v.verse, date));

    // 分散計算：已指派/已發布的 (日序, bookId)。
    final placed = <({int ord, int bookId})>[];
    int? prevBookId; // 前一天（有節位者）的書卷，供「不連續同書卷」

    bool usedWithin(int bookId, int chapter, int verse, int ord) {
      final list = usage[_verseKey(bookId, chapter, verse)];
      if (list == null) return false;
      for (final o in list) {
        if ((ord - o).abs() < noRepeatDays) return true;
      }
      return false;
    }

    int sameBookInWindow(int bookId, int ord) {
      var c = 0;
      for (final p in placed) {
        if (p.bookId == bookId && (ord - p.ord).abs() < sameBookWindow) c++;
      }
      return c;
    }

    final out = <DailyVersePlanDay>[];
    final warnings = <String>[];
    var cursor = 0;
    var shortfall = 0;

    for (var i = 0; i < days; i++) {
      final date = DailyVerseScheduler.addDaysYmd(startYmd, i);
      final ord = _ordinal(date);

      // 已 Published：鎖定、只讀、納入防重複/分散。
      final pub = publishedByDate[date];
      if (pub != null) {
        final text = resolveText(books, pub.bookId, pub.chapter, pub.verse);
        out.add(DailyVersePlanDay(
          date: date,
          ref: refString(books, pub.bookId, pub.chapter, pub.verse),
          bookId: pub.bookId,
          chapter: pub.chapter,
          verse: pub.verse,
          resolvedText: text,
          published: true,
        ));
        placed.add((ord: ord, bookId: pub.bookId));
        prevBookId = pub.bookId;
        continue;
      }

      // 未 Published：確定性掃描 catalog，找第一個合規候選。
      DailyVersePlanDay? pick;
      if (resolved.isNotEmpty) {
        for (var step = 0; step < resolved.length; step++) {
          final cand = resolved[cursor % resolved.length];
          cursor++;
          final b = cand.bookId!, c = cand.chapter!, v = cand.verse!;
          if (usedWithin(b, c, v, ord)) continue; // 365 天內重複
          if (prevBookId != null && b == prevBookId) continue; // 不連續同書卷
          if (sameBookInWindow(b, ord) >= maxSameBookInWindow) continue; // 視窗集中
          pick = cand.copyWith(); // 命中
          break;
        }
      }

      if (pick == null) {
        // fail-closed：留白，不 fabricate。
        out.add(DailyVersePlanDay(date: date, failClosed: true));
        shortfall++;
        // prevBookId 不更新（該日無節位）
        continue;
      }

      out.add(DailyVersePlanDay(
        date: date,
        ref: pick.ref,
        bookId: pick.bookId,
        chapter: pick.chapter,
        verse: pick.verse,
        resolvedText: pick.resolvedText,
        flags: pick.flags,
      ));
      addUsage(pick.bookId!, pick.chapter!, pick.verse!, date);
      placed.add((ord: ord, bookId: pick.bookId!));
      prevBookId = pick.bookId;
    }

    if (shortfall > 0) warnings.add('shortfall:$shortfall');

    return DailyVerseAutoPlan(
      days: out,
      startYmd: startYmd,
      requestedDays: days,
      catalogVersion: catalogVersion,
      algoVersion: algoVersion,
      warnings: warnings,
    );
  }

  /// 由已存池（帶 date 的候選）重建計畫，供 Admin 重開畫面時還原先前產生的結果，
  /// 並以最新 [publishedByDate] 重新鎖定已發布日期（不覆寫）。ref 無法解析 → 該日 failClosed。
  static DailyVerseAutoPlan planFromDatedPool({
    required List<Book> books,
    required DailyVerseCandidatePool pool,
    Map<String, ({int bookId, int chapter, int verse})> publishedByDate = const {},
  }) {
    final dated = [
      for (final c in pool.candidates)
        if (c.date != null) c,
    ]..sort((a, b) => a.date!.compareTo(b.date!));
    final days = <DailyVersePlanDay>[];
    for (final c in dated) {
      final date = c.date!;
      final pub = publishedByDate[date];
      if (pub != null) {
        days.add(DailyVersePlanDay(
          date: date,
          ref: refString(books, pub.bookId, pub.chapter, pub.verse),
          bookId: pub.bookId,
          chapter: pub.chapter,
          verse: pub.verse,
          resolvedText: resolveText(books, pub.bookId, pub.chapter, pub.verse),
          published: true,
        ));
        continue;
      }
      final loc = VerseLocator.parse(c.ref, books);
      if (loc == null || loc.verse == null) {
        days.add(DailyVersePlanDay(date: date, ref: c.ref, failClosed: true));
        continue;
      }
      final text = resolveText(books, loc.bookId, loc.chapter, loc.verse!);
      if (text == null) {
        days.add(DailyVersePlanDay(date: date, ref: c.ref, failClosed: true));
        continue;
      }
      days.add(DailyVersePlanDay(
        date: date,
        ref: c.ref,
        bookId: loc.bookId,
        chapter: loc.chapter,
        verse: loc.verse,
        resolvedText: text,
        flags: advisoryFlags(text),
      ));
    }
    return DailyVerseAutoPlan(
      days: days,
      startYmd: days.isEmpty ? '' : days.first.date,
      requestedDays: days.length,
      catalogVersion: pool.catalogVersion,
      algoVersion: pool.algoVersion,
    );
  }

  /// 以節位字串（如「約3:16」）建立單日規格，供 Admin 手動替換單筆。解析不到回 null。
  static DailyVersePlanDay? dayFromRef(List<Book> books, String date, String ref) {
    final loc = VerseLocator.parse(ref.trim(), books);
    if (loc == null || loc.verse == null) return null;
    final text = resolveText(books, loc.bookId, loc.chapter, loc.verse!);
    if (text == null) return null;
    return DailyVersePlanDay(
      date: date,
      ref: refString(books, loc.bookId, loc.chapter, loc.verse!),
      bookId: loc.bookId,
      chapter: loc.chapter,
      verse: loc.verse,
      resolvedText: text,
      flags: advisoryFlags(text),
    );
  }

  /// 把計畫的**可建立日**轉為批次草稿規格（正文由 corpus，已在 plan 內解析）。
  /// 已 Published／fail-closed 的日**不**產生 spec（不覆寫、不 fabricate）。
  static List<DailyVerseDraftSpec> planToSpecs(DailyVerseAutoPlan plan) => [
        for (final d in plan.days)
          if (d.isDraftable)
            DailyVerseDraftSpec(
              date: d.date,
              ref: d.ref,
              bookId: d.bookId,
              chapter: d.chapter,
              verse: d.verse,
              resolvedText: d.resolvedText,
              refResolves: true,
            ),
      ];
}

/// 選取演算法版本。**改變選取邏輯時 +1**（provenance 用）。
const int kDailyVerseSelectionAlgoVersion = 1;
