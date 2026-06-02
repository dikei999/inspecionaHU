class ChecklistTemplate {
  final String id;
  final String? hospitalId; // null = template global (Super Admin)
  final String title;
  final String? description;
  final String? nr32Category;
  final String scope; // 'global' | 'local'
  final String status;
  final String createdBy;
  final DateTime createdAt;

  const ChecklistTemplate({
    required this.id,
    this.hospitalId,
    required this.title,
    this.description,
    this.nr32Category,
    required this.scope,
    required this.status,
    required this.createdBy,
    required this.createdAt,
  });

  factory ChecklistTemplate.fromJson(Map<String, dynamic> json) =>
      ChecklistTemplate(
        id: json['id'] as String,
        hospitalId: json['hospital_id'] as String?,
        title: json['title'] as String,
        description: json['description'] as String?,
        nr32Category: json['nr32_category'] as String?,
        scope: json['scope'] as String,
        status: json['status'] as String,
        createdBy: json['created_by'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'hospital_id': hospitalId,
        'title': title,
        'description': description,
        'nr32_category': nr32Category,
        'scope': scope,
        'status': status,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
      };

  bool get isGlobal => scope == 'global';
  bool get isActive => status == 'active';
}
