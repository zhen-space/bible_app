import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/church.dart';
import '../models/study_content.dart';
import '../models/teacher.dart';

/// Church / Membership 資料存取（Church/Teacher R1）。
///
/// - Student：讀 active churches（Picker）、讀**自己的** membership、建立自己的 pending。
/// - Admin：建立/更新 church（公開欄位）、approve/reject/revoke membership（authoritative）。
/// 授權來源＝`memberships/{uid}`（doc id=uid，Admin-authoritative）；Student 不得 self-approve。
class ChurchRepository {
  ChurchRepository(this._fs);
  final FirebaseFirestore _fs;

  CollectionReference<Map<String, dynamic>> get _churches =>
      _fs.collection('churches');
  CollectionReference<Map<String, dynamic>> get _memberships =>
      _fs.collection('memberships');

  // ---- Churches ----

  /// Picker：只列 active（Inactive 不可作為新申請/發佈 target）。
  Future<List<Church>> fetchActiveChurches() async {
    final s = await _churches.where('active', isEqualTo: true).get();
    return [for (final d in s.docs) Church.fromDoc(d.id, d.data())]
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<Church?> fetchChurch(String id) async {
    final d = await _churches.doc(id).get();
    return d.exists ? Church.fromDoc(d.id, d.data()!) : null;
  }

  /// Admin：全部 churches（含 inactive）。
  Future<List<Church>> fetchAllChurches() async {
    final s = await _churches.get();
    return [for (final d in s.docs) Church.fromDoc(d.id, d.data())]
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Admin：寫入 church **公開欄位**（私有資料另寫 churches/{id}/private/admin）。
  Future<void> saveChurch(Church c) =>
      _churches.doc(c.id).set(c.toPublicMap(), SetOptions(merge: true));

  Future<void> setChurchActive(String id, bool active) =>
      _churches.doc(id).set({'active': active}, SetOptions(merge: true));

  // ---- Membership ----

  /// 讀自己的 membership（無 doc = no membership）。
  Future<Membership?> fetchMembership(String uid) async {
    final d = await _memberships.doc(uid).get();
    return d.exists ? Membership.fromDoc(d.id, d.data()!) : null;
  }

  /// 目前授權快照（供 authorized universe）。
  Future<StudentAuth> currentAuth(String uid) async =>
      StudentAuth.from(await fetchMembership(uid));

  /// Student：提出 pending 申請（rules 另檢查 target church active、status==pending、
  /// 不得自設 reviewed/active）。doc id=uid → 一人一 membership 記錄。
  Future<void> requestMembership(String uid, String churchId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _memberships.doc(uid).set(
      Membership(
        uid: uid,
        churchId: churchId,
        status: MembershipStatus.pending,
        requestedAt: now,
      ).toMap(),
    );
  }

  // Admin authoritative transitions（＋稽核 history）。
  Future<void> approveMembership(String uid, String adminEmail) =>
      _setStatus(uid, MembershipStatus.active, adminEmail);
  Future<void> rejectMembership(String uid, String adminEmail) =>
      _setStatus(uid, MembershipStatus.rejected, adminEmail);
  Future<void> revokeMembership(String uid, String adminEmail) =>
      _setStatus(uid, MembershipStatus.revoked, adminEmail);

  Future<void> _setStatus(
      String uid, MembershipStatus to, String adminEmail) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final ref = _memberships.doc(uid);
    final prev = await ref.get();
    final from = prev.data()?['status'];
    final update = <String, dynamic>{
      'status': to.name,
      'reviewed_at': now,
      'reviewed_by': adminEmail,
      if (to == MembershipStatus.rejected) 'rejected_at': now,
      if (to == MembershipStatus.revoked) 'revoked_at': now,
    };
    await ref.set(update, SetOptions(merge: true));
    await ref.collection('history').add({
      'from': from,
      'to': to.name,
      'at': now,
      'by': adminEmail,
      'church_id': prev.data()?['church_id'],
    });
  }

  /// Admin：待審 membership 佇列。
  Future<List<Membership>> pendingMemberships() async {
    final s = await _memberships
        .where('status', isEqualTo: MembershipStatus.pending.name)
        .get();
    return [for (final d in s.docs) Membership.fromDoc(d.id, d.data())];
  }
}

/// 老師專區結構讀取（授權 aware）。Book/Chapter 皆 audience-gated，避免結構洩漏。
class TeacherRepository {
  TeacherRepository(this._fs);
  final FirebaseFirestore _fs;

  CollectionReference<Map<String, dynamic>> get _books =>
      _fs.collection('teacher_books');
  static const _pub = 'published';

  Future<List<TeacherBook>> fetchAuthorizedBooks(StudentAuth auth) async {
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    docs.addAll((await _books
            .where('status', isEqualTo: _pub)
            .where('audience', isEqualTo: Audience.public.name)
            .get())
        .docs);
    if (auth.hasChurch) {
      docs.addAll((await _books
              .where('status', isEqualTo: _pub)
              .where('audience', isEqualTo: Audience.church.name)
              .where('allowed_church_ids', arrayContains: auth.activeChurchId)
              .get())
          .docs);
    }
    final seen = <String>{};
    final out = <TeacherBook>[];
    for (final d in docs) {
      if (!seen.add(d.id)) continue;
      final b = TeacherBook.fromDoc(d.id, d.data());
      if (b.authorizedFor(auth.activeChurchId)) out.add(b);
    }
    out.sort((a, b) => a.order.compareTo(b.order));
    return out;
  }

  Future<List<TeacherChapter>> fetchAuthorizedChapters(
      String bookId, StudentAuth auth) async {
    final col = _books.doc(bookId).collection('chapters');
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    docs.addAll((await col
            .where('status', isEqualTo: _pub)
            .where('audience', isEqualTo: Audience.public.name)
            .get())
        .docs);
    if (auth.hasChurch) {
      docs.addAll((await col
              .where('status', isEqualTo: _pub)
              .where('audience', isEqualTo: Audience.church.name)
              .where('allowed_church_ids', arrayContains: auth.activeChurchId)
              .get())
          .docs);
    }
    final seen = <String>{};
    final out = <TeacherChapter>[];
    for (final d in docs) {
      if (!seen.add(d.id)) continue;
      final c = TeacherChapter.fromDoc(d.id, d.data());
      if (c.authorizedFor(auth.activeChurchId)) out.add(c);
    }
    out.sort((a, b) => a.order.compareTo(b.order));
    return out;
  }
}

/// 已儲存的研讀內容（relationship only；§14）。open 時走 authorization-aware live resolve。
class SavedStudyContentRepository {
  SavedStudyContentRepository(this._fs);
  final FirebaseFirestore _fs;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _fs.collection('users').doc(uid).collection('saved_study_content');

  Future<void> save(String uid, String contentId) => _col(uid).doc(contentId).set({
        'content_id': contentId,
        'saved_at': DateTime.now().millisecondsSinceEpoch,
      });

  Future<void> unsave(String uid, String contentId) =>
      _col(uid).doc(contentId).delete();

  /// 只回 relationship（contentId + savedAt），**不含 payload**。
  Future<List<String>> savedIds(String uid) async {
    final s = await _col(uid).get();
    final rows = [
      for (final d in s.docs)
        (id: d.id, at: (d.data()['saved_at'] as int?) ?? 0)
    ]..sort((a, b) => b.at.compareTo(a.at));
    return [for (final r in rows) r.id];
  }
}
