import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../constants/nr32_clauses.dart';
import '../models/checklist_item.dart';
import '../models/inspection.dart';
import '../models/inspection_response.dart';

/// Dados consolidados de um relatório de inspeção para exportação.
class ReportExportData {
  final Inspection inspection;
  final List<InspectionResponse> responses;
  final Map<String, ChecklistItem> items;
  final String hospitalName;
  final String sectorName;
  final String checklistTitle;
  final String inspectorName;

  const ReportExportData({
    required this.inspection,
    required this.responses,
    required this.items,
    required this.hospitalName,
    required this.sectorName,
    required this.checklistTitle,
    required this.inspectorName,
  });

  int get compliant => responses.where((r) => r.status == 'C').length;
  int get nonCompliant => responses.where((r) => r.status == 'NC').length;
  int get notApplicable => responses.where((r) => r.status == 'NA').length;

  double get complianceRate {
    final total = compliant + nonCompliant;
    if (total == 0) return 0;
    return compliant / total * 100;
  }

  /// Respostas ordenadas pelo order_index do item do checklist,
  /// com desempate por checklistItemId (ordem deterministica).
  List<InspectionResponse> get orderedResponses {
    final list = List<InspectionResponse>.from(responses);
    list.sort((a, b) {
      final ia = items[a.checklistItemId]?.orderIndex ?? 0;
      final ib = items[b.checklistItemId]?.orderIndex ?? 0;
      final cmp = ia.compareTo(ib);
      // Desempate estavel: order_index repetido (ou item removido caindo no
      // fallback 0) nao pode gerar ordem diferente entre telas e exportacoes.
      return cmp != 0 ? cmp : a.checklistItemId.compareTo(b.checklistItemId);
    });
    return list;
  }
}

/// Geração de PDF e Excel do relatório individual de inspeção.
/// Fotos são baixadas via signed URL de 1h do bucket privado
/// inspection-photos; falha em uma foto não impede a exportação.
class ReportExportService {
  ReportExportService._();

  static final _db = Supabase.instance.client;
  static const _bucket = 'inspection-photos';

  static final _dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

  // Cores da identidade visual no espaço do PDF
  static final _pdfPrimary = PdfColor.fromInt(0xFF00448E);
  static final _pdfCompliant = PdfColor.fromInt(0xFF16A34A);
  static final _pdfNonCompliant = PdfColor.fromInt(0xFFDC2626);
  static final _pdfGray = PdfColor.fromInt(0xFF6B7280);
  static final _pdfLightGray = PdfColor.fromInt(0xFFF3F4F6);
  static final _pdfBorder = PdfColor.fromInt(0xFFE5E7EB);

  // ── Fotos: re-assinatura e download ─────────────────────────────────────────

  /// Extrai o path do Storage a partir de uma signed URL salva
  /// (formato .../object/sign/inspection-photos/{path}?token=...).
  static String? storagePathFromPhotoUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      final idx = segments.indexOf(_bucket);
      if (idx == -1 || idx == segments.length - 1) return null;
      return segments.sublist(idx + 1).join('/');
    } catch (_) {
      return null;
    }
  }

  /// Gera uma signed URL nova (1h) a partir da URL salva — a original expira.
  static Future<String?> freshSignedUrl(String storedUrl) async {
    final path = storagePathFromPhotoUrl(storedUrl);
    if (path == null) return null;
    try {
      return await _db.storage.from(_bucket).createSignedUrl(path, 3600);
    } catch (e) {
      debugPrint('[ReportExport] freshSignedUrl falhou: $e');
      return null;
    }
  }

  /// Baixa os bytes de uma foto via signed URL de 1h.
  /// Retorna null em caso de falha (o PDF usa placeholder).
  static Future<Uint8List?> _downloadPhoto(String storedUrl) async {
    try {
      final signedUrl = await freshSignedUrl(storedUrl);
      if (signedUrl == null) return null;

      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(signedUrl));
        final response = await request.close();
        if (response.statusCode != 200) return null;
        final builder = BytesBuilder(copy: false);
        await for (final chunk in response) {
          builder.add(chunk);
        }
        return builder.takeBytes();
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      debugPrint('[ReportExport] download foto falhou: $e');
      return null;
    }
  }

  // ── PDF ─────────────────────────────────────────────────────────────────────

  static Future<Uint8List> buildPdf(ReportExportData data) async {
    final ordered = data.orderedResponses;

    // Numeração humana (1, 2, 3...) na ordem em que os itens são
    // renderizados — não usa o order_index cru do banco.
    final displayNumbers = <String, int>{
      for (var i = 0; i < ordered.length; i++) ordered[i].id: i + 1,
    };

    // Baixa as fotos de TODOS os itens que têm foto (C, NC e NA) antes de
    // montar o documento. Tratamento de erro individual: foto que falhar
    // vira placeholder e não impede a exportação.
    final withPhoto = ordered.where((r) => r.photoUrl != null).toList();
    final photoBytes = <String, Uint8List?>{};
    for (final r in withPhoto) {
      photoBytes[r.id] = await _downloadPhoto(r.photoUrl!);
    }

    // Marca institucional do cabecalho.
    final logoBytes =
        (await rootBundle.load('assets/branding/icon_mark.png'))
            .buffer
            .asUint8List();

    final doc = pw.Document(
      title: 'Relatório de Inspeção NR-32 — ${data.checklistTitle}',
      author: 'InspecionaHU',
    );

    final generatedAt = _dateFmt.format(DateTime.now());

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 44),
        header: (ctx) => _pdfHeader(data, logoBytes),
        footer: (ctx) => _pdfFooter(ctx, generatedAt),
        build: (ctx) => [
          pw.SizedBox(height: 12),
          _pdfMetadata(data),
          pw.SizedBox(height: 14),
          _pdfSummary(data),
          pw.SizedBox(height: 18),
          pw.Text('Itens inspecionados',
              style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: _pdfPrimary)),
          pw.SizedBox(height: 8),
          _pdfItemsTable(data, displayNumbers),
          // Sem seção separada de não conformidades: a tabela de itens já
          // traz status e observação de cada item, e as fotos aparecem em
          // "Evidências fotográficas" (a tabela não comporta imagem).
          if (withPhoto.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            pw.Text('Evidências fotográficas',
                style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: _pdfPrimary)),
            pw.SizedBox(height: 8),
            ...withPhoto.map((r) => _pdfPhotoEvidenceBlock(
                data, r, photoBytes[r.id], displayNumbers[r.id])),
          ],
          ..._pdfNormativeBase(data),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _pdfHeader(ReportExportData data, Uint8List logoBytes) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _pdfBorder, width: 1)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Marca institucional (HU-UFPI/EBSERH)
          pw.Image(pw.MemoryImage(logoBytes), width: 34, height: 34),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(data.hospitalName,
                    style: pw.TextStyle(
                        fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.Text('Relatório de Inspeção NR-32',
                    style: pw.TextStyle(fontSize: 10, color: _pdfGray)),
              ],
            ),
          ),
          pw.Text('InspecionaHU',
              style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: _pdfPrimary)),
        ],
      ),
    );
  }

  static pw.Widget _pdfFooter(pw.Context ctx, String generatedAt) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _pdfBorder, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Gerado em $generatedAt pelo InspecionaHU',
              style: pw.TextStyle(fontSize: 8, color: _pdfGray)),
          pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}',
              style: pw.TextStyle(fontSize: 8, color: _pdfGray)),
        ],
      ),
    );
  }

  static pw.Widget _pdfMetadata(ReportExportData data) {
    final insp = data.inspection;
    final rows = <List<String>>[
      ['Checklist', data.checklistTitle],
      ['Setor', data.sectorName],
      ['Inspetor', data.inspectorName],
      if (insp.startedAt != null)
        ['Iniciada em', _dateFmt.format(insp.startedAt!)],
      if (insp.submittedAt != null)
        ['Enviada em', _dateFmt.format(insp.submittedAt!)],
      if (insp.validatedAt != null)
        ['Validada em', _dateFmt.format(insp.validatedAt!)],
      [
        'Status',
        insp.isValidated
            ? 'Validado'
            : insp.isSubmitted
                ? 'Enviado'
                : 'Rascunho'
      ],
    ];

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _pdfLightGray,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        children: rows
            .map((r) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                  child: pw.Row(
                    children: [
                      pw.SizedBox(
                        width: 90,
                        child: pw.Text(r[0],
                            style:
                                pw.TextStyle(fontSize: 9, color: _pdfGray)),
                      ),
                      pw.Expanded(
                        child: pw.Text(r[1],
                            style: pw.TextStyle(
                                fontSize: 9,
                                fontWeight: pw.FontWeight.bold)),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  static pw.Widget _pdfSummary(ReportExportData data) {
    pw.Widget statBox(String label, String value, PdfColor color) {
      return pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.symmetric(horizontal: 3),
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: color, width: 0.8),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            children: [
              pw.Text(value,
                  style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: color)),
              pw.SizedBox(height: 2),
              pw.Text(label,
                  style: pw.TextStyle(fontSize: 8, color: _pdfGray)),
            ],
          ),
        ),
      );
    }

    final rateColor = data.complianceRate >= 80
        ? _pdfCompliant
        : data.complianceRate >= 60
            ? PdfColor.fromInt(0xFFD97706)
            : _pdfNonCompliant;

    return pw.Row(
      children: [
        statBox('Taxa de conformidade',
            '${data.complianceRate.toStringAsFixed(1)}%', rateColor),
        statBox('Conformes', '${data.compliant}', _pdfCompliant),
        statBox('Não conformes', '${data.nonCompliant}', _pdfNonCompliant),
        statBox('Não se aplica', '${data.notApplicable}', _pdfGray),
      ],
    );
  }

  static pw.Widget _pdfItemsTable(
      ReportExportData data, Map<String, int> displayNumbers) {
    PdfColor statusColor(String? s) => s == 'C'
        ? _pdfCompliant
        : s == 'NC'
            ? _pdfNonCompliant
            : _pdfGray;

    final headerStyle = pw.TextStyle(
        fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white);
    const cellStyle = pw.TextStyle(fontSize: 8.5);

    return pw.Table(
      border: pw.TableBorder.all(color: _pdfBorder, width: 0.5),
      columnWidths: {
        0: const pw.FixedColumnWidth(24),
        1: const pw.FlexColumnWidth(4),
        2: const pw.FixedColumnWidth(34),
        3: const pw.FixedColumnWidth(38),
        4: const pw.FlexColumnWidth(3),
        5: const pw.FixedColumnWidth(34),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _pdfPrimary),
          children: ['Nº', 'Item', 'Status', 'Crítico', 'Observação', 'Foto']
              .map((h) => pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text(h, style: headerStyle),
                  ))
              .toList(),
        ),
        ...data.orderedResponses.map((r) {
          final item = data.items[r.checklistItemId];
          return pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text('${displayNumbers[r.id] ?? '—'}',
                    style: cellStyle),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(item?.description ?? 'Item removido',
                    style: cellStyle),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(r.status ?? '—',
                    style: pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                        color: statusColor(r.status))),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text((item?.isCritical ?? false) ? 'Sim' : 'Não',
                    style: pw.TextStyle(
                        fontSize: 8.5,
                        color: (item?.isCritical ?? false)
                            ? _pdfNonCompliant
                            : _pdfGray)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(r.observation ?? '', style: cellStyle),
              ),
              // Indica que há evidência fotográfica na seção específica
              // (a tabela não comporta imagem).
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(r.photoUrl != null ? 'Sim' : '—',
                    style: pw.TextStyle(
                        fontSize: 8.5,
                        color: r.photoUrl != null ? _pdfPrimary : _pdfGray)),
              ),
            ],
          );
        }),
      ],
    );
  }

  /// Seção "Base normativa": cada referência NR-32 citada neste relatório,
  /// em ordem crescente, com o texto integral da cláusula (nr32_clauses.dart).
  /// É o que torna o relatório um documento de conformidade defensável.
  static List<pw.Widget> _pdfNormativeBase(ReportExportData data) {
    final refs = data.responses
        .map((r) => data.items[r.checklistItemId]?.nr32Reference)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort(_compareNr32Refs);
    if (refs.isEmpty) return [];

    return [
      pw.SizedBox(height: 20),
      pw.Text('Base normativa',
          style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: _pdfPrimary)),
      pw.SizedBox(height: 4),
      pw.Text(
          'Cláusulas da NR-32 — Segurança e Saúde no Trabalho em Serviços '
          'de Saúde citadas pelos itens deste relatório.',
          style: pw.TextStyle(fontSize: 8, color: _pdfGray)),
      pw.SizedBox(height: 8),
      ...refs.map((ref) => pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.only(bottom: 6),
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _pdfBorder, width: 0.5),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('NR-32 · $ref',
                    style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: _pdfPrimary)),
                pw.SizedBox(height: 3),
                pw.Text(
                    nr32Clauses[ref] ??
                        'Texto da cláusula não disponível nesta versão do aplicativo.',
                    style: const pw.TextStyle(fontSize: 8, lineSpacing: 2)),
              ],
            ),
          )),
    ];
  }

  /// Ordena referências NR-32: numéricas primeiro (comparação parte a
  /// parte: 32.5.2 < 32.5.10), depois as do Anexo III em ordem textual.
  static int _compareNr32Refs(String a, String b) {
    final na = _refNumericParts(a);
    final nb = _refNumericParts(b);
    if (na != null && nb != null) {
      for (var i = 0; i < na.length && i < nb.length; i++) {
        final c = na[i].compareTo(nb[i]);
        if (c != 0) return c;
      }
      return na.length.compareTo(nb.length);
    }
    if (na != null) return -1;
    if (nb != null) return 1;
    return a.compareTo(b);
  }

  static List<int>? _refNumericParts(String ref) {
    final nums = <int>[];
    for (final part in ref.split('.')) {
      final n = int.tryParse(part);
      if (n == null) return null;
      nums.add(n);
    }
    return nums;
  }

  /// Bloco de evidência fotográfica de um item (qualquer status: C, NC, NA).
  /// A imagem mantém a orientação original — usa BoxFit.contain dentro de
  /// uma altura máxima, sem forçar proporção de paisagem.
  static pw.Widget _pdfPhotoEvidenceBlock(ReportExportData data,
      InspectionResponse r, Uint8List? photo, int? displayNumber) {
    final item = data.items[r.checklistItemId];
    final status = r.status ?? '—';
    final statusColor = status == 'C'
        ? _pdfCompliant
        : status == 'NC'
            ? _pdfNonCompliant
            : _pdfGray;

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _pdfBorder, width: 0.8),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Foto: largura fixa, altura livre até um teto — preserva retrato.
          pw.Container(
            width: 150,
            constraints: const pw.BoxConstraints(maxHeight: 200),
            alignment: pw.Alignment.topCenter,
            child: photo != null
                ? pw.ClipRRect(
                    horizontalRadius: 4,
                    verticalRadius: 4,
                    child: pw.Image(
                      pw.MemoryImage(photo),
                      fit: pw.BoxFit.contain,
                    ),
                  )
                // Falha no download por signed URL não pode sumir em
                // silêncio: vira placeholder identificando o item.
                : pw.Container(
                    height: 90,
                    padding: const pw.EdgeInsets.all(6),
                    alignment: pw.Alignment.center,
                    decoration: pw.BoxDecoration(
                      color: _pdfLightGray,
                      border: pw.Border.all(color: _pdfGray, width: 0.5),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        pw.Text(
                            'Item ${displayNumber ?? '—'}: foto registrada,',
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(
                                fontSize: 8,
                                fontWeight: pw.FontWeight.bold,
                                color: _pdfGray)),
                        pw.SizedBox(height: 2),
                        pw.Text(
                            'não foi possível baixá-la na exportação. '
                            'A imagem segue armazenada no sistema.',
                            textAlign: pw.TextAlign.center,
                            style:
                                pw.TextStyle(fontSize: 7, color: _pdfGray)),
                      ],
                    ),
                  ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Text(
                        displayNumber != null ? 'Item $displayNumber' : 'Item',
                        style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: _pdfPrimary)),
                    pw.SizedBox(width: 6),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: pw.BoxDecoration(
                        color: statusColor,
                        borderRadius: pw.BorderRadius.circular(3),
                      ),
                      child: pw.Text(status,
                          style: pw.TextStyle(
                              fontSize: 7,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.white)),
                    ),
                    if (item?.isCritical ?? false) ...[
                      pw.SizedBox(width: 4),
                      pw.Text('CRÍTICO',
                          style: pw.TextStyle(
                              fontSize: 7,
                              fontWeight: pw.FontWeight.bold,
                              color: _pdfNonCompliant)),
                    ],
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Text(item?.description ?? 'Item removido',
                    style: const pw.TextStyle(fontSize: 9)),
                if (r.observation != null && r.observation!.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text('Observação: ${r.observation}',
                      style: pw.TextStyle(fontSize: 8, color: _pdfGray)),
                ],
                if (r.photoCapturedAt != null) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                      'Capturada em ${_dateFmt.format(r.photoCapturedAt!)}',
                      style: pw.TextStyle(fontSize: 7.5, color: _pdfGray)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Excel ───────────────────────────────────────────────────────────────────

  /// Gera a planilha (abas Resumo e Itens) e salva em arquivo temporário.
  /// Retorna o path do arquivo .xlsx pronto para compartilhar.
  static Future<File> buildExcelFile(ReportExportData data) async {
    final excel = xls.Excel.createExcel();

    // ── Aba Resumo ────────────────────────────────────────────────────────
    final resumo = excel['Resumo'];
    void addResumoRow(String label, String value) {
      resumo.appendRow([xls.TextCellValue(label), xls.TextCellValue(value)]);
    }

    addResumoRow('Relatório de Inspeção NR-32', '');
    addResumoRow('Hospital', data.hospitalName);
    addResumoRow('Checklist', data.checklistTitle);
    addResumoRow('Setor', data.sectorName);
    addResumoRow('Inspetor', data.inspectorName);
    if (data.inspection.submittedAt != null) {
      addResumoRow('Enviada em', _dateFmt.format(data.inspection.submittedAt!));
    }
    if (data.inspection.validatedAt != null) {
      addResumoRow(
          'Validada em', _dateFmt.format(data.inspection.validatedAt!));
    }
    addResumoRow(
        'Status',
        data.inspection.isValidated
            ? 'Validado'
            : data.inspection.isSubmitted
                ? 'Enviado'
                : 'Rascunho');
    addResumoRow('', '');
    addResumoRow(
        'Taxa de conformidade', '${data.complianceRate.toStringAsFixed(1)}%');
    addResumoRow('Itens conformes (C)', '${data.compliant}');
    addResumoRow('Itens não conformes (NC)', '${data.nonCompliant}');
    addResumoRow('Não se aplica (NA)', '${data.notApplicable}');
    addResumoRow('Total de itens', '${data.responses.length}');
    addResumoRow('', '');
    addResumoRow('Gerado em', _dateFmt.format(DateTime.now()));
    addResumoRow('Gerado por', 'InspecionaHU');

    // ── Aba Itens ─────────────────────────────────────────────────────────
    final itens = excel['Itens'];
    itens.appendRow([
      xls.TextCellValue('Nº'),
      xls.TextCellValue('Item'),
      xls.TextCellValue('Status'),
      xls.TextCellValue('Crítico?'),
      xls.TextCellValue('Observação'),
      xls.TextCellValue('Possui foto?'),
    ]);

    final orderedForExcel = data.orderedResponses;
    for (var i = 0; i < orderedForExcel.length; i++) {
      final r = orderedForExcel[i];
      final item = data.items[r.checklistItemId];
      itens.appendRow([
        // Numeração humana (1, 2, 3...), igual à do PDF.
        xls.IntCellValue(i + 1),
        xls.TextCellValue(item?.description ?? 'Item removido'),
        xls.TextCellValue(r.status ?? '—'),
        xls.TextCellValue((item?.isCritical ?? false) ? 'Sim' : 'Não'),
        xls.TextCellValue(r.observation ?? ''),
        xls.TextCellValue(r.photoUrl != null ? 'Sim' : 'Não'),
      ]);
    }

    // Remove a aba padrão criada automaticamente
    excel.delete('Sheet1');

    final bytes = excel.save();
    if (bytes == null) {
      throw Exception('Falha ao gerar a planilha.');
    }

    final dir = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final file = File('${dir.path}/relatorio_nr32_$stamp.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
