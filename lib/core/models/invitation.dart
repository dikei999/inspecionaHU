/// Convite de vinculação enviado por um Diretor/Supervisor/Super Admin
/// para um usuário sem vínculo (identificado pelo profile_code).
class Invitation {
  final String id;
  final String inviteeId;
  final String inviterId;
  final String? hospitalId;
  final String role; // director | supervisor | inspector
  final List<String> sectorIds;
  final String status; // pending | accepted | declined | cancelled | expired
  final String? message;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? respondedAt;

  // Campos enriquecidos por joins (opcionais).
  final String? inviterName;
  final String? inviteeName;
  final String? hospitalName;

  const Invitation({
    required this.id,
    required this.inviteeId,
    required this.inviterId,
    this.hospitalId,
    required this.role,
    this.sectorIds = const [],
    required this.status,
    this.message,
    required this.createdAt,
    this.expiresAt,
    this.respondedAt,
    this.inviterName,
    this.inviteeName,
    this.hospitalName,
  });

  factory Invitation.fromMap(Map<String, dynamic> map) {
    final rawSectors = map['sector_ids'];
    final sectors = rawSectors is List
        ? rawSectors.map((e) => e.toString()).toList()
        : <String>[];

    // Joins podem vir aninhados (ex.: inviter:profiles!inviter_id(full_name)).
    String? nested(String key, String field) {
      final obj = map[key];
      if (obj is Map && obj[field] != null) return obj[field] as String;
      return null;
    }

    return Invitation(
      id: map['id'] as String,
      inviteeId: map['invitee_id'] as String,
      inviterId: map['inviter_id'] as String,
      hospitalId: map['hospital_id'] as String?,
      role: map['role'] as String,
      sectorIds: sectors,
      status: map['status'] as String,
      message: map['message'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      expiresAt: map['expires_at'] != null
          ? DateTime.parse(map['expires_at'] as String)
          : null,
      respondedAt: map['responded_at'] != null
          ? DateTime.parse(map['responded_at'] as String)
          : null,
      inviterName: (map['inviter_name'] as String?) ?? nested('inviter', 'full_name'),
      inviteeName: (map['invitee_name'] as String?) ?? nested('invitee', 'full_name'),
      hospitalName: (map['hospital_name'] as String?) ?? nested('hospital', 'name'),
    );
  }

  bool get isPending => status == 'pending';
  bool get isExpired =>
      status == 'expired' ||
      (expiresAt != null && expiresAt!.isBefore(DateTime.now()));
}
