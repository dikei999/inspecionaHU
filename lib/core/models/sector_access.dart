class SectorAccess {
  final String id;
  final String sectorId;
  final String supervisorId;
  final bool canView;
  final bool canEdit;
  final String grantedBy;
  final DateTime createdAt;

  const SectorAccess({
    required this.id,
    required this.sectorId,
    required this.supervisorId,
    required this.canView,
    required this.canEdit,
    required this.grantedBy,
    required this.createdAt,
  });

  factory SectorAccess.fromJson(Map<String, dynamic> json) => SectorAccess(
        id: json['id'] as String,
        sectorId: json['sector_id'] as String,
        supervisorId: json['supervisor_id'] as String,
        canView: json['can_view'] as bool,
        canEdit: json['can_edit'] as bool,
        grantedBy: json['granted_by'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sector_id': sectorId,
        'supervisor_id': supervisorId,
        'can_view': canView,
        'can_edit': canEdit,
        'granted_by': grantedBy,
        'created_at': createdAt.toIso8601String(),
      };
}
