import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/sector.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../widgets/charts.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/skeleton_loader.dart';
import '../../../widgets/stat_card.dart';
import '../../../widgets/status_badge.dart';
import '../../auth/providers/auth_provider.dart';

/// Relatórios & Análises — um dos 4 cards principais do dashboard.
/// Diretor vê o hospital inteiro; Supervisor vê apenas os setores dos quais
/// é owner ou onde tem sector_access.
class RelatoriosAnalisesScreen extends StatefulWidget {
  const RelatoriosAnalisesScreen({super.key});

  @override
  State<RelatoriosAnalisesScreen> createState() =>
      _RelatoriosAnalisesScreenState();
}

class _RelatoriosAnalisesScreenState extends State<RelatoriosAnalisesScreen> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  bool _isSupervisor = false;

  double _conformidade = 0;
  int _totalCompliant = 0;
  int _totalNonCompliant = 0;
  int _totalNotApplicable = 0;
  int _totalInspecoes = 0;
  int _ncsAbertas = 0;

  List<_RecentInspection> _recentes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = context.read<AuthProvider>().profile;
    if (profile?.hospitalId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final hospitalId = profile!.hospitalId!;
    _isSupervisor = profile.role == 'supervisor';

    try {
      // Supervisor: restringe aos setores que ele gerencia.
      List<String>? sectorIds;
      if (_isSupervisor) {
        sectorIds = await _sectorIdsDoSupervisor(hospitalId, profile.id);
        if (sectorIds.isEmpty) {
          if (mounted) {
            setState(() {
              _conformidade = 0;
              _totalCompliant = 0;
              _totalNonCompliant = 0;
              _totalNotApplicable = 0;
              _totalInspecoes = 0;
              _ncsAbertas = 0;
              _recentes = [];
              _loading = false;
            });
          }
          return;
        }
      }

      // ── Conformidade agregada (tabela reports = cache calculado) ───────
      var reportsQuery = _db
          .from('reports')
          .select('compliance_rate, compliant, non_compliant, not_applicable, '
              'inspection_id')
          .eq('hospital_id', hospitalId);
      if (sectorIds != null) {
        reportsQuery = reportsQuery.inFilter('sector_id', sectorIds);
      }
      final reports = await reportsQuery;

      double conf = 0;
      int sumC = 0, sumNc = 0, sumNa = 0;
      if (reports.isNotEmpty) {
        final sum = reports.fold<double>(
            0, (acc, r) => acc + (r['compliance_rate'] as num).toDouble());
        conf = sum / reports.length;
        for (final r in reports) {
          sumC += (r['compliant'] as num? ?? 0).toInt();
          sumNc += (r['non_compliant'] as num? ?? 0).toInt();
          sumNa += (r['not_applicable'] as num? ?? 0).toInt();
        }
      }

      // ── NCs em inspeções ainda não validadas ──────────────────────────
      var openQuery = _db
          .from('inspections')
          .select('id')
          .eq('hospital_id', hospitalId)
          .neq('overall_status', 'validated');
      if (sectorIds != null) {
        openQuery = openQuery.inFilter('sector_id', sectorIds);
      }
      final openInspections = await openQuery;

      int ncCount = 0;
      if (openInspections.isNotEmpty) {
        final ids = openInspections.map((e) => e['id'] as String).toList();
        final ncs = await _db
            .from('inspection_responses')
            .select('id')
            .inFilter('inspection_id', ids)
            .eq('status', 'NC');
        ncCount = ncs.length;
      }

      // ── Inspeções concluídas mais recentes ────────────────────────────
      var recentQuery = _db
          .from('inspections')
          .select('id, sector_id, submitted_at, overall_status')
          .eq('hospital_id', hospitalId)
          .inFilter('overall_status', ['submitted', 'validated']);
      if (sectorIds != null) {
        recentQuery = recentQuery.inFilter('sector_id', sectorIds);
      }
      final recentRows =
          await recentQuery.order('submitted_at', ascending: false).limit(20);

      final recentList = (recentRows as List).cast<Map<String, dynamic>>();
      final recentSectorIds =
          recentList.map((e) => e['sector_id'] as String).toSet().toList();

      final sectorMap = <String, Sector>{};
      if (recentSectorIds.isNotEmpty) {
        final rows =
            await _db.from('sectors').select().inFilter('id', recentSectorIds);
        for (final r in rows) {
          final s = Sector.fromJson(r);
          sectorMap[s.id] = s;
        }
      }

      if (mounted) {
        setState(() {
          _conformidade = conf;
          _totalCompliant = sumC;
          _totalNonCompliant = sumNc;
          _totalNotApplicable = sumNa;
          _totalInspecoes = reports.length;
          _ncsAbertas = ncCount;
          _recentes = recentList
              .map((e) => _RecentInspection(
                    id: e['id'] as String,
                    status: e['overall_status'] as String,
                    sectorName: sectorMap[e['sector_id']]?.name ?? '—',
                    submittedAt:
                        AppDateUtils.parseDate(e['submitted_at'] as String?),
                  ))
              .toList();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[RelatoriosAnalises] erro: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Setores visíveis ao Supervisor: onde é owner + onde tem sector_access.
  Future<List<String>> _sectorIdsDoSupervisor(
      String hospitalId, String supervisorId) async {
    final ids = <String>{};

    final owned = await _db
        .from('sectors')
        .select('id')
        .eq('hospital_id', hospitalId)
        .eq('owner_supervisor_id', supervisorId);
    for (final r in owned) {
      ids.add(r['id'] as String);
    }

    final shared = await _db
        .from('sector_access')
        .select('sector_id')
        .eq('supervisor_id', supervisorId);
    for (final r in shared) {
      ids.add(r['sector_id'] as String);
    }

    return ids.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatórios & Análises'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Calendário',
            onPressed: () => context.push(AppRoutes.calendarioInstitucional),
          ),
          IconButton(
            icon: const Icon(Icons.view_kanban_outlined),
            tooltip: 'Quadro de tarefas',
            onPressed: () => context.push(AppRoutes.quadroTarefasGestao),
          ),
        ],
      ),
      body: _loading
          ? const SkeletonDashboard()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(AppDimensions.screenPadding),
                children: [
                  if (_isSupervisor)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Dados restritos aos seus setores.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ),

                  Row(
                    children: [
                      Expanded(
                        child: StatCard(
                          label: 'Conformidade',
                          value: '${_conformidade.toStringAsFixed(1)}%',
                          icon: Icons.verified_outlined,
                          color: _conformidade >= 80
                              ? AppColors.compliant
                              : _conformidade >= 60
                                  ? AppColors.pending
                                  : AppColors.nonCompliant,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatCard(
                          label: 'Inspeções',
                          value: _totalInspecoes.toString(),
                          icon: Icons.assignment_turned_in_outlined,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  StatCard(
                    label: 'NCs abertas',
                    value: _ncsAbertas.toString(),
                    icon: Icons.warning_amber_outlined,
                    color: _ncsAbertas > 0
                        ? AppColors.nonCompliant
                        : AppColors.compliant,
                  ),
                  const SizedBox(height: 16),

                  // Gráfico "Inspeções na semana" removido — sem substituto
                  // por enquanto. Mantido apenas o donut de conformidade.
                  ChartCard(
                    title: 'Conformidade geral',
                    subtitle: 'Itens respondidos em todas as inspeções',
                    child: ComplianceDonut(
                      compliant: _totalCompliant,
                      nonCompliant: _totalNonCompliant,
                      notApplicable: _totalNotApplicable,
                    ),
                  ),

                  const SizedBox(height: 24),
                  Text('Inspeções recentes',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),

                  if (_recentes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: EmptyState(
                        icon: Icons.insights_outlined,
                        title: 'Nenhuma inspeção concluída',
                        subtitle:
                            'Os relatórios aparecem aqui assim que os Inspetores enviarem as inspeções.',
                      ),
                    )
                  else
                    ..._recentes.map((r) => Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: AppColors.primary50,
                              child: Icon(Icons.description_outlined,
                                  color: AppColors.primary),
                            ),
                            title: Text(r.sectorName),
                            subtitle: Text(r.submittedAt != null
                                ? AppDateUtils.formatDateTime(r.submittedAt!)
                                : '—'),
                            trailing:
                                StatusBadge(status: r.status, compact: true),
                            onTap: () => context
                                .push(AppRoutes.relatorioIndividual(r.id)),
                          ),
                        )),
                ],
              ),
            ),
    );
  }
}

class _RecentInspection {
  final String id;
  final String status;
  final String sectorName;
  final DateTime? submittedAt;

  _RecentInspection({
    required this.id,
    required this.status,
    required this.sectorName,
    required this.submittedAt,
  });
}
