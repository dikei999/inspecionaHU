import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/archive_service.dart';
import '../../../widgets/charts.dart';
import '../../../widgets/notification_bell.dart';
import '../../../widgets/skeleton_loader.dart';
import '../../../widgets/stat_card.dart';
import '../../auth/providers/auth_provider.dart';
import '../../shared/widgets/dashboard_header.dart';
import '../../shared/widgets/dashboard_nav_card.dart';

/// Dashboard do Supervisor — mesma estrutura de 4 destinos do Diretor,
/// porém com os dados restritos aos setores que ele gerencia (owner ou
/// sector_access). Supervisor NÃO cria templates locais nem convida
/// Supervisores — ambas as restrições já são validadas no backend.
class SupervisorDashboardScreen extends StatefulWidget {
  const SupervisorDashboardScreen({super.key});

  @override
  State<SupervisorDashboardScreen> createState() =>
      _SupervisorDashboardScreenState();
}

class _SupervisorDashboardScreenState extends State<SupervisorDashboardScreen> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  double _conformidade = 0;
  int _inspecoesHoje = 0;
  int _ncsAbertas = 0;
  int _setoresPendentes = 0;
  int _meusSetores = 0;
  String? _hospitalNome;

  // Agregados do donut de conformidade
  int _totalCompliant = 0;
  int _totalNonCompliant = 0;
  int _totalNotApplicable = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = context.read<AuthProvider>().profile;
    if (profile == null) {
      // Perfil ainda nao carregado: encerra o loading para
      // a tela nao ficar presa no skeleton indefinidamente.
      if (mounted) setState(() => _loading = false);
      return;
    }
    final hospitalId = profile.hospitalId!;

    try {
      final hosp = await _db
          .from('hospitals')
          .select('name')
          .eq('id', hospitalId)
          .maybeSingle();
      if (mounted && hosp != null) {
        setState(() => _hospitalNome = hosp['name'] as String?);
      }

      // Escopo do Supervisor: setores onde é owner + onde tem sector_access.
      final sectorIds = await _meusSetorIds(hospitalId, profile.id);

      if (sectorIds.isEmpty) {
        if (mounted) {
          setState(() {
            _conformidade = 0;
            _inspecoesHoje = 0;
            _ncsAbertas = 0;
            _setoresPendentes = 0;
            _meusSetores = 0;
            _totalCompliant = 0;
            _totalNonCompliant = 0;
            _totalNotApplicable = 0;
            _loading = false;
          });
        }
        return;
      }

      // Checklists arquivados ficam FORA de todo indicador (bloco 1).
      final archivedChecklists =
          await ArchiveService.archivedChecklistIds(hospitalId);
      final archivedInspections = await ArchiveService.inspectionIdsDeArquivados(
          hospitalId,
          sectorIds: sectorIds);

      var reportsQuery = _db
          .from('reports')
          .select('compliance_rate, compliant, non_compliant, not_applicable')
          .eq('hospital_id', hospitalId)
          .inFilter('sector_id', sectorIds);
      if (archivedInspections.isNotEmpty) {
        reportsQuery =
            reportsQuery.not('inspection_id', 'in', archivedInspections);
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

      final today = DateTime.now();
      final todayStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      var todayQuery = _db
          .from('inspections')
          .select('id')
          .eq('hospital_id', hospitalId)
          .inFilter('sector_id', sectorIds)
          .gte('submitted_at', '${todayStr}T00:00:00')
          .lt('submitted_at', '${todayStr}T23:59:59');
      if (archivedChecklists.isNotEmpty) {
        todayQuery = todayQuery.not('checklist_id', 'in', archivedChecklists);
      }
      final inspToday = await todayQuery;

      var openQuery = _db
          .from('inspections')
          .select('id')
          .eq('hospital_id', hospitalId)
          .inFilter('sector_id', sectorIds)
          .neq('overall_status', 'validated');
      if (archivedChecklists.isNotEmpty) {
        openQuery = openQuery.not('checklist_id', 'in', archivedChecklists);
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

      var pendingQuery = _db
          .from('tasks')
          .select('sector_id')
          .eq('hospital_id', hospitalId)
          .inFilter('sector_id', sectorIds)
          .inFilter('status', ['pending', 'in_progress']);
      if (archivedChecklists.isNotEmpty) {
        pendingQuery =
            pendingQuery.not('checklist_id', 'in', archivedChecklists);
      }
      final pendingTasks = await pendingQuery;

      final pendentes =
          pendingTasks.map((t) => t['sector_id'] as String).toSet().length;

      if (mounted) {
        setState(() {
          _conformidade = conf;
          _inspecoesHoje = inspToday.length;
          _ncsAbertas = ncCount;
          _setoresPendentes = pendentes;
          _meusSetores = sectorIds.length;
          _totalCompliant = sumC;
          _totalNonCompliant = sumNc;
          _totalNotApplicable = sumNa;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[SupervisorDashboard] erro: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Setores do Supervisor: owner + sector_access (view ou edit).
  Future<List<String>> _meusSetorIds(
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
    final auth = context.read<AuthProvider>();
    final profile = context.watch<AuthProvider>().profile;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // ── Header institucional azul ─────────────────────────────
            DashboardHeader(
              greeting: profile?.fullName != null
                  ? 'Olá, ${profile!.fullName.split(' ').first}'
                  : 'Olá',
              subtitle: _hospitalNome ?? 'Painel do Supervisor',
              actions: [
                const NotificationBell(),
                IconButton(
                  icon: const Icon(Icons.person_outline),
                  tooltip: 'Perfil',
                  onPressed: () => context.push(AppRoutes.perfil),
                ),
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Sair',
                  onPressed: () => auth.signOut(),
                ),
              ],
              child: _loading
                  ? null
                  : ComplianceDonut(
                      light: true,
                      compliant: _totalCompliant,
                      nonCompliant: _totalNonCompliant,
                      notApplicable: _totalNotApplicable,
                    ),
            ),
            const SizedBox(height: 16),

            // ── Conteúdo ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
            if (_loading)
              const SkeletonDashboard()
            else ...[
              // ── Métricas ──────────────────────────────────────────────
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
                      label: 'Inspeções hoje',
                      value: _inspecoesHoje.toString(),
                      icon: Icons.today_outlined,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: StatCard(
                      label: 'NCs abertas',
                      value: _ncsAbertas.toString(),
                      icon: Icons.warning_amber_outlined,
                      color: _ncsAbertas > 0
                          ? AppColors.nonCompliant
                          : AppColors.compliant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      label: 'Setores pendentes',
                      value: _setoresPendentes.toString(),
                      icon: Icons.domain_outlined,
                      color: _setoresPendentes > 0
                          ? AppColors.pending
                          : AppColors.compliant,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 28),

            // ── Navegação: 4 destinos ─────────────────────────────────
            Text('Gestão', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),

            DashboardNavCard(
              icon: Icons.domain_outlined,
              color: AppColors.primary,
              title: 'Setores',
              subtitle: _meusSetores > 0
                  ? 'Seus setores: checklists, tarefas, equipe e histórico'
                  : 'Você ainda não é responsável por nenhum setor',
              onTap: () async {
                await context.push(AppRoutes.gestaoSetores);
                _load();
              },
            ),
            DashboardNavCard(
              icon: Icons.people_outline,
              color: AppColors.compliant,
              title: 'Inspetores',
              subtitle: 'Inspetores, convites e acesso compartilhado',
              onTap: () async {
                await context.push(AppRoutes.gestaoEquipe);
                _load();
              },
            ),
            DashboardNavCard(
              icon: Icons.insights_outlined,
              color: AppColors.pending,
              title: 'Relatórios & Análises',
              subtitle: 'Conformidade e inspeções dos seus setores',
              badge: _ncsAbertas,
              onTap: () => context.push(AppRoutes.supervisorRelatorios),
            ),
            DashboardNavCard(
              icon: Icons.settings_outlined,
              color: AppColors.primary,
              title: 'Templates & Configurações',
              subtitle: 'Templates globais (leitura), notificações e hospital',
              onTap: () => context.push(AppRoutes.supervisorConfiguracoes),
            ),
            const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
