import 'package:flutter_test/flutter_test.dart';
import 'package:inspecionahu/core/models/task.dart';
import 'package:inspecionahu/core/utils/app_date_utils.dart';

Task _t(DateTime prazo, {String status = 'pending'}) => Task(
      id: 'x',
      checklistId: 'c',
      sectorId: 's',
      hospitalId: 'h',
      inspectorId: 'i',
      assignedBy: 'a',
      dueDate: prazo,
      status: status,
      createdAt: DateTime(2026, 1, 1),
    );

DateTime get _hoje {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

void main() {
  group('ocorrência futura NÃO é pendência', () {
    test('prazo daqui a uma semana fica agendada', () {
      final t = _t(_hoje.add(const Duration(days: 7)));
      expect(t.isAgendada, isTrue);
      expect(t.isPendenteHoje, isFalse);
      expect(t.isOverdue, isFalse);
      expect(t.exigeAcao, isFalse,
          reason: 'agendada não pode encher o painel de dívida falsa');
    });

    test('prazo amanhã ainda é agendada', () {
      final t = _t(_hoje.add(const Duration(days: 1)));
      expect(t.isAgendada, isTrue);
      expect(t.exigeAcao, isFalse);
    });
  });

  group('vira pendente ao chegar a data', () {
    test('prazo hoje é pendente, não atrasada', () {
      final t = _t(_hoje);
      expect(t.isPendenteHoje, isTrue);
      expect(t.isOverdue, isFalse,
          reason: 'só fica atrasada depois que o dia passa');
      expect(t.isAgendada, isFalse);
      expect(t.exigeAcao, isTrue);
    });

    test('prazo hoje às 23h59 não é atrasada', () {
      // O bug antigo: comparar com now() marcava como atrasada logo após
      // a meia-noite do próprio dia do prazo.
      final t = _t(DateTime(_hoje.year, _hoje.month, _hoje.day, 23, 59));
      expect(t.isOverdue, isFalse);
      expect(t.isPendenteHoje, isTrue);
    });
  });

  group('atrasada só depois da data', () {
    test('prazo ontem está atrasada', () {
      final t = _t(_hoje.subtract(const Duration(days: 1)));
      expect(t.isOverdue, isTrue);
      expect(t.isAgendada, isFalse);
      expect(t.exigeAcao, isTrue);
    });
  });

  group('respondida e cancelada saem de tudo', () {
    test('enviada não é pendência nem atraso', () {
      final t = _t(_hoje.subtract(const Duration(days: 5)),
          status: 'submitted');
      expect(t.isOverdue, isFalse);
      expect(t.exigeAcao, isFalse);
    });

    test('cancelada com prazo vencido não é atraso', () {
      final t = _t(_hoje.subtract(const Duration(days: 5)),
          status: 'cancelled');
      expect(t.isOverdue, isFalse);
      expect(t.isAgendada, isFalse);
      expect(t.exigeAcao, isFalse);
    });

    test('cancelada futura também não é agendada', () {
      final t = _t(_hoje.add(const Duration(days: 5)), status: 'cancelled');
      expect(t.isAgendada, isFalse);
    });
  });

  group('AppDateUtils.isOverdue segue a mesma regra', () {
    test('prazo hoje não é atraso', () {
      expect(AppDateUtils.isOverdue(_hoje, 'pending'), isFalse);
    });

    test('prazo ontem é atraso', () {
      expect(
        AppDateUtils.isOverdue(
            _hoje.subtract(const Duration(days: 1)), 'pending'),
        isTrue,
      );
    });

    test('cancelada nunca é atraso', () {
      expect(
        AppDateUtils.isOverdue(
            _hoje.subtract(const Duration(days: 3)), 'cancelled'),
        isFalse,
      );
    });
  });
}
