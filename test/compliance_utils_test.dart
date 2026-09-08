import 'package:flutter_test/flutter_test.dart';
import 'package:inspecionahu/core/utils/compliance_utils.dart';

/// Item 3 — havia DUAS fórmulas na mesma tela e elas divergiam.
/// Este teste trava a correta: agregação por item.
void main() {
  group('taxa agregada por item', () {
    test('conformidade simples', () {
      expect(ComplianceUtils.taxa(compliant: 8, nonCompliant: 2), 80.0);
    });

    test('NA fica fora do denominador', () {
      // 5 conformes, 5 não conformes e 90 "não se aplica" = 50%, não 5%.
      final r = ComplianceUtils.agregar([
        {'compliant': 5, 'non_compliant': 5, 'not_applicable': 90},
      ]);
      expect(r.taxa, 50.0);
      expect(r.notApplicable, 90);
    });

    test('sem item avaliável devolve 0 em vez de estourar', () {
      expect(ComplianceUtils.taxa(compliant: 0, nonCompliant: 0), 0.0);
      final r = ComplianceUtils.agregar(const []);
      expect(r.taxa, 0.0);
    });
  });

  group('a divergência que existia', () {
    // Cenário real: uma inspeção pequena e uma grande.
    final reports = [
      {'compliant': 1, 'non_compliant': 1, 'not_applicable': 0,
       'compliance_rate': 50.0},
      {'compliant': 45, 'non_compliant': 5, 'not_applicable': 0,
       'compliance_rate': 90.0},
    ];

    test('agregação por item devolve 88,5%', () {
      final r = ComplianceUtils.agregar(reports);
      expect(r.compliant, 46);
      expect(r.nonCompliant, 6);
      expect(r.taxa, closeTo(88.46, 0.01));
    });

    test('a média das taxas devolveria 70% — 18 pontos de diferença', () {
      // Fórmula ANTIGA do card, reproduzida só para documentar o erro.
      final media = reports
              .map((r) => r['compliance_rate'] as double)
              .reduce((a, b) => a + b) /
          reports.length;
      expect(media, 70.0);

      final correta = ComplianceUtils.agregar(reports).taxa;
      expect((media - correta).abs(), greaterThan(18),
          reason: 'a média dá o mesmo peso a uma inspeção de 2 itens e a '
              'uma de 50');
    });
  });

  group('bate com o donut', () {
    test('a taxa agregada é a mesma que o donut calcula', () {
      final r = ComplianceUtils.agregar([
        {'compliant': 30, 'non_compliant': 10, 'not_applicable': 5},
        {'compliant': 20, 'non_compliant': 40, 'not_applicable': 0},
      ]);
      // Donut: compliant / (compliant + nonCompliant) * 100
      final donut = r.compliant / (r.compliant + r.nonCompliant) * 100;
      expect(r.taxa, donut,
          reason: 'gráfico e número precisam sair da mesma conta');
    });
  });
}
