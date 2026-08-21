import 'package:cloud_firestore/cloud_firestore.dart';

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
  FirebaseFirestore get _fs => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _questions =>
      _fs.collection('questions');

  CollectionReference<Map<String, dynamic>> _following(String uid) =>
      _fs.collection('users').doc(uid).collection('following');

  CollectionReference<Map<String, dynamic>> _saved(String uid) =>
      _fs.collection('users').doc(uid).collection('saved_questions');

  // ---- 提問（使用者）----

  Future<void> submitQuestion({
    required String uid,
    required String authorName,
    required String title,
    required String body,
    required String category,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _questions.add({
      'uid': uid,
      'author': authorName,
      'title': title,
      'body': body,
      'category': category,
      'status': 'pending',
      // published ≠ approved：核准/回答不等於發布；唯有管理者明確發布，
      // 學生端才能取得。預設 false。
      'published': false,
      'featured': false,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<Question?> getQuestion(String id) async {
    final d = await _questions.doc(id).get();
    if (!d.exists) return null;
    return Question.fromDoc(d.id, d.data()!);
  }

  /// **學生端可取得的內容＝只有已發布（published）者。**
  /// approved/reviewed 不算 published；沒有已發布資料就回空清單（不得回答）。
  /// 另加 isAnswered 防呆：即使誤設 published，未回答的也不外流。
  /// featured 置頂、其餘依更新時間新到舊。
  Future<List<Question>> publishedQuestions({String? category}) async {
    final snap =
        await _questions.where('published', isEqualTo: true).get();
    final list = snap.docs
        .map((d) => Question.fromDoc(d.id, d.data()))
        .where((q) => q.isAnswered)
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

  /// 發布／取消發布（管理者）。發布後學生端才取得得到；取消發布立即撤下。
  /// approved/回答不會自動發布——這是刻意分離的獨立動作。
  Future<void> setPublished(String id, bool published) =>
      _questions.doc(id).update({
        'published': published,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

  /// 儲存／更新回答。更新時把「舊回答」推進 answer_versions（回答更新紀錄），
  /// 並把問題設為已審核（approved）。**注意：approved ≠ published**——
  /// 回答不會自動發布給學生端，需管理者另外呼叫 setPublished 才會外流。
  Future<void> saveAnswer({
    required Question question,
    required String content,
    required List<String> scriptures,
    required List<String> tags,
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
  });

  bool get isAnswered => answer != null;

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
      );
}

class QaAnswer {
  final String content;
  final List<String> scriptures; // 引用經文（節位字串，可跳轉）
  final List<String> tags;
  final int answeredAt;
  final int updatedAt;

  const QaAnswer({
    required this.content,
    required this.scriptures,
    required this.tags,
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
        answeredAt: m['answered_at'] as int? ?? m['edited_at'] as int? ?? 0,
        updatedAt: m['updated_at'] as int? ?? m['edited_at'] as int? ?? 0,
      );
}
