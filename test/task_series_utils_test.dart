import 'package:flutter_test/flutter_test.dart';
import 'package:inspecionahu/core/utils/task_series_utils.dart';

void main() {
  group('gerarDatas', () {
    test('diária inclui início e fim', () {
      final d = TaskSeriesUtils.gerarDatas(
        inicio: DateTime(2026, 1, 1),
        fim: DateTime(2026, 1, 5),
        frequencia: 'daily',
      );
      expect(d.length, 5);
      expect(d.first, DateTime(2026, 1, 1));
      expect(d.last, DateTime(2026, 1, 5));
    });

    test('semanal salta 7 dias', () {
      final d = TaskSeriesUtils.gerarDatas(
        inicio: DateTime(2026, 1, 1),
        fim: DateTime(2026, 1, 29),
        frequencia: 'weekly',
      );
      expect(d.map((e) => e.day).toList(), [1, 8, 15, 22, 29]);
    });

    test('quinzenal salta 14 dias', () {
      final d = TaskSeriesUtils.gerarDatas(
        inicio: DateTime(2026, 1, 1),
        fim: DateTime(2026, 2, 1),
        frequencia: 'biweekly',
      );
      expect(d.length, 3);
    });

    test('mensal a partir de 31/01 não transborda para março', () {
      final d = TaskSeriesUtils.gerarDatas(
        inicio: DateTime(2026, 1, 31),
        fim: DateTime(2026, 4, 30),
        frequencia: 'monthly',
      );
      expect(d[0], DateTime(2026, 1, 31));
      expect(d[1], DateTime(2026, 2, 28)); // 2026 não é bissexto
      expect(d[2], DateTime(2026, 3, 31));
      expect(d[3], DateTime(2026, 4, 30));
    });

    test('personalizado só nos dias escolhidos', () {
      // 2026-01-01 é quinta-feira.
      final d = TaskSeriesUtils.gerarDatas(
        inicio: DateTime(2026, 1, 1),
        fim: DateTime(2026, 1, 14),
        frequencia: 'custom',
        customDays: ['mon', 'wed'],
      );
      for (final data in d) {
        expect([DateTime.monday, DateTime.wednesday], contains(data.weekday));
      }
      expect(d.length, 4); // 5, 7, 12, 14
    });

    test('respeita o teto de 60 ocorrências', () {
      final d = TaskSeriesUtils.gerarDatas(
        inicio: DateTime(2026, 1, 1),
        fim: DateTime(2026, 12, 31),
        frequencia: 'daily',
      );
      expect(d.length, TaskSeriesUtils.maxOcorrencias);
    });

    test('fim antes do início devolve vazio', () {
      final d = TaskSeriesUtils.gerarDatas(
        inicio: DateTime(2026, 5, 10),
        fim: DateTime(2026, 5, 1),
        frequencia: 'daily',
      );
      expect(d, isEmpty);
    });

    test('custom sem dias devolve vazio', () {
      final d = TaskSeriesUtils.gerarDatas(
        inicio: DateTime(2026, 1, 1),
        fim: DateTime(2026, 1, 31),
        frequencia: 'custom',
      );
      expect(d, isEmpty);
    });
  });

  group('excedeuLimite', () {
    test('ano inteiro diário excede', () {
      expect(
        TaskSeriesUtils.excedeuLimite(
          inicio: DateTime(2026, 1, 1),
          fim: DateTime(2026, 12, 31),
          frequencia: 'daily',
        ),
        isTrue,
      );
    });

    test('uma semana diária não excede', () {
      expect(
        TaskSeriesUtils.excedeuLimite(
          inicio: DateTime(2026, 1, 1),
          fim: DateTime(2026, 1, 7),
          frequencia: 'daily',
        ),
        isFalse,
      );
    });
  });
}
