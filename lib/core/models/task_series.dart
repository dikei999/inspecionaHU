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

  /// Pertence a uma serie. Usa o tamanho DECLARADO, nao o carregado: com
  /// 3 de 4 ja respondidas, a lista traz uma tarefa so e o grupo deixaria
  /// de ser serie, voltando a virar card avulso no meio do caminho.
  bool get isSerie => seriesId != null && total > 1;

  /// A tarefa que representa o grupo quando ele é avulso.
  Task get unica => tasks.first;

  /// Tamanho REAL da série, vindo de tasks.series_total.
  ///
  /// NÃO usar tasks.length: a lista carregada pode conter só um recorte —
  /// o painel do Inspetor, por exemplo, consulta apenas 'pending' e
  /// 'in_progress'. Ao responder a primeira de 4 ocorrências, a série
  /// passava a carregar 3 tarefas com 0 respondidas e o card exibia
  /// "0 de 3" em vez de "1 de 4".
  int get total {
    final declarado = tasks.first.seriesTotal;
    if (declarado != null && declarado >= tasks.length) return declarado;
    return tasks.length;
  }

  /// Concluídas = total da série menos as que ainda estão abertas.
  ///
  /// Derivar do total evita depender de as ocorrências respondidas terem
  /// sido carregadas: se a consulta trouxe só as abertas, as que faltam
  /// são exatamente as já concluídas.
  int get concluidas {
    final abertas = tasks.where((t) => !t.isRespondida && !t.isCancelled).length;
    final calculado = total - abertas;
    // Piso em zero e teto no total: uma consulta que traga tudo continua
    // batendo, e nenhum recorte estranho gera número negativo.
    if (calculado < 0) return 0;
    if (calculado > total) return total;
    return calculado;
  }

  /// "2 de 7" — quantas já foram concluídas, sobre o tamanho da série.
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
