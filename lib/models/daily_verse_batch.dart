/// 每日經文「批次候選池 → 確定性排程 → 批次草稿」的**內容無關（content-agnostic）**資料契約。
///
/// 硬性原則（R1）：
/// - 候選經文**只由使用者親自建立並人工核准**；本層絕不自行填入或杜撰候選。
/// - 經文正文**只能**由既有正式 Bible corpus 依 reference 解析取得（見 scheduler）。
/// - 未核准／空候選池 → 排程 **fail-closed**（不從整本聖經任意補位）。
/// - 這一層純資料 + 純函式，不寫 Firestore、不做 production mutation。
library;

/// 單一候選：一個 scripture reference（單節，如「約3:16」）＋使用者親撰的 title/content。
/// title/content 可空；ref 之正文由 corpus 解析，不在此存正文。
///
/// [date]（台北 YYYY-MM-DD）**選填**：自動選取（auto）流程會把「已指派日期」的候選存進池，
/// 供 Draft 建立時精準落到該日（跳過已 Published 日期）；手動（manual）流程 date 為 null，
/// 沿用「依池序逐日指派」的舊行為。null 時序列化省略，維持既有 doc 形狀（向後相容）。
class DailyVerseCandidate {
  final String ref;
  final String title;
  final String content;
  final String? date;
  const DailyVerseCandidate({
    required this.ref,
    this.title = '',
    this.content = '',
    this.date,
  });

  factory DailyVerseCandidate.fromJson(Map<String, dynamic> m) => DailyVerseCandidate(
        ref: (m['ref'] as String?) ?? '',
        title: (m['title'] as String?) ?? '',
        content: (m['content'] as String?) ?? '',
        date: m['date'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'ref': ref,
        'title': title,
        'content': content,
        if (date != null) 'date': date,
      };
}

/// 版本化候選池。**只有 approved 且非空**才可被排程（[isSchedulable]）。
/// version 每次人工核准/更新遞增（由 repository 負責遞增，本 model 只承載）。
///
/// provenance（[source]/[catalogVersion]/[algoVersion]/[generatedAt]）記錄本池是
/// 「自動選取（auto）」或「手動輸入（manual）」，以及自動選取時所用的 catalog／
/// 演算法版本與產生時間，供審核與重現。手動池的 source='manual'、版本為 0（向後相容）。
class DailyVerseCandidatePool {
  final int version;
  final bool approved;
  final List<DailyVerseCandidate> candidates;
  final String source; // 'manual' | 'auto'
  final int catalogVersion;
  final int algoVersion;
  final int? generatedAt; // epoch millis（auto 產生時）

  const DailyVerseCandidatePool({
    this.version = 0,
    this.approved = false,
    this.candidates = const [],
    this.source = 'manual',
    this.catalogVersion = 0,
    this.algoVersion = 0,
    this.generatedAt,
  });

  /// 排程前置條件：人工已核准且候選非空。不符即 fail-closed。
  bool get isSchedulable => approved && candidates.isNotEmpty;

  DailyVerseCandidatePool copyWith({
    int? version,
    bool? approved,
    List<DailyVerseCandidate>? candidates,
    String? source,
    int? catalogVersion,
    int? algoVersion,
    int? generatedAt,
  }) =>
      DailyVerseCandidatePool(
        version: version ?? this.version,
        approved: approved ?? this.approved,
        candidates: candidates ?? this.candidates,
        source: source ?? this.source,
        catalogVersion: catalogVersion ?? this.catalogVersion,
        algoVersion: algoVersion ?? this.algoVersion,
        generatedAt: generatedAt ?? this.generatedAt,
      );

  factory DailyVerseCandidatePool.fromJson(Map<String, dynamic> m) =>
      DailyVerseCandidatePool(
        version: (m['version'] as int?) ?? 0,
        approved: (m['approved'] as bool?) ?? false,
        candidates: ((m['candidates'] as List?) ?? const [])
            .map((e) => DailyVerseCandidate.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        source: (m['source'] as String?) ?? 'manual',
        catalogVersion: (m['catalog_version'] as int?) ?? 0,
        algoVersion: (m['algo_version'] as int?) ?? 0,
        generatedAt: m['generated_at'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'approved': approved,
        'candidates': [for (final c in candidates) c.toJson()],
        'source': source,
        'catalog_version': catalogVersion,
        'algo_version': algoVersion,
        if (generatedAt != null) 'generated_at': generatedAt,
      };
}

/// 排程結果一筆：日期（台北 YYYY-MM-DD）→ 指派到的候選（含其在池中的索引）。
class DailyVerseAssignment {
  final String date;
  final DailyVerseCandidate candidate;
  final int poolIndex;
  const DailyVerseAssignment({
    required this.date,
    required this.candidate,
    required this.poolIndex,
  });
}

/// 確定性排程輸出。[failClosedReason] 非 null 代表排程被 fail-closed 擋下
/// （'pool_not_approved' / 'pool_empty'），此時 assignments 必為空。
class DailyVerseScheduleResult {
  final List<DailyVerseAssignment> assignments;
  final List<String> warnings; // 例：'shortfall:N'（候選不足 N 天，且未允許重複）
  final String? failClosedReason;

  const DailyVerseScheduleResult({
    this.assignments = const [],
    this.warnings = const [],
    this.failClosedReason,
  });

  bool get ok => failClosedReason == null;
}

/// 由排程 + corpus 解析出的一筆批次草稿規格（尚未寫入 Firestore）。
/// [refResolves]＝ref 是否能在 corpus 解析到單節；false 代表此筆需人工修正、
/// 不可送出（批次 apply 會 fail-closed）。resolvedText 僅供 Admin 逐句核對顯示。
class DailyVerseDraftSpec {
  final String date; // contentId（YYYY-MM-DD）
  final String ref;
  final String title;
  final String content;
  final int? bookId;
  final int? chapter;
  final int? verse;
  final String? resolvedText; // corpus 正文（只讀顯示，不落 payload）
  final bool refResolves;

  const DailyVerseDraftSpec({
    required this.date,
    required this.ref,
    this.title = '',
    this.content = '',
    this.bookId,
    this.chapter,
    this.verse,
    this.resolvedText,
    this.refResolves = false,
  });

  /// 寫入 workspace 草稿用的 payload（與既有 admin_daily_verse_screen 完全一致）。
  /// 正文不落 payload（讀取端一律由 corpus 依 book/chapter/verse 取得）。
  Map<String, dynamic> toPayload() => {
        'date': date,
        'book_id': bookId,
        'chapter': chapter,
        'verse': verse,
        'ref_text': ref,
        'title': title,
        'content': content,
      };
}

/// 批次驗證結果（送出前的整批健檢）。
class DailyVerseBatchValidation {
  final int count;
  final List<String> unresolvedDates; // ref 無法解析的日期
  final bool hasDuplicateDates;

  const DailyVerseBatchValidation({
    this.count = 0,
    this.unresolvedDates = const [],
    this.hasDuplicateDates = false,
  });

  bool get allResolve => unresolvedDates.isEmpty;
  bool get canSubmit => count > 0 && allResolve && !hasDuplicateDates;
}

// ===========================================================================
// 自動選取（auto-select）：系統從 curated catalog + corpus 正文解析，逐日確定性
// 指派未來 N 天的每日經文。內容正文一律來自 corpus，catalog 只提供節位。
// ===========================================================================

/// 自動選取後一天的規格。[published]＝該日已有對外 Published（鎖定、不覆寫、只讀顯示）；
/// [failClosed]＝當日沒有符合規則的候選（不 fabricate、留白待補）。
/// [flags] 為**建議性**旗標（如 'pronoun_start'），不阻擋送出，只供 Admin 參考。
class DailyVersePlanDay {
  final String date; // 台北 YYYY-MM-DD
  final String ref; // 顯示節位（abbr章:節）；failClosed 時為 ''
  final int? bookId;
  final int? chapter;
  final int? verse;
  final String? resolvedText; // corpus 正文（只讀顯示，不落 payload）
  final bool published;
  final bool failClosed;
  final List<String> flags;

  const DailyVersePlanDay({
    required this.date,
    this.ref = '',
    this.bookId,
    this.chapter,
    this.verse,
    this.resolvedText,
    this.published = false,
    this.failClosed = false,
    this.flags = const [],
  });

  /// 可建立為 Draft 的日：未 Published、未 fail-closed、且正文可解析。
  bool get isDraftable =>
      !published && !failClosed && bookId != null && chapter != null && verse != null;

  DailyVersePlanDay copyWith({
    String? ref,
    int? bookId,
    int? chapter,
    int? verse,
    String? resolvedText,
    bool? failClosed,
    List<String>? flags,
  }) =>
      DailyVersePlanDay(
        date: date,
        ref: ref ?? this.ref,
        bookId: bookId ?? this.bookId,
        chapter: chapter ?? this.chapter,
        verse: verse ?? this.verse,
        resolvedText: resolvedText ?? this.resolvedText,
        published: published,
        failClosed: failClosed ?? this.failClosed,
        flags: flags ?? this.flags,
      );
}

/// 自動選取整體計畫（確定性：同輸入同輸出）。
class DailyVerseAutoPlan {
  final List<DailyVersePlanDay> days;
  final String startYmd;
  final int requestedDays;
  final int catalogVersion;
  final int algoVersion;
  final List<String> warnings; // 例：'shortfall:N'（N 天無候選、留白待補）

  const DailyVerseAutoPlan({
    this.days = const [],
    required this.startYmd,
    this.requestedDays = 0,
    this.catalogVersion = 0,
    this.algoVersion = 0,
    this.warnings = const [],
  });

  /// 可建立 Draft 的日（未 Published、未 fail-closed、可解析）。
  List<DailyVersePlanDay> get draftableDays =>
      [for (final d in days) if (d.isDraftable) d];

  /// 已 Published（鎖定）的日。
  List<DailyVersePlanDay> get publishedDays =>
      [for (final d in days) if (d.published) d];

  /// fail-closed（無候選）的日。
  List<DailyVersePlanDay> get failClosedDays =>
      [for (final d in days) if (d.failClosed) d];

  bool get hasFailClosed => failClosedDays.isNotEmpty;
}
