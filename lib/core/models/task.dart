class Task {
  final String id;
  final String checklistId;
  final String sectorId;
  final String hospitalId;
  final String inspectorId;
  final String assignedBy;
  final DateTime dueDate;
  final String status; // pending | in_progress | submitted | validated
  final DateTime createdAt;

  const Task({
    required this.id,
    required this.checklistId,
    required this.sectorId,
    required this.hospitalId,
    required this.inspectorId,
    required this.assignedBy,
    required this.dueDate,
    required this.status,
    required this.createdAt,
  });

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'] as String,
        checklistId: json['checklist_id'] as String,
        sectorId: json['sector_id'] as String,
        hospitalId: json['hospital_id'] as String,
        inspectorId: json['inspector_id'] as String,
        assignedBy: json['assigned_by'] as String,
        dueDate: DateTime.parse(json['due_date'] as String),
        status: json['status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'checklist_id': checklistId,
        'sector_id': sectorId,
        'hospital_id': hospitalId,
        'inspector_id': inspectorId,
        'assigned_by': assignedBy,
        'due_date': dueDate.toIso8601String(),
        'status': status,
        'created_at': createdAt.toIso8601String(),
      };

  /// overdue é CALCULADO — não armazenado como status (regra 6.3).
  bool get isOverdue =>
      dueDate.isBefore(DateTime.now()) &&
      status != 'submitted' &&
      status != 'validated';
}
