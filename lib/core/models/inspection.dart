class Inspection {
  final String id;
  final String taskId;
  final String checklistId;
  final String sectorId;
  final String hospitalId;
  final String inspectorId;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final DateTime? submittedAt;
  final String overallStatus; // draft | submitted | validated
  final String? notes;
  final String? validatedBy;
  final DateTime? validatedAt;
  final DateTime createdAt;

  const Inspection({
    required this.id,
    required this.taskId,
    required this.checklistId,
    required this.sectorId,
    required this.hospitalId,
    required this.inspectorId,
    this.startedAt,
    this.finishedAt,
    this.submittedAt,
    required this.overallStatus,
    this.notes,
    this.validatedBy,
    this.validatedAt,
    required this.createdAt,
  });

  factory Inspection.fromJson(Map<String, dynamic> json) => Inspection(
        id: json['id'] as String,
        taskId: json['task_id'] as String,
        checklistId: json['checklist_id'] as String,
        sectorId: json['sector_id'] as String,
        hospitalId: json['hospital_id'] as String,
        inspectorId: json['inspector_id'] as String,
        startedAt: json['started_at'] != null
            ? DateTime.parse(json['started_at'] as String)
            : null,
        finishedAt: json['finished_at'] != null
            ? DateTime.parse(json['finished_at'] as String)
            : null,
        submittedAt: json['submitted_at'] != null
            ? DateTime.parse(json['submitted_at'] as String)
            : null,
        overallStatus: json['overall_status'] as String,
        notes: json['notes'] as String?,
        validatedBy: json['validated_by'] as String?,
        validatedAt: json['validated_at'] != null
            ? DateTime.parse(json['validated_at'] as String)
            : null,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'task_id': taskId,
        'checklist_id': checklistId,
        'sector_id': sectorId,
        'hospital_id': hospitalId,
        'inspector_id': inspectorId,
        'started_at': startedAt?.toIso8601String(),
        'finished_at': finishedAt?.toIso8601String(),
        'submitted_at': submittedAt?.toIso8601String(),
        'overall_status': overallStatus,
        'notes': notes,
        'validated_by': validatedBy,
        'validated_at': validatedAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };

  bool get isDraft => overallStatus == 'draft';
  bool get isSubmitted => overallStatus == 'submitted';
  bool get isValidated => overallStatus == 'validated';
  // Validado = bloqueado para edição (regra 6.7)
  bool get isLocked => isValidated;
}
