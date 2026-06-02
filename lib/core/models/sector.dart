class Sector {
  final String id;
  final String hospitalId;
  final String? ownerSupervisorId;
  final String name;
  final String? description;
  final String? nr32Category;
  final String status;
  final String createdBy;
  final DateTime createdAt;

  const Sector({
    required this.id,
    required this.hospitalId,
    this.ownerSupervisorId,
    required this.name,
    this.description,
    this.nr32Category,
    required this.status,
    required this.createdBy,
    required this.createdAt,
  });

  factory Sector.fromJson(Map<String, dynamic> json) => Sector(
        id: json['id'] as String,
        hospitalId: json['hospital_id'] as String,
        ownerSupervisorId: json['owner_supervisor_id'] as String?,
        name: json['name'] as String,
        description: json['description'] as String?,
        nr32Category: json['nr32_category'] as String?,
        status: json['status'] as String,
        createdBy: json['created_by'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'hospital_id': hospitalId,
        'owner_supervisor_id': ownerSupervisorId,
        'name': name,
        'description': description,
        'nr32_category': nr32Category,
        'status': status,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
      };

  bool get isActive => status == 'active';
}
