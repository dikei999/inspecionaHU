import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/checklist_item.dart';
import '../../../core/models/inspection.dart';
import '../../../core/models/inspection_response.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/services/report_export_service.dart';
import '../../../widgets/charts.dart';
import '../../../widgets/status_badge.dart';
import '../../auth/providers/auth_provider.dart';

class RelatorioIndividualScreen extends StatefulWidget {
  final String inspectionId;

  const RelatorioIndividualScreen({super.key, required this.inspectionId});

  @override
  State<RelatorioIndividualScreen> createState() =>
      _RelatorioIndividualScreenState();
}

class _RelatorioIndividualScreenState
    extends State<RelatorioIndividualScreen> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  bool _validating = false;
  bool _exportingPdf = false;
  bool _exportingExcel = false;

  Inspection? _inspection;
  Map<String, ChecklistItem> _items = {};
  List<InspectionResponse> _responses = [];
  String? _inspectorName;
  String? _sectorName;
  String? _checklistTitle;
  String? _hospitalName;

  int get _compliant =>
      _responses.where((r) => r.status == 'C').length;
  int get _nonCompliant =>
      _responses.where((r) => r.status == 'NC').length;
  int get _notApplicable =>
      _responses.where((r) => r.status == 'NA').length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final inspData = await _db
          .from('inspections')
          .select()
          .eq('id', widget.inspectionId)
          .single();
      final inspection = Inspection.fromJson(inspData);

      final responsesData = await _db
          .from('inspection_responses')
          .select()
          .eq('inspection_id', widget.inspectionId);

      final itemIds = responsesData
          .map((r) => r['checklist_item_id'] as String)
          .toList();
      Map<String, ChecklistItem> itemMap = {};
      if (itemIds.isNotEmpty) {
        final itemsData = await _db
            .from('checklist_items')
            .select()
            .inFilter('id', itemIds);
        for (final i in itemsData) {
          final item = ChecklistItem.fromJson(i);
          itemMap[item.id] = item;
        }
      }

      // Nome do Inspetor
      final inspProfile = await _db
          .from('profiles')
          .select('full_name')
          .eq('id', inspection.inspectorId)
          .single();

      // Nome do Setor
      final sectorData = await _db
          .from('sectors')
          .select('name')
          .eq('id', inspection.sectorId)
          .single();

      // Título do Checklist
      final clData = await _db
          .from('checklists')
          .select('title')
          .eq('id', inspection.checklistId)
          .single();

      // Nome do Hospital (cabeçalho institucional das exportações)
      final hospitalData = await _db
          .from('hospitals')
          .select('name')
          .eq('id', inspection.hospitalId)
          .single();

      // Ordena respostas pelo order_index do item
      final responses =
          responsesData.map(InspectionResponse.fromJson).toList()
            ..sort((a, b) => (itemMap[a.checklistItemId]?.orderIndex ?? 0)
                .compareTo(itemMap[b.checklistItemId]?.orderIndex ?? 0));

      if (mounted) {
        setState(() {
          _inspection = inspection;
          _responses = responses;
          _items = itemMap;
          _inspectorName = inspProfile['full_name'] as String;
          _sectorName = sectorData['name'] as String;
          _checklistTitle = clData['title'] as String;
          _hospitalName = hospitalData['name'] as String;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[RelatorioIndividual] erro: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Erro ao carregar o relatório. Tente novamente.'),
          backgroundColor: AppColors.nonCompliant,
        ));
      }
    }
  }

  ReportExportData get _exportData => ReportExportData(
        inspection: _inspection!,
        responses: _responses,
        items: _items,
        hospitalName: _hospitalName ?? 'Hospital Universitário',
        sectorName: _sectorName ?? '—',
        checklistTitle: _checklistTitle ?? '—',
        inspectorName: _inspectorName ?? '—',
      );

  // ── Exportação PDF ──────────────────────────────────────────────────────────

  Future<void> _exportPdf() async {
    if (_exportingPdf || _inspection == null) return;
    setState(() => _exportingPdf = true);

    final profile = context.read<AuthProvider>().profile;
    try {
      final bytes = await ReportExportService.buildPdf(_exportData);
      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'relatorio_nr32_$stamp.pdf',
      );

      if (profile != null) {
        await AuditService.log(
          userId: profile.id,
          hospitalId: _inspection!.hospitalId,
          action: 'export_pdf',
          entityType: 'inspection',
          entityId: _inspection!.id,
          details: {'checklist_title': _checklistTitle},
        );
      }
    } catch (e) {
      debugPrint('[RelatorioIndividual] export PDF erro: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Erro ao gerar o PDF. Tente novamente.'),
          backgroundColor: AppColors.nonCompliant,
        ));
      }
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  // ── Exportação Excel ────────────────────────────────────────────────────────

  Future<void> _exportExcel() async {
    if (_exportingExcel || _inspection == null) return;
    setState(() => _exportingExcel = true);

    final profile = context.read<AuthProvider>().profile;
    try {
      final file = await ReportExportService.buildExcelFile(_exportData);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        text: 'Relatório de Inspeção NR-32 — $_checklistTitle',
      ));

      if (profile != null) {
        await AuditService.log(
          userId: profile.id,
          hospitalId: _inspection!.hospitalId,
          action: 'export_excel',
          entityType: 'inspection',
          entityId: _inspection!.id,
          details: {'checklist_title': _checklistTitle},
        );
      }
    } catch (e) {
      debugPrint('[RelatorioIndividual] export Excel erro: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Erro ao gerar a planilha. Tente novamente.'),
          backgroundColor: AppColors.nonCompliant,
        ));
      }
    } finally {
      if (mounted) setState(() => _exportingExcel = false);
    }
  }

  // ── Validação ───────────────────────────────────────────────────────────────

  Future<void> _validar() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Validar relatório?'),
        content: const Text(
          'Após validar, o relatório ficará bloqueado para edição e o Inspetor será notificado.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Validar'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    setState(() => _validating = true);

    final auth = context.read<AuthProvider>();
    final profile = auth.profile!;
    final now = DateTime.now().toIso8601String();

    try {
      await _db.from('inspections').update({
        'overall_status': 'validated',
        'validated_by': profile.id,
        'validated_at': now,
      }).eq('id', widget.inspectionId);

      // Atualiza task status para validated
      await _db.from('tasks').update({
        'status': 'validated',
      }).eq('id', _inspection!.taskId);

      // A notificação ao Inspetor é gerada pelo trigger no banco
      // (migration_notifications.sql) — fonte única, sem duplicar aqui.

      await AuditService.log(
        userId: profile.id,
        hospitalId: _inspection!.hospitalId,
        action: 'validar_relatorio',
        entityType: 'inspection',
        entityId: widget.inspectionId,
        details: {'checklist_title': _checklistTitle},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Relatório validado com sucesso.'),
          backgroundColor: AppColors.compliant,
        ));
        await _load();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Erro ao validar. Tente novamente.'),
          backgroundColor: AppColors.nonCompliant,
        ));
      }
    } finally {
      if (mounted) setState(() => _validating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
          appBar: AppBar(title: const Text('Relatório')),
          body: const Center(child: CircularProgressIndicator()));
    }

    if (_inspection == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('Relatório')),
          body: const Center(child: Text('Inspeção não encontrada.')));
    }

    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final inspection = _inspection!;
    final ncResponses =
        _responses.where((r) => r.status == 'NC').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatório'),
        actions: [
          // ── Exportar PDF ─────────────────────────────────────────────
          IconButton(
            tooltip: 'Exportar PDF',
            onPressed: _exportingPdf ? null : _exportPdf,
            icon: _exportingPdf
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf_outlined),
          ),
          // ── Exportar Excel ───────────────────────────────────────────
          IconButton(
            tooltip: 'Exportar Excel',
            onPressed: _exportingExcel ? null : _exportExcel,
            icon: _exportingExcel
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.table_view_outlined),
          ),
          if (inspection.isSubmitted && !inspection.isValidated)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.compliant,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 38),
                ),
                onPressed: _validating ? null : _validar,
                icon: _validating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.verified_outlined, size: 18),
                label: const Text('Validar'),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppDimensions.screenPadding),
        children: [
          // ── Cabeçalho ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border, width: 0.5),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        _checklistTitle ?? '—',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusBadge(
                        status: inspection.isValidated
                            ? 'validated'
                            : 'submitted'),
                  ],
                ),
                const SizedBox(height: 10),
                _InfoRow(label: 'Hospital', value: _hospitalName ?? '—'),
                _InfoRow(label: 'Setor', value: _sectorName ?? '—'),
                _InfoRow(label: 'Inspetor', value: _inspectorName ?? '—'),
                if (inspection.submittedAt != null)
                  _InfoRow(
                    label: 'Enviado em',
                    value: fmt.format(inspection.submittedAt!),
                  ),
                if (inspection.isValidated && inspection.validatedAt != null)
                  _InfoRow(
                    label: 'Validado em',
                    value: fmt.format(inspection.validatedAt!),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Sumário de conformidade (anel) ──────────────────────────────
          ChartCard(
            title: 'Conformidade',
            subtitle: 'Distribuição das respostas desta inspeção',
            child: ComplianceDonut(
              compliant: _compliant,
              nonCompliant: _nonCompliant,
              notApplicable: _notApplicable,
            ),
          ),
          const SizedBox(height: 16),

          // ── Não conformidades em destaque ───────────────────────────────
          if (ncResponses.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.report_gmailerrorred,
                    size: 18, color: AppColors.nonCompliant),
                const SizedBox(width: 6),
                Text('Não conformidades',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.nonCompliant,
                        )),
              ],
            ),
            const SizedBox(height: 8),
            ...ncResponses.map((resp) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _NcCard(
                    response: resp,
                    item: _items[resp.checklistItemId],
                  ),
                )),
            const SizedBox(height: 8),
          ],

          // ── Respostas ──────────────────────────────────────────────────
          Text('Todos os itens',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),

          ..._responses.map((resp) {
            final item = _items[resp.checklistItemId];
            final isCritical = item?.isCritical ?? false;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ResponseBadge(status: resp.status),
                        if (isCritical) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.warning_amber,
                              size: 16, color: AppColors.nonCompliant),
                        ],
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item?.description ?? 'Item removido',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                    if (item?.nr32Reference != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        item!.nr32Reference!,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.primary),
                      ),
                    ],
                    if (resp.status != 'NC' &&
                        resp.observation != null &&
                        resp.observation!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        resp.observation!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
              child: Text(value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ))),
        ],
      ),
    );
  }
}

/// Card de não conformidade com observação e foto (signed URL re-gerada).
class _NcCard extends StatelessWidget {
  final InspectionResponse response;
  final ChecklistItem? item;

  const _NcCard({required this.response, this.item});

  @override
  Widget build(BuildContext context) {
    final isCritical = item?.isCritical ?? false;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCritical ? AppColors.nonCompliant50 : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.nonCompliant
              .withValues(alpha: isCritical ? 1.0 : 0.4),
          width: isCritical ? 1.2 : 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isCritical) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.nonCompliant,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'NC CRÍTICA',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            item?.description ?? 'Item removido',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (item?.nr32Reference != null) ...[
            const SizedBox(height: 2),
            Text(
              item!.nr32Reference!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.primary),
            ),
          ],
          if (response.observation != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.nonCompliant.withValues(alpha: 0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.comment_outlined,
                      size: 14, color: AppColors.nonCompliant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      response.observation!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (response.photoUrl != null) ...[
            const SizedBox(height: 8),
            FutureBuilder<String?>(
              future:
                  ReportExportService.freshSignedUrl(response.photoUrl!),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Container(
                    height: 140,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                final url = snapshot.data;
                if (url == null) {
                  return Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Foto indisponível',
                        style: Theme.of(context).textTheme.bodySmall),
                  );
                }
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    url,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, e, st) => Container(
                      height: 48,
                      alignment: Alignment.center,
                      color: AppColors.background,
                      child: Text('Foto indisponível',
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ),
                );
              },
            ),
            if (response.photoCapturedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Foto capturada em ${DateFormat('dd/MM/yy HH:mm').format(response.photoCapturedAt!)}',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
