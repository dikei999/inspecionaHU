class AuditLog {
  final String id;
  final String userId;
  final String? hospitalId;
  final String action; // ex: 'user.linked', 'checklist.created', 'inspection.submitted'
  final String entityType; // ex: 'profile', 'checklist', 'inspection', 'sector'
  final String entityId;
  final Map<String, dynamic>? details;
  final DateTime createdAt;

  const AuditLog({
    required this.id,
    required this.userId,
    this.hospitalId,
    required this.action,
    required this.entityType,
    required this.entityId,
    this.details,
    required this.createdAt,
  });

  factory AuditLog.fromJson(Map<String, dynamic> json) => AuditLog(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        hospitalId: json['hospital_id'] as String?,
        action: json['action'] as String,
        entityType: json['entity_type'] as String,
        entityId: json['entity_id'] as String,
        details: json['details'] as Map<String, dynamic>?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  // AuditLog é apenas INSERT — sem toJson para update/delete (regra 7.16)
  Map<String, dynamic> toInsertJson() => {
        'user_id': userId,
        'hospital_id': hospitalId,
        'action': action,
        'entity_type': entityType,
        'entity_id': entityId,
        'details': details,
      };
}
