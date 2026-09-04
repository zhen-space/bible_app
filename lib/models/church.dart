/// Church / Membership domain（Church/Teacher R1 backend contract §2.1–§2.2）。
///
/// - `churches/{churchId}`：**只放公開欄位**（Picker 用）。
/// - `churches/{churchId}/private/capabilities`：Church-specific capability；Student
///   只能讀自己 Active Membership 對應的這一份，不得枚舉其他 Church。
/// - 其他 `churches/{churchId}/private/*`：Student 永不讀。
/// - `memberships/{uid}`（**doc id = uid**）：使用者唯一 membership 記錄 →
///   結構性保證「一人至多一 membership、至多一個 Active」。狀態由 Admin-authoritative
///   write 控制；Student 只能建立自己的 pending、不得 self-approve。
/// ⛔ 內容（教會名稱/地區）由使用者親填，不 hardcode。
library;

/// Membership 狀態。缺 document ＝ no membership（非授權；不為 none 造假）。
/// 未知值 → null（fail-closed：視為無有效 membership）。
enum MembershipStatus {
  pending,
  active,
  rejected,
  revoked;

  static MembershipStatus? fromName(String? s) {
    for (final m in MembershipStatus.values) {
      if (m.name == s) return m;
    }
    return null;
  }

  String get label => switch (this) {
        MembershipStatus.pending => '審核中',
        MembershipStatus.active => '已加入',
        MembershipStatus.rejected => '未通過',
        MembershipStatus.revoked => '已解除',
      };
}

/// Church 的**公開表示**（Picker）。私有欄位不在此 model。
class Church {
  final String id;
  final String name;
  final String region;
  final bool active;
  final int createdAt;

  const Church({
    required this.id,
    this.name = '',
    this.region = '',
    this.active = false,
    this.createdAt = 0,
  });

  factory Church.fromDoc(String id, Map<String, dynamic> m) => Church(
        id: id,
        name: (m['name'] as String?) ?? '',
        region: (m['region'] as String?) ?? '',
        active: m['active'] == true,
        createdAt: (m['created_at'] as int?) ?? 0,
      );

  /// 只寫公開欄位（私有資料另寫 churches/{id}/private/admin）。
  Map<String, dynamic> toPublicMap() => {
        'church_id': id,
        'name': name,
        'region': region,
        'active': active,
        'created_at': createdAt,
      };
}

/// Church 的私有 capability 文件。
///
/// 正式位置：`churches/{churchId}/private/capabilities`。
/// 缺文件、缺欄位、型別錯誤或未知欄位一律不授權（fail closed）。這個 capability
/// 只決定「老師專區入口是否存在」，不取代 Teacher/Study Content 的 audience authorization。
class ChurchCapabilities {
  final String churchId;
  final bool teacherArea;

  const ChurchCapabilities({
    required this.churchId,
    this.teacherArea = false,
  });

  factory ChurchCapabilities.disabled([String churchId = '']) =>
      ChurchCapabilities(churchId: churchId);

  factory ChurchCapabilities.fromDoc(
          String churchId, Map<String, dynamic> m) =>
      ChurchCapabilities(
        churchId: churchId,
        teacherArea: m['teacher_area'] == true,
      );

  Map<String, dynamic> toMap() => {'teacher_area': teacherArea};
}

/// 使用者的 membership 記錄（doc id = uid）。
class Membership {
  final String uid;
  final String churchId;
  final MembershipStatus? status; // null ＝ 無有效狀態（fail-closed）
  final int requestedAt;
  final int reviewedAt;
  final String reviewedBy;
  final int rejectedAt;
  final int revokedAt;

  const Membership({
    required this.uid,
    this.churchId = '',
    this.status,
    this.requestedAt = 0,
    this.reviewedAt = 0,
    this.reviewedBy = '',
    this.rejectedAt = 0,
    this.revokedAt = 0,
  });

  bool get isActive => status == MembershipStatus.active;

  /// **授權用**：只有 Active 才回 churchId，其餘（含 pending/rejected/revoked/null）回 null。
  String? get activeChurchId => isActive && churchId.isNotEmpty ? churchId : null;

  factory Membership.fromDoc(String uid, Map<String, dynamic> m) => Membership(
        uid: uid,
        churchId: (m['church_id'] as String?) ?? '',
        status: MembershipStatus.fromName(m['status'] as String?),
        requestedAt: (m['requested_at'] as int?) ?? 0,
        reviewedAt: (m['reviewed_at'] as int?) ?? 0,
        reviewedBy: (m['reviewed_by'] as String?) ?? '',
        rejectedAt: (m['rejected_at'] as int?) ?? 0,
        revokedAt: (m['revoked_at'] as int?) ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'church_id': churchId,
        'status': status?.name,
        'requested_at': requestedAt,
        'reviewed_at': reviewedAt,
        'reviewed_by': reviewedBy,
        'rejected_at': rejectedAt,
        'revoked_at': revokedAt,
      };
}

/// 目前使用者的授權快照（供 repository 組 Authorized Universe）。
/// `activeChurchId==null` ＝ 無 Church 授權（只可讀 public）。
class StudentAuth {
  final String? activeChurchId;
  const StudentAuth(this.activeChurchId);
  static const none = StudentAuth(null);

  factory StudentAuth.from(Membership? m) => StudentAuth(m?.activeChurchId);
  bool get hasChurch => activeChurchId != null;
}
