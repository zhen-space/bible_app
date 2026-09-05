import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/church.dart';
import '../models/managed_content.dart';

/// 疑問 Q&A（白板「六、疑問 Q&A」）——**全人工，無 AI**。
///
/// 使用者提問 → 進待審 → 管理者（使用者本人）審核 → 親自回答。
/// Firestore：
/// - `questions/{qid}`：問題本體＋回答（回答含引用經文、標籤、更新紀錄）
/// - `users/{uid}/following/{qid}`：我追蹤的問題（含已讀時間，做「有新回答」提示）
/// - `users/{uid}/saved_questions/{qid}`：我收藏的問題
///
/// 為避免 Firestore 複合索引，列表查詢都用單一欄位（status 或 category 之一），
/// 其餘排序／過濾在用戶端做。內容（問題、回答）一律由人撰寫。
class QaService {
  QaService([FirebaseFirestore? fs]) : _fs = fs ?? FirebaseFirestore.instance;
  final FirebaseFirestore _fs;

  CollectionReference<Map<String, dynamic>> get _questions =>
      _fs.collection('questions');

  CollectionReference<Map<String, dynamic>> _following(String uid) =>
      _fs.collection('users').doc(uid).collection('following');

  CollectionReference<Map<String, dynamic>> _saved(String uid) =>
      _fs.collection('users').doc(uid).collection('saved_questions');

  // ---- 提問（使用者）----

  Future<String> submitQuestion({
    required String uid,
    required String authorName,
    required String title,
    required String body,
    required String category,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final ref = await _questions.add({
      'uid': uid,
      'author': authorName,
      'title': title,
      'body': body,
      'category': category,
      'status': 'pending',
      // published ≠ approved：核准/回答不等於發布；唯有管理者明確發布，
      // 學生端才能取得。預設 false。Pending question **本身不是 retrieval source**。
      'published': false,
      'featured': false,
      'created_at': now,
      'updated_at': now,
    });
    return ref.id;
  }

  /// #9 統一提問入口，回傳三種結果之一：
  /// - `answered`：在 Published approved 語料找到相符（回 matches 供顯示回答依據）。
  /// - `insufficient_approved_content`：找不到，**不得生成一般回答**。
  /// - `pending_question_created`：使用者選擇送出未回答問題（回 pendingQuestionId）。
  ///
  /// 只做檢索（無模型知識／Web／LLM）。呼叫端先 `ask`，若 insufficient 再由使用者
  /// 決定是否 `submitQuestion` → 之後以回傳 id 包成 pendingQuestionCreated。
  Future<QaAskResult> ask(String query,
      {String? category,
      StudentAuth? auth,
      bool activeChurchHasTeacherArea = false}) async {
    final r = await retrieveApproved(query,
        category: category,
        auth: auth,
        activeChurchHasTeacherArea: activeChurchHasTeacherArea);
    if (r.insufficientApprovedContent) {
      return const QaAskResult(QaOutcome.insufficientApprovedContent);
    }
    return QaAskResult(QaOutcome.answered, answers: r.matches);
  }

  Future<Question?> getQuestion(String id) async {
    final d = await _questions.doc(id).get();
    if (!d.exists) return null;
    return Question.fromDoc(d.id, d.data()!);
  }

  /// **學生端可取得的內容＝只有已發布（published）且授權者。**
  /// approved/reviewed 不算 published；沒有已發布資料就回空清單（不得回答）。
  /// 另加 isAnswered 防呆：即使誤設 published，未回答的也不外流。
  /// **Church-sourced answer confidentiality（B17/B20）**：以 [auth] 過濾 audience——
  /// public 全可；church 僅 Active Membership churchId ∈ allowedChurchIds；
  /// missing/internal audience → fail-closed（不外流）。rules 為真正邊界，此為防禦性同源過濾。
  /// featured 置頂、其餘依更新時間新到舊。
  Future<List<Question>> publishedQuestions(
      {String? category,
      StudentAuth? auth,
      bool activeChurchHasTeacherArea = false}) async {
    final snap =
        await _questions.where('published', isEqualTo: true).get();
    final activeChurch = auth?.activeChurchId;
    final list = snap.docs
        .map((d) => Question.fromDoc(d.id, d.data()))
        .where((q) =>
            q.isAnswered &&
            q.studentReadable(activeChurch,
                activeChurchHasTeacherArea: activeChurchHasTeacherArea))
        .toList();
    final filtered = category == null || category.isEmpty
        ? list
        : list.where((q) => q.category == category).toList();
    filtered.sort((a, b) {
      if (a.featured != b.featured) return a.featured ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return filtered;
  }

  /// #9 檢索安全：**只在已發布（Published）approved 內容上做純關鍵字比對。**
  /// 禁止模型自身知識／Web Search／一般 LLM fallback（本服務不含任何生成路徑）。
  /// 待審（pending）／退回（rejected）／未發布的問答**永不進入檢索語料**。
  /// 沒有相符 → 回傳 `insufficientApprovedContent`（呼叫端據此顯示，不得以任何
  /// 未經核准/未發布內容或 AI 回答代替）。
  Future<QaRetrievalResult> retrieveApproved(String query,
      {String? category,
      StudentAuth? auth,
      bool activeChurchHasTeacherArea = false}) async {
    final q = query.trim();
    if (q.isEmpty) return const QaRetrievalResult([]);
    // 語料 = 只有 Published（且已回答、**且對本使用者授權**）的問答。
    final corpus = await publishedQuestions(
        category: category,
        auth: auth,
        activeChurchHasTeacherArea: activeChurchHasTeacherArea);
    final words =
        q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final matches = corpus.where((question) {
      final hay = [
        question.title,
        question.body,
        question.answer?.content ?? '',
        question.answer?.tags.join(' ') ?? '',
      ].join(' ');
      return hay.contains(q) || words.any(hay.contains);
    }).toList();
    return QaRetrievalResult(matches);
  }

  /// 管理者用：已回答（approved）但**尚未發布**的佇列，供管理者發布。
  /// 非學生端可見來源。
  Future<List<Question>> awaitingPublishQuestions() async {
    final snap =
        await _questions.where('status', isEqualTo: 'approved').get();
    return snap.docs
        .map((d) => Question.fromDoc(d.id, d.data()))
        .where((q) => q.isAnswered && !q.published)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// 我提出的問題（含待審／退回，讓提問者看得到狀態）。
  Future<List<Question>> myQuestions(String uid) async {
    final snap = await _questions.where('uid', isEqualTo: uid).get();
    final list =
        snap.docs.map((d) => Question.fromDoc(d.id, d.data())).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// 待審佇列（管理者）。
  Future<List<Question>> pendingQuestions() async {
    final snap = await _questions.where('status', isEqualTo: 'pending').get();
    final list =
        snap.docs.map((d) => Question.fromDoc(d.id, d.data())).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  // ---- 審核與回答（管理者）----

  Future<void> approveQuestion(String id) =>
      _questions.doc(id).update({'status': 'approved'});

  Future<void> rejectQuestion(String id) =>
      _questions.doc(id).update({'status': 'rejected'});

  Future<void> setFeatured(String id, bool featured) =>
      _questions.doc(id).update({'featured': featured});

  /// 取消發布（管理者）：立即撤下，學生端讀不到。audience 欄位保留（下次發布會重推導）。
  Future<void> unpublish(String id) => _questions.doc(id).update({
        'published': false,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

  /// 發布（管理者）：**同時寫入由 AnswerSource 推導出的 serving audience**（B18/B19）。
  /// 管理員不得手動放寬；audience/allowedChurchIds 一律由呼叫端以 [deriveAudience]
  /// 於「發布前重新驗證的 live source」推導後帶入。church 空交集不得走到這裡（呼叫端擋）。
  Future<void> publishAnswer(String id,
          {required Audience audience,
          required List<String> allowedChurchIds,
          List<String> requiredCapabilities = const []}) =>
      _questions.doc(id).update({
        'published': true,
        'audience': audience.name,
        'allowed_church_ids':
            audience == Audience.church ? allowedChurchIds : const [],
        'required_capabilities': requiredCapabilities,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

  /// 相容保留：僅供測試/舊路徑取消發布用。發布請走 [publishAnswer]。
  Future<void> setPublished(String id, bool published) => published
      ? throw StateError('發布請走 publishAnswer（需帶推導後的 audience）')
      : unpublish(id);

  /// 儲存／更新回答。更新時把「舊回答」推進 answer_versions（回答更新紀錄），
  /// 並把問題設為已審核（approved）。**注意：approved ≠ published**——
  /// 回答不會自動發布給學生端，需管理者另外呼叫 setPublished 才會外流。
  Future<void> saveAnswer({
    required Question question,
    required String content,
    required List<String> scriptures,
    required List<String> tags,
    List<AnswerSource> sources = const [],
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final old = question.answer;
    final data = <String, dynamic>{
      'status': 'approved',
      'updated_at': now,
      'answer': {
        'content': content,
        'scriptures': scriptures,
        'tags': tags,
        // #9：回答保存所依據的 source content IDs + versions，前台可取得回答依據。
        'sources': [for (final s in sources) s.toMap()],
        'answered_at': old?.answeredAt ?? now,
        'updated_at': now,
      },
    };
    if (old != null) {
      // 保留舊版本（更新紀錄）
      data['answer_versions'] = FieldValue.arrayUnion([
        {
          'content': old.content,
          'scriptures': old.scriptures,
          'tags': old.tags,
          'edited_at': old.updatedAt,
        }
      ]);
    }
    await _questions.doc(question.id).update(data);
  }

  // ---- 追蹤（問題追蹤通知：用「已讀時間」做未讀提示）----

  Future<void> followQuestion(String uid, String qid) => _following(uid)
      .doc(qid)
      .set({'followed_at': DateTime.now().millisecondsSinceEpoch, 'seen_at': 0});

  Future<void> unfollowQuestion(String uid, String qid) =>
      _following(uid).doc(qid).delete();

  /// 標記某追蹤問題「已讀到此更新時間」（進入詳情時呼叫）。
  Future<void> markFollowSeen(String uid, String qid, int seenAt) async {
    final doc = _following(uid).doc(qid);
    if ((await doc.get()).exists) {
      await doc.update({'seen_at': seenAt});
    }
  }

  /// 我追蹤的問題（qid → 已讀時間）。
  Future<Map<String, int>> followingMap(String uid) async {
    final snap = await _following(uid).get();
    return {for (final d in snap.docs) d.id: (d.data()['seen_at'] as int? ?? 0)};
  }

  // ---- 收藏 ----

  Future<void> saveQuestion(String uid, String qid) => _saved(uid)
      .doc(qid)
      .set({'saved_at': DateTime.now().millisecondsSinceEpoch});

  Future<void> unsaveQuestion(String uid, String qid) =>
      _saved(uid).doc(qid).delete();

  Future<Set<String>> savedIds(String uid) async {
    final snap = await _saved(uid).get();
    return snap.docs.map((d) => d.id).toSet();
  }
}

/// Q&A 分類（爭議＝有不同立場、需謹慎的題目）。
const List<String> kQaCategories = ['神學', '生活', '爭議', '其他'];

/// Answer serving audience 推導結果（B9/B10）。**由 AnswerSource 自動推導，管理員不得放寬。**
class DerivedAnswerAudience {
  final Audience audience;
  final List<String> allowedChurchIds; // church 時＝所有 church source 的交集
  final bool publishable;
  final String? blockReason; // publishable==false 時的原因（供 UI 顯示）
  // 學生需其 Active Church 具備的 capability 聯集（Teacher Area 來源→['teacher_area']）。
  final List<String> requiredCapabilities;

  const DerivedAnswerAudience({
    required this.audience,
    required this.allowedChurchIds,
    required this.publishable,
    this.blockReason,
    this.requiredCapabilities = const [],
  });

  /// 所有 source 的 requiredCapabilities 聯集（deterministic 排序）。
  static List<String> _capsOf(List<AnswerSource> sources) {
    final s = <String>{};
    for (final x in sources) {
      s.addAll(x.requiredCapabilities);
    }
    final l = s.toList()..sort();
    return l;
  }

  /// 發布前**單一 managed source 重新驗證**（純函式，可測；B13/B27）。
  /// [livePublished]＝該 source 現在是否為 Published mirror（adminGetContentPublished != null）；
  /// 回傳問題字串（可顯示）或 null（通過）。順序：不 Published → 版本漂移 → Internal。
  static String? sourceProblem({
    required String label,
    required int citedVersion,
    required bool livePublished,
    required int? liveVersion,
    required Audience? liveAudience,
  }) {
    if (!livePublished) {
      return '$label：目前不是 Published（可能被退回／封存／刪除）';
    }
    if (liveVersion != citedVersion) {
      return '$label：回答依據已更新，引用 v$citedVersion，但目前正式版本為 v$liveVersion';
    }
    if (liveAudience == null || liveAudience == Audience.internal) {
      return '$label：目前為 Internal，不可作為學生 Q&A 發布依據';
    }
    return null;
  }

  /// 純函式推導（可測，無 IO）：
  /// - 任一 source access=='internal' → **不可發布**（Internal 不得作學生依據，B6）。
  /// - 無 church source → Public。
  /// - 有 church source → Church，allowedChurchIds＝所有 church source allowedChurchIds 的**交集**；
  ///   交集為空 → **不可發布**（B10：不存在能同時合法存取全部來源的學生）。
  /// scripture / public source 不縮小 audience。空 sources → Public（純經文或無依據）。
  static DerivedAnswerAudience derive(List<AnswerSource> sources) {
    final managed = sources.where((s) => s.kind == 'study_content').toList();
    if (managed.any((s) => s.access == 'internal')) {
      return const DerivedAnswerAudience(
          audience: Audience.public,
          allowedChurchIds: [],
          publishable: false,
          blockReason: 'Internal 內容不可作為學生 Q&A 發布依據，請移除或更換。');
    }
    final caps = _capsOf(sources);
    final church = managed.where((s) => s.access == 'church').toList();
    if (church.isEmpty) {
      // Teacher Area 來源必為 church audience（有 allowed_church_ids），因此不會落在
      // 純 public 分支；capability 只可能與 church 併存。防禦性：若無 church 但仍帶
      // capability（不應發生），視為不可發布（避免 public answer 帶 teacher_area gate）。
      if (caps.isNotEmpty) {
        return const DerivedAnswerAudience(
            audience: Audience.public,
            allowedChurchIds: [],
            publishable: false,
            blockReason: 'Teacher Area 來源必須有對應教會範圍，無法發布為公開。');
      }
      return const DerivedAnswerAudience(
          audience: Audience.public, allowedChurchIds: [], publishable: true);
    }
    // 交集
    Set<String>? inter;
    for (final s in church) {
      final ids = s.allowedChurchIds.toSet();
      inter = inter == null ? ids : inter.intersection(ids);
    }
    final list = (inter ?? <String>{}).toList()..sort();
    if (list.isEmpty) {
      return const DerivedAnswerAudience(
          audience: Audience.church,
          allowedChurchIds: [],
          publishable: false,
          blockReason: '所選 Church sources 沒有共同可閱讀的教會，無法發布。');
    }
    return DerivedAnswerAudience(
        audience: Audience.church,
        allowedChurchIds: list,
        publishable: true,
        requiredCapabilities: caps);
  }
}

/// #9 檢索結果。[matches] 只含 Published approved 內容；空＝
/// **insufficient_approved_content**（呼叫端顯示「目前沒有已核准的解答」，
/// 並可讓使用者送出 Pending Question；不得以任何未發布內容/AI 代替）。
class QaRetrievalResult {
  final List<Question> matches;
  const QaRetrievalResult(this.matches);
  bool get insufficientApprovedContent => matches.isEmpty;
}

/// #9 提問三態結果（trusted backend / service 層 enforce，非只 client）。
enum QaOutcome { answered, insufficientApprovedContent, pendingQuestionCreated }

class QaAskResult {
  final QaOutcome outcome;

  /// answered：相符的 Published approved 問答（含 answer、source scriptures/sources）。
  final List<Question> answers;

  /// pending_question_created：新建的待答問題 id。
  final String? pendingQuestionId;

  const QaAskResult(this.outcome,
      {this.answers = const [], this.pendingQuestionId});

  /// 使用者送出未回答問題後的結果。
  factory QaAskResult.pending(String id) =>
      QaAskResult(QaOutcome.pendingQuestionCreated, pendingQuestionId: id);
}

class Question {
  final String id;
  final String uid;
  final String author;
  final String title;
  final String body;
  final String category;
  final String status; // pending / approved / rejected（審核狀態）
  final bool published; // 是否發布給學生端（approved≠published，預設 false）
  final bool featured;
  final int createdAt;
  final int updatedAt;
  final QaAnswer? answer;
  final List<QaAnswer> answerVersions; // 歷史版本（不含目前）
  // Q&A serving 授權（Church/Teacher R1 B18）：由 AnswerSource 於發布時推導，
  // **管理員不得手動放寬**。null＝尚未發布/未推導（學生端 fail-closed）。
  final Audience? audience;
  final List<String> allowedChurchIds;
  // 學生需其 Active Church 具備的 capability（Teacher Area 來源→['teacher_area']）。
  final List<String> requiredCapabilities;

  const Question({
    required this.id,
    required this.uid,
    required this.author,
    required this.title,
    required this.body,
    required this.category,
    required this.status,
    this.published = false,
    required this.featured,
    required this.createdAt,
    required this.updatedAt,
    required this.answer,
    required this.answerVersions,
    this.audience,
    this.allowedChurchIds = const [],
    this.requiredCapabilities = const [],
  });

  bool get isAnswered => answer != null;

  /// 學生端可讀（授權，非只 published）：published 且（public，或 church 且
  /// activeChurchId ∈ allowedChurchIds）**且**滿足 requiredCapabilities。
  /// [activeChurchHasTeacherArea]＝目前 Active Church 是否具 teacher_area capability
  /// （§B7；由呼叫端以 authoritative membership→capability 提供）。missing/internal → fail-closed。
  bool studentReadable(String? activeChurchId,
      {bool activeChurchHasTeacherArea = false}) {
    if (!published) return false;
    // audience gate
    final audienceOk = audience == Audience.public ||
        (audience == Audience.church &&
            activeChurchId != null &&
            allowedChurchIds.contains(activeChurchId));
    if (!audienceOk) return false; // internal / null / 未授權 church → fail-closed
    // capability gate（Teacher Area）
    if (requiredCapabilities.contains('teacher_area') &&
        !activeChurchHasTeacherArea) {
      return false;
    }
    return true;
  }

  factory Question.fromDoc(String id, Map<String, dynamic> m) => Question(
        id: id,
        uid: m['uid'] as String? ?? '',
        author: m['author'] as String? ?? '',
        title: m['title'] as String? ?? '',
        body: m['body'] as String? ?? '',
        category: m['category'] as String? ?? '其他',
        status: m['status'] as String? ?? 'pending',
        published: m['published'] as bool? ?? false,
        featured: m['featured'] as bool? ?? false,
        createdAt: m['created_at'] as int? ?? 0,
        updatedAt: m['updated_at'] as int? ?? 0,
        answer: m['answer'] == null
            ? null
            : QaAnswer.fromMap((m['answer'] as Map).cast<String, dynamic>()),
        answerVersions: ((m['answer_versions'] as List?) ?? const [])
            .map((e) => QaAnswer.fromMap((e as Map).cast<String, dynamic>()))
            .toList(),
        audience: Audience.fromName(m['audience'] as String?),
        allowedChurchIds: ((m['allowed_church_ids'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        requiredCapabilities:
            ((m['required_capabilities'] as List?) ?? const [])
                .map((e) => e.toString())
                .toList(),
      );
}

class QaAnswer {
  final String content;
  final List<String> scriptures; // 引用經文（節位字串，可跳轉）
  final List<String> tags;
  final List<AnswerSource> sources; // #9：回答依據（content id + version）
  final int answeredAt;
  final int updatedAt;

  const QaAnswer({
    required this.content,
    required this.scriptures,
    required this.tags,
    this.sources = const [],
    required this.answeredAt,
    required this.updatedAt,
  });

  factory QaAnswer.fromMap(Map<String, dynamic> m) => QaAnswer(
        content: m['content'] as String? ?? '',
        scriptures: ((m['scriptures'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        tags: ((m['tags'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        sources: ((m['sources'] as List?) ?? const [])
            .map((e) => AnswerSource.fromMap((e as Map).cast<String, dynamic>()))
            .toList(),
        answeredAt: m['answered_at'] as int? ?? m['edited_at'] as int? ?? 0,
        updatedAt: m['updated_at'] as int? ?? m['edited_at'] as int? ?? 0,
      );
}
