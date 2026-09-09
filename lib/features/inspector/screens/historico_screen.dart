import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../core/constants/app_colors.dart';
import '../../../core/services/data_source.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/skeleton_loader.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../widgets/confirm_dialog.dart';

class HistoricoScreen extends StatefulWidget {
  const HistoricoScreen({super.key});

  @override
  State<HistoricoScreen> createState() => _HistoricoScreenState();
}

class _HistoricoScreenState extends State<HistoricoScreen> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  List<_InspectionEntry> _entries = [];

  /// Histórico agrupado por série: uma recorrência é um card só, como no
  /// quadro de tarefas. Inspeção avulsa segue card individual (A3).
  List<_HistoryGroup> get _grupos => _HistoryGroup.agrupar(_entries);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final perfil = context.read<AuthProvider>().profile;
    final uid = perfil?.id;
    if (uid == null) {
      // Perfil ainda nao carregado: encerra o loading para
      // a tela nao ficar presa no skeleton indefinidamente.
      if (mounted) setState(() => _loading = false);
      return;
    }

    // O histórico é consulta ao servidor e não tem equivalente local: o que
    // foi enviado vive lá. Offline a tela explica isso, em vez de tentar a
    // rede e falhar.
    if (DataSource.estaOffline) {
      if (mounted) {
        setState(() {
          _entries = [];
          _loading = false;
        });
      }
      return;
    }

    try {
      // Busca inspeções submetidas/validadas do inspetor
      // hospital_id explicito: a RLS ja isola o Inspetor as proprias
      // inspecoes, mas a regra de ouro do projeto e que TODA query filtre
      // o hospital. Esta era a unica consulta desta tela que nao filtrava.
      final hospitalId = perfil?.hospitalId;
      var query = _db
          .from('inspections')
          .select()
          .eq('inspector_id', uid)
          .inFilter('overall_status', ['submitted', 'validated']);
      if (hospitalId != null) {
        query = query.eq('hospital_id', hospitalId);
      }
      final data = await query.order('submitted_at', ascending: false);

      if ((data as List).isEmpty) {
        if (mounted) {
          setState(() {
            _entries = [];
            _loading = false;
          });
        }
        return;
      }

      // Busca checklists e setores relacionados
      final checklistIds =
          data.map((e) => e['checklist_id'] as String).toSet().toList();
      final sectorIds =
          data.map((e) => e['sector_id'] as String).toSet().toList();

      final checklistsData = await _db
          .from('checklists')
          .select('id, title')
          .inFilter('id', checklistIds);

      final sectorsData = await _db
          .from('sectors')
          .select('id, name')
          .inFilter('id', sectorIds);

      // Busca reports para ter compliance_rate
      final inspectionIds = data.map((e) => e['id'] as String).toList();
      final reportsData = await _db
          .from('reports')
          .select('inspection_id, compliance_rate')
          .inFilter('inspection_id', inspectionIds);

      // Serie de cada inspecao: o historico listava ocorrencias soltas
      // enquanto o quadro de tarefas ja agrupava (A3).
      final taskIds = data
          .map((e) => e['task_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final seriePorTask = <String, Map<String, dynamic>>{};
      if (taskIds.isNotEmpty) {
        var tq = _db
            .from('tasks')
            .select('id, series_id, series_total')
            .inFilter('id', taskIds);
        if (hospitalId != null) {
          tq = tq.eq('hospital_id', hospitalId);
        }
        for (final t in await tq) {
          seriePorTask[t['id'] as String] = t;
        }
      }

      // Mapeia por id
      final checklistMap = <String, String>{
        for (final c in checklistsData as List)
          c['id'] as String: c['title'] as String,
      };
      final sectorMap = <String, String>{
        for (final s in sectorsData as List)
          s['id'] as String: s['name'] as String,
      };
      final rateMap = <String, double>{
        for (final r in reportsData as List)
          r['inspection_id'] as String:
              (r['compliance_rate'] as num).toDouble(),
      };

      if (mounted) {
        setState(() {
          _entries = data.map((e) {
            final id = e['id'] as String;
            final serie = seriePorTask[e['task_id'] as String?];
            return _InspectionEntry(
              id: id,
              checklistTitle:
                  checklistMap[e['checklist_id'] as String] ?? 'Checklist',
              sectorName:
                  sectorMap[e['sector_id'] as String] ?? 'Setor',
              overallStatus: e['overall_status'] as String,
              submittedAt: e['submitted_at'] != null
                  ? DateTime.parse(e['submitted_at'] as String)
                  : null,
              validatedAt: e['validated_at'] != null
                  ? DateTime.parse(e['validated_at'] as String)
                  : null,
              complianceRate: rateMap[id],
              seriesId: serie?['series_id'] as String?,
              seriesTotal: (serie?['series_total'] as num?)?.toInt(),
            );
          }).toList();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[Historico] erro: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
            onPressed: () async {
              if (await confirmSignOut(context) && context.mounted) {
                await context.read<AuthProvider>().signOut();
              }
            },
          ),
        ],
      ),
      body: _loading
          ? const SkeletonList(itemHeight: 110)
          : RefreshIndicator(
              onRefresh: _load,
              child: _entries.isEmpty
                  ? EmptyState(
                      icon: DataSource.estaOffline
                          ? Icons.cloud_off_outlined
                          : Icons.history_toggle_off,
                      title: DataSource.estaOffline
                          ? 'Histórico indisponível offline'
                          : 'Nenhuma inspeção enviada ainda',
                      subtitle: DataSource.estaOffline
                          ? 'O histórico fica no servidor. Conecte-se à '
                              'internet para consultá-lo.'
                          : 'Após enviar uma inspeção ela aparecerá aqui.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _grupos.length,
                      separatorBuilder: (_, i) => const SizedBox(height: 10),
                      itemBuilder: (_, i) =>
                          _GroupCard(grupo: _grupos[i]),
                    ),
            ),
    );
  }

}

// ── Modelo interno ────────────────────────────────────────────────────────────

class _InspectionEntry {
  final String id;
  final String checklistTitle;
  final String sectorName;
  final String overallStatus;
  final DateTime? submittedAt;
  final DateTime? validatedAt;
  final double? complianceRate;

  /// Serie da tarefa que gerou a inspecao. null = avulsa.
  final String? seriesId;
  final int? seriesTotal;

  const _InspectionEntry({
    required this.id,
    required this.checklistTitle,
    required this.sectorName,
    required this.overallStatus,
    this.submittedAt,
    this.validatedAt,
    this.complianceRate,
    this.seriesId,
    this.seriesTotal,
  });
}

/// Um card do historico: uma serie inteira ou uma inspecao avulsa (A3).
class _HistoryGroup {
  final String? seriesId;
  final List<_InspectionEntry> entradas;

  const _HistoryGroup({required this.seriesId, required this.entradas});

  bool get isSerie => seriesId != null && entradas.length > 1;

  _InspectionEntry get principal => entradas.first;

  int get total {
    final declarado = principal.seriesTotal;
    if (declarado != null && declarado >= entradas.length) return declarado;
    return entradas.length;
  }

  String get progresso => '${entradas.length} de $total';

  /// Agrupa preservando a ordem de chegada (mais recente primeiro), que ja
  /// vem ordenada por submitted_at desc.
  static List<_HistoryGroup> agrupar(List<_InspectionEntry> entradas) {
    final porSerie = <String, List<_InspectionEntry>>{};
    final ordem = <String>[];
    final saida = <_HistoryGroup>[];

    for (final e in entradas) {
      final sid = e.seriesId;
      if (sid == null) {
        saida.add(_HistoryGroup(seriesId: null, entradas: [e]));
      } else {
        if (!porSerie.containsKey(sid)) {
          porSerie[sid] = [];
          ordem.add(sid);
          // Marca o lugar da serie na lista pela PRIMEIRA ocorrencia vista,
          // que e a mais recente: a serie nao pula para o topo nem afunda.
          saida.add(_HistoryGroup(seriesId: sid, entradas: porSerie[sid]!));
        }
        porSerie[sid]!.add(e);
      }
    }
    return saida;
  }
}

// ── Card do grupo: série ou inspeção avulsa ───────────────────────────────────

class _GroupCard extends StatelessWidget {
  final _HistoryGroup grupo;
  const _GroupCard({required this.grupo});

  @override
  Widget build(BuildContext context) {
    if (!grupo.isSerie) return _EntryCard(entry: grupo.principal);

    final principal = grupo.principal;
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: const Icon(
            Icons.repeat_rounded,
            size: 20,
            color: AppColors.primary,
          ),
          title: Text(
            principal.checklistTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          subtitle: Text(
            principal.sectorName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primary50,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              grupo.progresso,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.primary700,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          children: [
            for (final e in grupo.entradas)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _EntryCard(entry: e),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Card de inspeção ──────────────────────────────────────────────────────────

class _EntryCard extends StatelessWidget {
  final _InspectionEntry entry;
  const _EntryCard({required this.entry});

  Color get _statusColor =>
      entry.overallStatus == 'validated' ? AppColors.compliant : AppColors.primary;

  String get _statusLabel =>
      entry.overallStatus == 'validated' ? 'Validado' : 'Enviado';

  IconData get _statusIcon =>
      entry.overallStatus == 'validated' ? Icons.verified_outlined : Icons.send_outlined;

  Color get _rateColor {
    final r = entry.complianceRate ?? 0;
    if (r >= 80) return AppColors.compliant;
    if (r >= 60) return AppColors.pending;
    return AppColors.nonCompliant;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Título e badge de status ───────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    entry.checklistTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_statusIcon, size: 12, color: _statusColor),
                      const SizedBox(width: 4),
                      Text(
                        _statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ── Setor ──────────────────────────────────────────────────
            Row(
              children: [
                const Icon(Icons.domain_outlined,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  entry.sectorName,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Linha inferior: data + taxa de conformidade ────────────
            Row(
              children: [
                // Data de envio
                if (entry.submittedAt != null) ...[
                  const Icon(Icons.calendar_today_outlined,
                      size: 13, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    AppDateUtils.formatDate(entry.submittedAt!),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
                const Spacer(),
                // Taxa de conformidade
                if (entry.complianceRate != null) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _rateColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.pie_chart_outline,
                            size: 12, color: _rateColor),
                        const SizedBox(width: 4),
                        Text(
                          '${entry.complianceRate!.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _rateColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),

            // Data de validação
            if (entry.validatedAt != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.verified_outlined,
                      size: 13, color: AppColors.compliant),
                  const SizedBox(width: 4),
                  Text(
                    'Validado em ${AppDateUtils.formatDate(entry.validatedAt!)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.compliant,
                        ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
