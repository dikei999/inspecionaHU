class Checklist {
  final String id;
  final String sectorId;
  final String hospitalId;
  final String title;
  final String frequency; // daily | weekly | biweekly | monthly | custom
  final List<String>? customDays; // ['mon','wed','fri'] — só quando frequency='custom'
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final String status;
  final String createdBy;
  final DateTime createdAt;

  /// OBSOLETO: o arquivamento passou para a inspeção — quem alimenta os
  /// indicadores é o relatório, não o formulário. Mantido apenas para ler
  /// dados já gravados; não é mais usado na interface.
  final DateTime? archivedAt;
  final String? archivedBy;

  /// EXCLUSÃO em soft delete (regra do projeto: nunca DELETE). Sai das
  /// listas e não recebe tarefa nova, mas as inspeções já feitas por ele
  /// continuam íntegras e legíveis.
  final DateTime? deletedAt;
  final String? deletedBy;

  const Checklist({
    required this.id,
    required this.sectorId,
    required this.hospitalId,
    required this.title,
    required this.frequency,
    this.customDays,
    this.periodStart,
    this.periodEnd,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    this.archivedAt,
    this.archivedBy,
    this.deletedAt,
    this.deletedBy,
  });

  factory Checklist.fromJson(Map<String, dynamic> json) => Checklist(
        id: json['id'] as String,
        sectorId: json['sector_id'] as String,
        hospitalId: json['hospital_id'] as String,
        title: json['title'] as String,
        frequency: json['frequency'] as String,
        customDays: (json['custom_days'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList(),
        periodStart: json['period_start'] != null
            ? DateTime.parse(json['period_start'] as String)
            : null,
        periodEnd: json['period_end'] != null
            ? DateTime.parse(json['period_end'] as String)
            : null,
        status: json['status'] as String,
        createdBy: json['created_by'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        archivedAt: json['archived_at'] != null
            ? DateTime.parse(json['archived_at'] as String)
            : null,
        archivedBy: json['archived_by'] as String?,
        deletedAt: json['deleted_at'] != null
            ? DateTime.parse(json['deleted_at'] as String)
            : null,
        deletedBy: json['deleted_by'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sector_id': sectorId,
        'hospital_id': hospitalId,
        'title': title,
        'frequency': frequency,
        'custom_days': customDays,
        'period_start': periodStart?.toIso8601String(),
        'period_end': periodEnd?.toIso8601String(),
        'status': status,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
        'archived_at': archivedAt?.toIso8601String(),
        'archived_by': archivedBy,
        'deleted_at': deletedAt?.toIso8601String(),
        'deleted_by': deletedBy,
      };

  bool get isActive => status == 'active';

  /// Excluído em soft delete: fora das listas, sem tarefa nova. As
  /// inspeções já feitas por ele continuam valendo.
  bool get isDeleted => deletedAt != null;

  /// Em operação: ativo E não excluído. É o que gera tarefa nova.
  bool get isOperational => isActive && !isDeleted;
}
