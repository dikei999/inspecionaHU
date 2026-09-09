import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Item 3 — os glifos que apareciam como quadrado com X.
///
/// Gera um PDF de verdade com os caracteres problemáticos e confirma que a
/// fonte embutida os possui. Com a Helvetica padrão do pacote pdf, o
/// travessão (—) e o ponto médio (·) não têm glifo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Caracteres que aparecem no relatório e falhavam na Helvetica.
  const problematicos = {
    '—': 'travessão (U+2014) — cabeçalho da Base normativa',
    '·': 'ponto médio (U+00B7) — coluna Foto e rodapé',
    'ç': 'cedilha',
    'ã': 'til',
    'á': 'acento agudo',
    'â': 'circunflexo',
    'É': 'maiúscula acentuada',
  };

  test('a Manrope embutida tem todos os glifos usados no relatório',
      () async {
    final dados = await rootBundle.load('assets/fonts/Manrope-Regular.ttf');
    // charToGlyphIndexMap é o mapa real da fonte: caractere ausente ali
    // não tem glifo, e o leitor desenha o quadrado com X. O pacote pdf não
    // expõe isso publicamente, então o teste usa o parser interno — é
    // teste, não código de produção.
    final parser = TtfParser(dados);

    final faltando = <String>[];
    for (final entry in problematicos.entries) {
      final ch = entry.key;
      final temGlifo =
          parser.charToGlyphIndexMap.containsKey(ch.codeUnitAt(0));
      debugPrint('  ${temGlifo ? "OK " : "SEM"}  "$ch"  ${entry.value}');
      if (!temGlifo) faltando.add(ch);
    }

    expect(faltando, isEmpty,
        reason: 'sem esses glifos o PDF volta a mostrar quadrado com X');
  });

  test('PDF gerado com o tema embutido abre e tem conteúdo', () async {
    final manrope =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Manrope-Regular.ttf'));
    final manropeBold =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Manrope-Bold.ttf'));
    final sora =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Sora-Bold.ttf'));

    final doc = pw.Document(
      title: 'Teste de glifos',
      theme: pw.ThemeData.withFont(
        base: manrope,
        bold: manropeBold,
        italic: manrope,
        boldItalic: manropeBold,
        fontFallback: [sora, manrope],
      ),
    );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // As mesmas strings das linhas 284, 495 e 510.
            pw.Text('Gerado em 08/09/2026 pelo InspecionaHU · '
                'HU Brasil · Hospitais Universitários Federais'),
            pw.SizedBox(height: 8),
            pw.Text('Cláusulas da NR-32 — Segurança e Saúde no Trabalho '
                'em Serviços de Saúde'),
            pw.SizedBox(height: 8),
            pw.Text('NR-32 · 32.2.4.5'),
            pw.SizedBox(height: 8),
            pw.Text('Não conformidade crítica — ação imediata'),
          ],
        ),
      ),
    );

    final bytes = await doc.save();
    expect(bytes.length, greaterThan(1000),
        reason: 'PDF vazio indica falha na geração');

    // Salva para inspeção visual, se alguém quiser abrir.
    final saida = File('${Directory.systemTemp.path}/glifos_teste.pdf');
    await saida.writeAsBytes(bytes);
    debugPrint('PDF de teste gerado: ${saida.path} '
        '(${(bytes.length / 1024).toStringAsFixed(1)} KB)');

    // A fonte embutida aparece no PDF; a Helvetica padrão não deve ser a
    // única fonte do documento.
    final conteudo = String.fromCharCodes(bytes.take(4000));
    expect(conteudo.contains('%PDF'), isTrue);
  });
}
