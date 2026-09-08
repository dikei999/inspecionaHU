import 'package:flutter_test/flutter_test.dart';
import 'package:inspecionahu/core/models/task.dart';
import 'package:inspecionahu/core/models/task_series.dart';

DateTime get _hoje {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

Task _t({
  required String id,
  required DateTime prazo,
  String? serie,
  int? idx,
  int? total,
  String status = 'pending',
}) =>
    Task(
      id: id,
      checklistId: 'c',
      sectorId: 's',
      hospitalId: 'h',
      inspectorId: 'i',
      assignedBy: 'a',
      dueDate: prazo,
      status: status,
      createdAt: DateTime(2026, 1, 1),
      seriesId: serie,
      seriesIndex: idx,
      seriesTotal: total,
    );

List<TaskGroup> _agrupar(List<Task> ts) => TaskGroup.agrupar(
      ts,
      checklistTitle: (_) => 'Checklist X',
      sectorName: (_) => 'UTI',
    );

void main() {
  group('agrupamento', () {
    test('série de 7 vira UM grupo, não 7', () {
      final ts = List.generate(
        7,
        (i) => _t(
          id: 't$i',
          prazo: _hoje.add(Duration(days: i * 7)),
          serie: 'S1',
          idx: i + 1,
          total: 7,
        ),
      );
      final g = _agrupar(ts);
      expect(g.length, 1);
      expect(g.first.isSerie, isTrue);
      expect(g.first.total, 7);
    });

    test('tarefa avulsa continua card individual', () {
      final g = _agrupar([_t(id: 'a', prazo: _hoje)]);
      expect(g.length, 1);
      expect(g.first.isSerie, isFalse,
          reason: 'avulsa não pode virar série');
      expect(g.first.seriesId, isNull);
    });

    test('séries diferentes não se misturam', () {
      final g = _agrupar([
        _t(id: '1', prazo: _hoje, serie: 'A', idx: 1, total: 2),
        _t(id: '2', prazo: _hoje, serie: 'A', idx: 2, total: 2),
        _t(id: '3', prazo: _hoje, serie: 'B', idx: 1, total: 2),
        _t(id: '4', prazo: _hoje, serie: 'B', idx: 2, total: 2),
        _t(id: '5', prazo: _hoje),
      ]);
      expect(g.length, 3, reason: '2 séries + 1 avulsa');
    });
  });

  group('progresso "2 de 7"', () {
    test('conta só as respondidas', () {
      final ts = [
        _t(id: '1', prazo: _hoje, serie: 'S', idx: 1, total: 3,
            status: 'validated'),
        _t(id: '2', prazo: _hoje, serie: 'S', idx: 2, total: 3,
            status: 'submitted'),
        _t(id: '3', prazo: _hoje.add(const Duration(days: 7)),
            serie: 'S', idx: 3, total: 3),
      ];
      final g = _agrupar(ts).first;
      expect(g.progresso, '2 de 3');
      expect(g.concluida, isFalse);
    });
  });

  group('próxima ocorrência', () {
    test('prefere a que exige ação sobre a agendada', () {
      final ts = [
        _t(id: '1', prazo: _hoje.subtract(const Duration(days: 7)),
            serie: 'S', idx: 1, total: 3, status: 'validated'),
        _t(id: '2', prazo: _hoje, serie: 'S', idx: 2, total: 3),
        _t(id: '3', prazo: _hoje.add(const Duration(days: 7)),
            serie: 'S', idx: 3, total: 3),
      ];
      final g = _agrupar(ts).first;
      expect(g.proxima!.id, '2', reason: 'a de hoje é a que cobra ação');
      expect(g.agendadas, 1);
      expect(g.exigemAcao, 1);
    });

    test('série toda concluída não tem próxima', () {
      final ts = [
        _t(id: '1', prazo: _hoje, serie: 'S', idx: 1, total: 2,
            status: 'validated'),
        _t(id: '2', prazo: _hoje, serie: 'S', idx: 2, total: 2,
            status: 'validated'),
      ];
      final g = _agrupar(ts).first;
      expect(g.proxima, isNull);
      expect(g.concluida, isTrue);
    });
  });

  group('ordenação', () {
    test('série com atraso vem antes da que só tem agendadas', () {
      final g = _agrupar([
        _t(id: 'f1', prazo: _hoje.add(const Duration(days: 3)),
            serie: 'FUTURA', idx: 1, total: 2),
        _t(id: 'f2', prazo: _hoje.add(const Duration(days: 10)),
            serie: 'FUTURA', idx: 2, total: 2),
        _t(id: 'a1', prazo: _hoje.subtract(const Duration(days: 2)),
            serie: 'ATRASADA', idx: 1, total: 2),
        _t(id: 'a2', prazo: _hoje.add(const Duration(days: 5)),
            serie: 'ATRASADA', idx: 2, total: 2),
      ]);
      expect(g.first.seriesId, 'ATRASADA');
    });
  });

  testesContadorSerie();

  group('série futura não cobra ação', () {
    test('série criada hoje, toda no futuro, não exige nada', () {
      final ts = List.generate(
        5,
        (i) => _t(
          id: 't$i',
          prazo: _hoje.add(Duration(days: (i + 1) * 7)),
          serie: 'S',
          idx: i + 1,
          total: 5,
        ),
      );
      final g = _agrupar(ts).first;
      expect(g.exigemAcao, 0, reason: 'nada vence hoje nem venceu');
      expect(g.atrasadas, 0);
      expect(g.agendadas, 5);
    });
  });
}

/// Item 2 — o contador mostrava "0 de 3" depois de responder a primeira de 4.
///
/// O painel do Inspetor consulta só 'pending' e 'in_progress', então as
/// ocorrências já respondidas NÃO chegam na lista. O total precisa vir de
/// series_total, não de tasks.length.
void testesContadorSerie() {
  group('contador da série com lista parcial', () {
    test('primeira de 4 respondida -> "1 de 4", não "0 de 3"', () {
      // O que a consulta do painel devolve: as 3 que sobraram.
      final restantes = [
        _t(id: '2', prazo: _hoje.add(const Duration(days: 7)),
            serie: 'S', idx: 2, total: 4),
        _t(id: '3', prazo: _hoje.add(const Duration(days: 14)),
            serie: 'S', idx: 3, total: 4),
        _t(id: '4', prazo: _hoje.add(const Duration(days: 21)),
            serie: 'S', idx: 4, total: 4),
      ];
      final g = _agrupar(restantes).first;
      expect(g.total, 4, reason: 'total é o tamanho da série');
      expect(g.concluidas, 1, reason: '4 menos as 3 ainda abertas');
      expect(g.progresso, '1 de 4');
    });

    test('três de 4 respondidas -> "3 de 4" e continua sendo série', () {
      final restantes = [
        _t(id: '4', prazo: _hoje.add(const Duration(days: 21)),
            serie: 'S', idx: 4, total: 4),
      ];
      final g = _agrupar(restantes).first;
      expect(g.progresso, '3 de 4');
      expect(g.isSerie, isTrue,
          reason: 'com uma ocorrência restante ainda é série, não avulsa');
    });

    test('lista completa (quadro de gestão) continua batendo', () {
      // O quadro do Diretor traz tudo menos canceladas.
      final todas = [
        _t(id: '1', prazo: _hoje.subtract(const Duration(days: 7)),
            serie: 'S', idx: 1, total: 4, status: 'validated'),
        _t(id: '2', prazo: _hoje, serie: 'S', idx: 2, total: 4),
        _t(id: '3', prazo: _hoje.add(const Duration(days: 7)),
            serie: 'S', idx: 3, total: 4),
        _t(id: '4', prazo: _hoje.add(const Duration(days: 14)),
            serie: 'S', idx: 4, total: 4),
      ];
      final g = _agrupar(todas).first;
      expect(g.total, 4);
      expect(g.concluidas, 1);
      expect(g.progresso, '1 de 4');
    });

    test('série inteira concluída -> "4 de 4"', () {
      final todas = List.generate(
        4,
        (i) => _t(
          id: 't$i',
          prazo: _hoje.subtract(Duration(days: 21 - i * 7)),
          serie: 'S',
          idx: i + 1,
          total: 4,
          status: 'validated',
        ),
      );
      final g = _agrupar(todas).first;
      expect(g.progresso, '4 de 4');
      expect(g.concluida, isTrue);
    });

    test('avulsa sem series_total não quebra', () {
      final g = _agrupar([_t(id: 'a', prazo: _hoje)]).first;
      expect(g.total, 1);
      expect(g.concluidas, 0);
      expect(g.isSerie, isFalse);
    });
  });
}
