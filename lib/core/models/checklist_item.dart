class ChecklistItem {
  final String id;
  final String checklistId;
  final int orderIndex;
  final String description;
  final String? nr32Reference;
  final String criticality; // 'normal' | 'critical'
  final bool requiresPhoto;
  // Regra fixa: NC = observação obrigatória, C/NA = opcional (sem campo requires_observation)
  final String status;
  final DateTime? lastModifiedAt;
  final String? lastModifiedBy;
  final DateTime createdAt;

  const ChecklistItem({
    required this.id,
    required this.checklistId,
    required this.orderIndex,
    required this.description,
    this.nr32Reference,
    required this.criticality,
    required this.requiresPhoto,
    required this.status,
    this.lastModifiedAt,
    this.lastModifiedBy,
    required this.createdAt,
  });

  factory ChecklistItem.fromJson(Map<String, dynamic> json) => ChecklistItem(
        id: json['id'] as String,
        checklistId: json['checklist_id'] as String,
        orderIndex: json['order_index'] as int,
        description: json['description'] as String,
        nr32Reference: json['nr32_reference'] as String?,
        criticality: json['criticality'] as String,
        requiresPhoto: json['requires_photo'] as bool,
        status: json['status'] as String,
        lastModifiedAt: json['last_modified_at'] != null
            ? DateTime.parse(json['last_modified_at'] as String)
            : null,
        lastModifiedBy: json['last_modified_by'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'checklist_id': checklistId,
        'order_index': orderIndex,
        'description': description,
        'nr32_reference': nr32Reference,
        'criticality': criticality,
        'requires_photo': requiresPhoto,
        'status': status,
        'last_modified_at': lastModifiedAt?.toIso8601String(),
        'last_modified_by': lastModifiedBy,
        'created_at': createdAt.toIso8601String(),
      };

  bool get isCritical => criticality == 'critical';
  bool get isActive => status == 'active';
}
