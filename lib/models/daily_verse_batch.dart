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
class DailyVerseCandidate {
  final String ref;
  final String title;
  final String content;
  const DailyVerseCandidate({required this.ref, this.title = '', this.content = ''});

  factory DailyVerseCandidate.fromJson(Map<String, dynamic> m) => DailyVerseCandidate(
        ref: (m['ref'] as String?) ?? '',
        title: (m['title'] as String?) ?? '',
        content: (m['content'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {'ref': ref, 'title': title, 'content': content};
}

/// 版本化候選池。**只有 approved 且非空**才可被排程（[isSchedulable]）。
/// version 每次人工核准/更新遞增（由 repository 負責遞增，本 model 只承載）。
class DailyVerseCandidatePool {
  final int version;
  final bool approved;
  final List<DailyVerseCandidate> candidates;

  const DailyVerseCandidatePool({
    this.version = 0,
    this.approved = false,
    this.candidates = const [],
  });

  /// 排程前置條件：人工已核准且候選非空。不符即 fail-closed。
  bool get isSchedulable => approved && candidates.isNotEmpty;

  DailyVerseCandidatePool copyWith({
    int? version,
    bool? approved,
    List<DailyVerseCandidate>? candidates,
  }) =>
      DailyVerseCandidatePool(
        version: version ?? this.version,
        approved: approved ?? this.approved,
        candidates: candidates ?? this.candidates,
      );

  factory DailyVerseCandidatePool.fromJson(Map<String, dynamic> m) =>
      DailyVerseCandidatePool(
        version: (m['version'] as int?) ?? 0,
        approved: (m['approved'] as bool?) ?? false,
        candidates: ((m['candidates'] as List?) ?? const [])
            .map((e) => DailyVerseCandidate.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'approved': approved,
        'candidates': [for (final c in candidates) c.toJson()],
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
