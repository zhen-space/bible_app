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

  /// 防禦性解析：任何欄位型別不符一律退回安全預設，**不丟例外**
  /// （malformed payload 不得讓讀取路徑崩潰或永久 spinner）。
  factory DailyVerseCandidate.fromJson(Map<String, dynamic> m) => DailyVerseCandidate(
        ref: m['ref'] is String ? m['ref'] as String : '',
        title: m['title'] is String ? m['title'] as String : '',
        content: m['content'] is String ? m['content'] as String : '',
        date: m['date'] is String ? m['date'] as String : null,
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
  /// 讀取時偵測到候選資料損壞；僅供 Admin 顯示，永不寫回 Firestore。
  final bool hasMalformedCandidates;

  const DailyVerseCandidatePool({
    this.version = 0,
    this.approved = false,
    this.candidates = const [],
    this.source = 'manual',
    this.catalogVersion = 0,
    this.algoVersion = 0,
    this.generatedAt,
    this.hasMalformedCandidates = false,
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
    bool? hasMalformedCandidates,
  }) =>
      DailyVerseCandidatePool(
        version: version ?? this.version,
        approved: approved ?? this.approved,
        candidates: candidates ?? this.candidates,
        source: source ?? this.source,
        catalogVersion: catalogVersion ?? this.catalogVersion,
        algoVersion: algoVersion ?? this.algoVersion,
        generatedAt: generatedAt ?? this.generatedAt,
        hasMalformedCandidates:
            hasMalformedCandidates ?? this.hasMalformedCandidates,
      );

  /// 防禦性解析：型別不符退回安全預設，**不丟例外**。
  /// 任一候選被略過或降級時，整池一律撤銷核准（fail-closed），避免
  /// 部分／損壞候選池仍被排程。
  factory DailyVerseCandidatePool.fromJson(Map<String, dynamic> m) {
    final rawList = m['candidates'];
    final candidates = <DailyVerseCandidate>[];
    var structurallyValid = rawList is List;
    if (rawList is List) {
      for (final e in rawList) {
        if (e is! Map) {
          structurallyValid = false;
          continue;
        }
        final candidateMap = e.cast<String, dynamic>();
        final ref = candidateMap['ref'];
        final candidateValid =
            ref is String &&
            ref.trim().isNotEmpty &&
            (!candidateMap.containsKey('title') ||
                candidateMap['title'] is String) &&
            (!candidateMap.containsKey('content') ||
                candidateMap['content'] is String) &&
            (!candidateMap.containsKey('date') ||
                candidateMap['date'] is String);
        if (!candidateValid) {
          structurallyValid = false;
          continue;
        }
        candidates.add(DailyVerseCandidate.fromJson(candidateMap));
      }
    }
    final requestedApproved =
        m['approved'] is bool ? m['approved'] as bool : false;
    return DailyVerseCandidatePool(
      version: m['version'] is int ? m['version'] as int : 0,
      approved: requestedApproved && structurallyValid,
      candidates: candidates,
      source: m['source'] is String ? m['source'] as String : 'manual',
      catalogVersion: m['catalog_version'] is int ? m['catalog_version'] as int : 0,
      algoVersion: m['algo_version'] is int ? m['algo_version'] as int : 0,
      generatedAt: m['generated_at'] is int ? m['generated_at'] as int : null,
      hasMalformedCandidates: !structurallyValid,
    );
  }

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

enum DailyVerseDraftOutcome {
  created,
  alreadyExists,
  conflict,
  failed,
  unknown,
}

class DailyVerseDraftItemResult {
  final String date;
  final DailyVerseDraftOutcome outcome;
  final String message;

  const DailyVerseDraftItemResult({
    required this.date,
    required this.outcome,
    this.message = '',
  });
}

/// A complete, per-date receipt for a batch Draft attempt.
///
/// `unknown` means the client stopped waiting for Firestore. The underlying
/// operation may still settle, so callers must reconcile before retrying.
class DailyVerseDraftBatchResult {
  final List<DailyVerseDraftItemResult> items;
  const DailyVerseDraftBatchResult(this.items);

  int count(DailyVerseDraftOutcome outcome) =>
      items.where((e) => e.outcome == outcome).length;
  int get created => count(DailyVerseDraftOutcome.created);
  int get alreadyExists => count(DailyVerseDraftOutcome.alreadyExists);
  int get conflicts => count(DailyVerseDraftOutcome.conflict);
  int get failed => count(DailyVerseDraftOutcome.failed);
  int get unknown => count(DailyVerseDraftOutcome.unknown);
  bool get needsReconciliation => conflicts > 0 || failed > 0 || unknown > 0;
}

class DailyVerseReconciliationItem {
  final String date;
  final bool workspaceExists;
  final String? workspaceStatus;
  final bool publishedExists;
  final String? publishedStatus;
  final int publishedRevisionCount;
  final List<String> anomalies;

  const DailyVerseReconciliationItem({
    required this.date,
    required this.workspaceExists,
    this.workspaceStatus,
    required this.publishedExists,
    this.publishedStatus,
    this.publishedRevisionCount = 0,
    this.anomalies = const [],
  });
}

class DailyVerseReconciliationResult {
  final List<DailyVerseReconciliationItem> items;
  const DailyVerseReconciliationResult(this.items);

  int get workspaceCount => items.where((e) => e.workspaceExists).length;
  int get publishedCount => items.where((e) => e.publishedExists).length;
  int get anomalyCount => items.where((e) => e.anomalies.isNotEmpty).length;
  Map<String, int> get workspaceStatusCounts {
    final out = <String, int>{};
    for (final item in items.where((e) => e.workspaceExists)) {
      final status = item.workspaceStatus ?? 'missing';
      out[status] = (out[status] ?? 0) + 1;
    }
    return out;
  }
}

// ===========================================================================
// 批次狀態轉移（送 Review / Publish）逐日 receipt。與 Draft 建立同樣「永不中斷、
// 逐筆結果、可安全重試」：跳過已完成、絕不覆寫已完成，單筆失敗不影響其他筆。
// ===========================================================================

enum DailyVerseStageOutcome {
  /// 成功轉移到目標狀態。
  transitioned,

  /// 已在目標狀態（idempotent）→ 略過，不重做（含**絕不重新發佈已發佈日期**）。
  skipped,

  /// 目前狀態不符前置條件（例：publish 時仍為 draft、或 workspace 不存在）→ 不動作。
  conflict,

  /// 逾時；結果未知，重試前必須 reconciliation。
  unknown,

  /// 其他錯誤。
  failed,
}

class DailyVerseStageItemResult {
  final String date;
  final DailyVerseStageOutcome outcome;
  final String message;
  const DailyVerseStageItemResult({
    required this.date,
    required this.outcome,
    this.message = '',
  });
}

/// 一次批次狀態轉移的完整逐日 receipt。單筆逾時/失敗不中斷整批。
class DailyVerseStageBatchResult {
  final List<DailyVerseStageItemResult> items;
  const DailyVerseStageBatchResult(this.items);

  int count(DailyVerseStageOutcome o) =>
      items.where((e) => e.outcome == o).length;
  int get transitioned => count(DailyVerseStageOutcome.transitioned);
  int get skipped => count(DailyVerseStageOutcome.skipped);
  int get conflicts => count(DailyVerseStageOutcome.conflict);
  int get unknown => count(DailyVerseStageOutcome.unknown);
  int get failed => count(DailyVerseStageOutcome.failed);
  bool get needsReconciliation => conflicts > 0 || failed > 0 || unknown > 0;
}

/// **純函式**批次閘門：由「預期日期集合」＋「最新 reconciliation 佐證」推導
/// 送 Review／Publish 是否可安全進行。佐證必須新鮮且完整（涵蓋所有預期日期、
/// 無異常、workspace 皆存在），否則一律 blocked（不可送審／發佈）。
///
/// 復原語義（部分失敗後仍可續作，且絕不覆寫已完成）：
/// - canReview：仍有日期停在 draft（把落單的補送審；其餘已在 review/published 會被服務略過）。
/// - canPublish：已無日期停在 draft，且至少一日在 review（發佈剩餘 review；published 會被略過）。
class DailyVerseStageGate {
  final bool evidenceComplete;
  final bool canReview;
  final bool canPublish;
  final String reason;

  const DailyVerseStageGate({
    required this.evidenceComplete,
    required this.canReview,
    required this.canPublish,
    this.reason = '',
  });

  factory DailyVerseStageGate.evaluate({
    required Set<String> expectedDates,
    required DailyVerseReconciliationResult? evidence,
  }) {
    if (expectedDates.isEmpty) {
      return const DailyVerseStageGate(
        evidenceComplete: false,
        canReview: false,
        canPublish: false,
        reason: '無可操作日期',
      );
    }
    if (evidence == null) {
      return const DailyVerseStageGate(
        evidenceComplete: false,
        canReview: false,
        canPublish: false,
        reason: '尚無 reconciliation 佐證（請先唯讀核對）',
      );
    }
    final byDate = {for (final i in evidence.items) i.date: i};
    final complete = expectedDates.every(
      (d) => byDate[d] != null && byDate[d]!.workspaceExists,
    );
    if (!complete || evidence.anomalyCount > 0) {
      return DailyVerseStageGate(
        evidenceComplete: false,
        canReview: false,
        canPublish: false,
        reason: evidence.anomalyCount > 0
            ? 'reconciliation 有異常，狀態未知（blocked）'
            : 'reconciliation 未涵蓋全部日期（blocked）',
      );
    }
    final statuses = {
      for (final d in expectedDates) byDate[d]!.workspaceStatus,
    };
    final anyDraft = statuses.contains('draft');
    final anyReview = statuses.contains('review');
    return DailyVerseStageGate(
      evidenceComplete: true,
      canReview: anyDraft,
      canPublish: anyReview && !anyDraft,
      reason: '',
    );
  }
}
