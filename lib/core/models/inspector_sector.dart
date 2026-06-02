class InspectorSector {
  final String id;
  final String inspectorId;
  final String sectorId;
  final String assignedBy;
  final String status;
  final DateTime createdAt;

  const InspectorSector({
    required this.id,
    required this.inspectorId,
    required this.sectorId,
    required this.assignedBy,
    required this.status,
    required this.createdAt,
  });

  factory InspectorSector.fromJson(Map<String, dynamic> json) =>
      InspectorSector(
        id: json['id'] as String,
        inspectorId: json['inspector_id'] as String,
        sectorId: json['sector_id'] as String,
        assignedBy: json['assigned_by'] as String,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'inspector_id': inspectorId,
        'sector_id': sectorId,
        'assigned_by': assignedBy,
        'status': status,
        'created_at': createdAt.toIso8601String(),
      };

  bool get isActive => status == 'active';
}
