import 'task.dart';

/// Um grupo de tarefas exibido como UM card.
///
/// Séries recorrentes viram um card só, com progresso e próximo prazo; a
/// tarefa avulsa continua sendo um card individual, sem nenhuma mudança de
/// comportamento. Antes as ocorrências apareciam soltas e uma série de 14
/// datas ocupava 14 cards no painel.
class TaskGroup {
  /// null quando é tarefa avulsa.
  final String? seriesId;

  /// Ocorrências, já ordenadas por data.
  final List<Task> tasks;

  final String checklistTitle;
  final String sectorName;

  const TaskGroup({
    required this.seriesId,
    required this.tasks,
    required this.checklistTitle,
    required this.sectorName,
  });

  bool get isSerie => seriesId != null && tasks.length > 1;

  /// A tarefa que representa o grupo quando ele é avulso.
  Task get unica => tasks.first;

  int get total => tasks.length;
  int get concluidas => tasks.where((t) => t.isRespondida).length;

  /// "2 de 7" — quantas já foram enviadas ou validadas.
  String get progresso => '$concluidas de $total';

  /// Ocorrências que exigem ação hoje (vencidas ou vencendo).
  int get exigemAcao => tasks.where((t) => t.exigeAcao).length;

  int get atrasadas => tasks.where((t) => t.isOverdue).length;
  int get agendadas => tasks.where((t) => t.isAgendada).length;

  /// Próxima ocorrência ainda não respondida — a que interessa ao Inspetor.
  /// Prefere a que já exige ação; sem nenhuma, devolve a agendada mais
  /// próxima. Null quando a série inteira foi concluída.
  Task? get proxima {
    final abertas = tasks.where((t) => !t.isRespondida && !t.isCancelled);
    if (abertas.isEmpty) return null;
    final ordenadas = abertas.toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return ordenadas.firstWhere(
      (t) => t.exigeAcao,
      orElse: () => ordenadas.first,
    );
  }

  bool get concluida => concluidas == total;

  /// Agrupa uma lista de tarefas: série vira um grupo, avulsa vira grupo de
  /// uma só. A ordem de saída coloca primeiro o que exige ação.
  static List<TaskGroup> agrupar(
    List<Task> tasks, {
    required String Function(Task) checklistTitle,
    required String Function(Task) sectorName,
  }) {
    final porSerie = <String, List<Task>>{};
    final avulsas = <Task>[];

    for (final t in tasks) {
      final sid = t.seriesId;
      if (sid == null) {
        avulsas.add(t);
      } else {
        porSerie.putIfAbsent(sid, () => []).add(t);
      }
    }

    final grupos = <TaskGroup>[
      for (final e in porSerie.entries)
        TaskGroup(
          seriesId: e.key,
          tasks: e.value..sort((a, b) => a.dueDate.compareTo(b.dueDate)),
          checklistTitle: checklistTitle(e.value.first),
          sectorName: sectorName(e.value.first),
        ),
      for (final t in avulsas)
        TaskGroup(
          seriesId: null,
          tasks: [t],
          checklistTitle: checklistTitle(t),
          sectorName: sectorName(t),
        ),
    ];

    // Ordem: atrasadas primeiro, depois o que vence hoje, depois o resto
    // por data da próxima ocorrência.
    grupos.sort((a, b) {
      final pa = _peso(a);
      final pb = _peso(b);
      if (pa != pb) return pa.compareTo(pb);
      final da = a.proxima?.dueDate;
      final db = b.proxima?.dueDate;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });

    return grupos;
  }

  static int _peso(TaskGroup g) {
    if (g.atrasadas > 0) return 0;
    if (g.exigemAcao > 0) return 1;
    if (g.concluida) return 3;
    return 2;
  }
}
