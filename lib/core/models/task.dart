class Task {
  final String id;
  final String? taskCode; // OS-YYYY-NNNNN — gerado por trigger no banco
  final String checklistId;
  final String sectorId;
  final String hospitalId;
  final String inspectorId;
  final String assignedBy;
  final DateTime dueDate;
  final String status; // pending | in_progress | submitted | validated | cancelled
  final DateTime createdAt;

  /// Série recorrente: tarefas criadas na mesma atribuição compartilham o
  /// series_id. NULL = tarefa avulsa. Não há agendamento no servidor — as
  /// ocorrencias sao todas criadas no ato da atribuicao.
  final String? seriesId;
  final int? seriesIndex;
  final int? seriesTotal;

  const Task({
    required this.id,
    this.taskCode,
    required this.checklistId,
    required this.sectorId,
    required this.hospitalId,
    required this.inspectorId,
    required this.assignedBy,
    required this.dueDate,
    required this.status,
    required this.createdAt,
    this.seriesId,
    this.seriesIndex,
    this.seriesTotal,
  });

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'] as String,
        taskCode: json['task_code'] as String?,
        checklistId: json['checklist_id'] as String,
        sectorId: json['sector_id'] as String,
        hospitalId: json['hospital_id'] as String,
        inspectorId: json['inspector_id'] as String,
        assignedBy: json['assigned_by'] as String,
        dueDate: DateTime.parse(json['due_date'] as String),
        status: json['status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        seriesId: json['series_id'] as String?,
        seriesIndex: (json['series_index'] as num?)?.toInt(),
        seriesTotal: (json['series_total'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'task_code': taskCode,
        'checklist_id': checklistId,
        'sector_id': sectorId,
        'hospital_id': hospitalId,
        'inspector_id': inspectorId,
        'assigned_by': assignedBy,
        'due_date': dueDate.toIso8601String(),
        'status': status,
        'created_at': createdAt.toIso8601String(),
        'series_id': seriesId,
        'series_index': seriesIndex,
        'series_total': seriesTotal,
      };

  /// Rótulo curto da tarefa — usa o código de OS quando disponível;
  /// cai para os 8 primeiros caracteres do UUID em bases sem a migration
  /// migration_task_code.sql aplicada.
  String get displayCode =>
      (taskCode != null && taskCode!.isNotEmpty)
          ? taskCode!
          : '#${id.substring(0, 8)}';

  /// overdue é CALCULADO — não armazenado como status (regra 6.3).
  bool get isOverdue =>
      dueDate.isBefore(DateTime.now()) &&
      status != 'submitted' &&
      status != 'validated' &&
      status != 'cancelled';

  /// Pertence a uma série recorrente.
  bool get isRecorrente => seriesId != null && seriesTotal != null;

  /// Rótulo de posição na série, ex.: "3 de 14". Null se avulsa.
  String? get seriesLabel =>
      isRecorrente ? '$seriesIndex de $seriesTotal' : null;

  /// Cancelada não aparece em lista de trabalho nem conta como pendência.
  bool get isCancelled => status == 'cancelled';

  /// Já respondida: não pode ser cancelada junto com a série.
  bool get isRespondida => status == 'submitted' || status == 'validated';
}
