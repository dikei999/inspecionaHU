/// Cálculo da taxa de conformidade — fonte ÚNICA para todo o app.
///
/// Existiam duas fórmulas na mesma tela, que divergiam:
///
///   • o donut somava os itens de todas as inspeções e dividia
///     C / (C + NC);
///   • o card fazia a MÉDIA das compliance_rate de cada relatório.
///
/// A média das taxas está errada: ela dá o mesmo peso a uma inspeção de 2
/// itens e a uma de 50. Com C=1/NC=1 numa e C=45/NC=5 na outra, a média
/// devolve 70,0% e a agregação por item devolve 88,5% — 18,5 pontos de
/// diferença no mesmo conjunto de dados.
///
/// A taxa correta é a agregada por ITEM, que é também a que a NR-32 espera:
/// a conformidade do hospital é a proporção de itens conformes entre os
/// itens avaliados, não a média de porcentagens de relatórios.
///
/// NA (não se aplica) fica fora do denominador — item que não se aplica não
/// é conformidade nem falha.
class ComplianceUtils {
  ComplianceUtils._();

  /// Taxa agregada por item, de 0 a 100. Devolve 0 quando não há item
  /// avaliável (só NA, ou nenhuma inspeção).
  static double taxa({required int compliant, required int nonCompliant}) {
    final avaliados = compliant + nonCompliant;
    if (avaliados <= 0) return 0;
    return compliant / avaliados * 100;
  }

  /// Soma os itens de uma lista de linhas de `reports` e devolve a taxa
  /// agregada junto dos totais que alimentam o donut.
  ///
  /// Uma única passada: as telas usavam o mesmo laço para somar os itens e
  /// ainda faziam a média das taxas em paralelo, que era a origem da
  /// divergência.
  static ({double taxa, int compliant, int nonCompliant, int notApplicable})
      agregar(Iterable<Map<String, dynamic>> reports) {
    var c = 0, nc = 0, na = 0;
    for (final r in reports) {
      c += (r['compliant'] as num? ?? 0).toInt();
      nc += (r['non_compliant'] as num? ?? 0).toInt();
      na += (r['not_applicable'] as num? ?? 0).toInt();
    }
    return (
      taxa: taxa(compliant: c, nonCompliant: nc),
      compliant: c,
      nonCompliant: nc,
      notApplicable: na,
    );
  }
}
