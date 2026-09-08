/// Geração das datas de uma série de tarefas recorrentes.
///
/// Tudo acontece no ato da atribuição: o app calcula as datas e insere uma
/// linha em `tasks` para cada uma. Não há agendamento no servidor nem job em
/// segundo plano — a recorrência é materializada de uma vez.
///
/// Lógica pura, sem Supabase e sem Flutter, para ser fácil de conferir.
class TaskSeriesUtils {
  TaskSeriesUtils._();

  /// Teto de ocorrências por série. Acima disso a atribuição vira um despejo
  /// de tarefas que ninguém consegue administrar, e o quadro do Inspetor
  /// fica ilegível.
  static const int maxOcorrencias = 60;

  /// Mapa dos códigos de dia usados em `AppConstants.weekDays` para o
  /// `DateTime.weekday` (1 = segunda … 7 = domingo).
  static const Map<String, int> _diaSemana = {
    'mon': DateTime.monday,
    'tue': DateTime.tuesday,
    'wed': DateTime.wednesday,
    'thu': DateTime.thursday,
    'fri': DateTime.friday,
    'sat': DateTime.saturday,
    'sun': DateTime.sunday,
  };

  /// Datas previstas entre [inicio] e [fim], inclusive, para a [frequencia].
  ///
  /// - `daily`    — todo dia
  /// - `weekly`   — a cada 7 dias, a partir de [inicio]
  /// - `biweekly` — a cada 14 dias
  /// - `monthly`  — mesmo dia do mês seguinte, com ajuste para meses curtos
  ///   (31/01 mensal cai em 28/02 ou 29/02, não transborda para março)
  /// - `custom`   — só nos dias da semana de [customDays]
  ///
  /// A lista sai ordenada e limitada a [maxOcorrencias]. Use
  /// [excedeuLimite] para saber se houve corte.
  static List<DateTime> gerarDatas({
    required DateTime inicio,
    required DateTime fim,
    required String frequencia,
    List<String> customDays = const [],
  }) {
    final d0 = DateTime(inicio.year, inicio.month, inicio.day);
    final dF = DateTime(fim.year, fim.month, fim.day);
    if (dF.isBefore(d0)) return const [];

    final datas = <DateTime>[];

    switch (frequencia) {
      case 'daily':
        for (var d = d0;
            !d.isAfter(dF) && datas.length < maxOcorrencias;
            d = d.add(const Duration(days: 1))) {
          datas.add(d);
        }

      case 'weekly':
      case 'biweekly':
        final passo = frequencia == 'weekly' ? 7 : 14;
        for (var d = d0;
            !d.isAfter(dF) && datas.length < maxOcorrencias;
            d = d.add(Duration(days: passo))) {
          datas.add(d);
        }

      case 'monthly':
        var i = 0;
        while (datas.length < maxOcorrencias) {
          final d = _somarMeses(d0, i);
          if (d.isAfter(dF)) break;
          datas.add(d);
          i++;
        }

      case 'custom':
        final alvos = customDays
            .map((c) => _diaSemana[c])
            .whereType<int>()
            .toSet();
        if (alvos.isEmpty) return const [];
        for (var d = d0;
            !d.isAfter(dF) && datas.length < maxOcorrencias;
            d = d.add(const Duration(days: 1))) {
          if (alvos.contains(d.weekday)) datas.add(d);
        }

      default:
        // Frequência desconhecida: uma única ocorrência na data inicial.
        // Melhor que devolver lista vazia e o Diretor achar que salvou.
        datas.add(d0);
    }

    return datas;
  }

  /// Quantas datas existiriam sem o teto de [maxOcorrencias]. Serve para
  /// avisar o Diretor de que a série foi cortada.
  static bool excedeuLimite({
    required DateTime inicio,
    required DateTime fim,
    required String frequencia,
    List<String> customDays = const [],
  }) {
    final d0 = DateTime(inicio.year, inicio.month, inicio.day);
    final dF = DateTime(fim.year, fim.month, fim.day);
    if (dF.isBefore(d0)) return false;

    final dias = dF.difference(d0).inDays + 1;
    final estimativa = switch (frequencia) {
      'daily' => dias,
      'weekly' => (dias / 7).ceil(),
      'biweekly' => (dias / 14).ceil(),
      'monthly' => (dias / 28).ceil(),
      'custom' => customDays.isEmpty
          ? 0
          : ((dias / 7).ceil() * customDays.length),
      _ => 1,
    };
    return estimativa > maxOcorrencias;
  }

  /// Soma [meses] a [base] preservando o dia quando possível.
  /// 31/01 + 1 mês = 28/02 (ou 29/02 em ano bissexto), nunca 03/03.
  static DateTime _somarMeses(DateTime base, int meses) {
    final totalMes = base.month - 1 + meses;
    final ano = base.year + totalMes ~/ 12;
    final mes = totalMes % 12 + 1;
    final ultimoDia = DateTime(ano, mes + 1, 0).day;
    return DateTime(ano, mes, base.day > ultimoDia ? ultimoDia : base.day);
  }
}
