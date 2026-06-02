import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/checklist_item.dart';
import '../../../core/models/inspection.dart';
import '../../../core/models/inspection_response.dart';
import '../../../core/services/audit_service.dart';
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

  Inspection? _inspection;
  Map<String, ChecklistItem> _items = {};
  List<InspectionResponse> _responses = [];
  String? _inspectorName;
  String? _sectorName;
  String? _checklistTitle;

  int get _compliant =>
      _responses.where((r) => r.status == 'C').length;
  int get _nonCompliant =>
      _responses.where((r) => r.status == 'NC').length;
  int get _notApplicable =>
      _responses.where((r) => r.status == 'NA').length;
  double get _complianceRate {
    final total = _compliant + _nonCompliant;
    if (total == 0) return 0;
    return (_compliant / total) * 100;
  }

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

      if (mounted) {
        setState(() {
          _inspection = inspection;
          _responses = responsesData.map(InspectionResponse.fromJson).toList();
          _items = itemMap;
          _inspectorName = inspProfile['full_name'] as String;
          _sectorName = sectorData['name'] as String;
          _checklistTitle = clData['title'] as String;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

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

      // Notifica o Inspetor
      await _db.from('notifications').insert({
        'user_id': _inspection!.inspectorId,
        'hospital_id': _inspection!.hospitalId,
        'type': 'report_validated',
        'title': 'Relatório validado',
        'body':
            'Seu relatório de "$_checklistTitle" foi validado por ${profile.fullName}.',
        'read': false,
      });

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatório'),
        actions: [
          if (inspection.isSubmitted && !inspection.isValidated)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.compliant,
                  foregroundColor: Colors.white,
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _checklistTitle ?? '—',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 8),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: inspection.isValidated
                          ? AppColors.statusValidated.withAlpha(30)
                          : AppColors.statusSubmitted.withAlpha(30),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      inspection.isValidated ? 'Validado' : 'Enviado',
                      style: TextStyle(
                        color: inspection.isValidated
                            ? AppColors.statusValidated
                            : AppColors.statusSubmitted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Sumário de conformidade ─────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Conformidade',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _ComplianceChip(
                        label: 'C',
                        count: _compliant,
                        color: AppColors.compliant,
                      ),
                      const SizedBox(width: 8),
                      _ComplianceChip(
                        label: 'NC',
                        count: _nonCompliant,
                        color: AppColors.nonCompliant,
                      ),
                      const SizedBox(width: 8),
                      _ComplianceChip(
                        label: 'N/A',
                        count: _notApplicable,
                        color: AppColors.textSecondary,
                      ),
                      const Spacer(),
                      Text(
                        '${_complianceRate.toStringAsFixed(1)}%',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: _complianceRate >= 80
                                  ? AppColors.compliant
                                  : _complianceRate >= 60
                                      ? AppColors.pending
                                      : AppColors.nonCompliant,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Respostas ──────────────────────────────────────────────────
          Text('Respostas',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),

          ..._responses.map((resp) {
            final item = _items[resp.checklistItemId];
            final isNc = resp.status == 'NC';
            final isCritical = item?.isCritical ?? false;

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Status badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: resp.status == 'C'
                                ? AppColors.compliant.withAlpha(30)
                                : resp.status == 'NC'
                                    ? AppColors.nonCompliant.withAlpha(30)
                                    : AppColors.textSecondary.withAlpha(30),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            resp.status ?? '—',
                            style: TextStyle(
                              color: resp.status == 'C'
                                  ? AppColors.compliant
                                  : resp.status == 'NC'
                                      ? AppColors.nonCompliant
                                      : AppColors.textSecondary,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (isCritical) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.warning_amber,
                              size: 16, color: AppColors.nonCompliant),
                        ],
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item?.description ?? 'Item removido',
                            style: Theme.of(context).textTheme.bodyMedium,
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
                    if (isNc && resp.observation != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.nonCompliant.withAlpha(15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.nonCompliant.withAlpha(60)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.comment_outlined,
                                size: 14, color: AppColors.nonCompliant),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                resp.observation!,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (resp.photoUrl != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.photo_outlined,
                              size: 14, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            'Foto registrada${resp.photoCapturedAt != null ? " — ${DateFormat('dd/MM/yy HH:mm').format(resp.photoCapturedAt!)}" : ""}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.primary),
                          ),
                        ],
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
                  style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _ComplianceChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _ComplianceChip(
      {required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
          const SizedBox(width: 6),
          Text('$count',
              style: TextStyle(color: color, fontSize: 13)),
        ],
      ),
    );
  }
}
