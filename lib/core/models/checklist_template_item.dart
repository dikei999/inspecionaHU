class ChecklistTemplateItem {
  final String id;
  final String templateId;
  final int orderIndex;
  final String description;
  final String? nr32Reference;
  final String criticality; // 'normal' | 'critical'
  final bool requiresPhoto;
  final DateTime createdAt;

  const ChecklistTemplateItem({
    required this.id,
    required this.templateId,
    required this.orderIndex,
    required this.description,
    this.nr32Reference,
    required this.criticality,
    required this.requiresPhoto,
    required this.createdAt,
  });

  factory ChecklistTemplateItem.fromJson(Map<String, dynamic> json) =>
      ChecklistTemplateItem(
        id: json['id'] as String,
        templateId: json['template_id'] as String,
        orderIndex: json['order_index'] as int,
        description: json['description'] as String,
        nr32Reference: json['nr32_reference'] as String?,
        criticality: json['criticality'] as String,
        requiresPhoto: json['requires_photo'] as bool,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'template_id': templateId,
        'order_index': orderIndex,
        'description': description,
        'nr32_reference': nr32Reference,
        'criticality': criticality,
        'requires_photo': requiresPhoto,
        'created_at': createdAt.toIso8601String(),
      };

  bool get isCritical => criticality == 'critical';
}
