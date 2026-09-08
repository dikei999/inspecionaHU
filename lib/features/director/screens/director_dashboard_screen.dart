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
import '../../../widgets/confirm_dialog.dart';

/// Dashboard do Diretor — modelo "Setor como unidade central".
/// Apenas 4 destinos: Setores, Equipe, Relatórios & Análises e
/// Templates & Configurações. Checklists, tarefas, calendário e vínculos
/// passaram a viver dentro do setor (DetalhesSetorScreen).
class DirectorDashboardScreen extends StatefulWidget {
  const DirectorDashboardScreen({super.key});

  @override
  State<DirectorDashboardScreen> createState() =>
      _DirectorDashboardScreenState();
}

class _DirectorDashboardScreenState extends State<DirectorDashboardScreen> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  double _conformidade = 0;
  int _inspecoesHoje = 0;
  int _ncsAbertas = 0;
  int _setoresPendentes = 0;
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

      // Relatórios arquivados ficam FORA de todo indicador. Quem alimenta
      // gráfico e taxa é a inspeção, então é ela que se exclui — não o
      // checklist, que agora tem exclusão em vez de arquivamento.
      final archivedInspections =
          await ArchiveService.archivedInspectionIds(hospitalId);

      var reportsQuery = _db
          .from('reports')
          .select('compliance_rate, compliant, non_compliant, not_applicable')
          .eq('hospital_id', hospitalId);
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
          .gte('submitted_at', '${todayStr}T00:00:00')
          .lt('submitted_at', '${todayStr}T23:59:59');
      if (archivedInspections.isNotEmpty) {
        todayQuery = todayQuery.not('id', 'in', archivedInspections);
      }
      final inspToday = await todayQuery;

      var openQuery = _db
          .from('inspections')
          .select('id')
          .eq('hospital_id', hospitalId)
          .neq('overall_status', 'validated');
      if (archivedInspections.isNotEmpty) {
        openQuery = openQuery.not('id', 'in', archivedInspections);
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

      // Tarefa de checklist EXCLUÍDO some do painel: ele não recebe
      // tarefa nova e as pendentes deixam de cobrar o setor.
      final deletedChecklists =
          await ArchiveService.deletedChecklistIds(hospitalId);
      var pendingQuery = _db
          .from('tasks')
          .select('sector_id')
          .eq('hospital_id', hospitalId)
          .inFilter('status', ['pending', 'in_progress']);
      if (deletedChecklists.isNotEmpty) {
        pendingQuery =
            pendingQuery.not('checklist_id', 'in', deletedChecklists);
      }
      final pendingTasks = await pendingQuery;

      final sectorIds =
          pendingTasks.map((t) => t['sector_id'] as String).toSet().length;

      if (mounted) {
        setState(() {
          _hospitalNome = hosp?['name'] as String?;
          _conformidade = conf;
          _inspecoesHoje = inspToday.length;
          _ncsAbertas = ncCount;
          _setoresPendentes = sectorIds;
          _totalCompliant = sumC;
          _totalNonCompliant = sumNc;
          _totalNotApplicable = sumNa;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[DirectorDashboard] erro: $e');
      if (mounted) setState(() => _loading = false);
    }
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
              greeting: profile != null ? profile.saudacao : 'Olá',
              subtitle: _hospitalNome ?? 'Painel do Diretor',
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
                  onPressed: () async {
                    if (await confirmSignOut(context) && context.mounted) {
                      await auth.signOut();
                    }
                  },
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
              subtitle:
                  'Checklists, tarefas, equipe e histórico de cada setor',
              onTap: () async {
                await context.push(AppRoutes.gestaoSetores);
                _load();
              },
            ),
            DashboardNavCard(
              icon: Icons.people_outline,
              color: AppColors.compliant,
              title: 'Usuários',
              subtitle: 'Membros do hospital e pedidos de acesso',
              onTap: () async {
                await context.push(AppRoutes.gestaoUsuariosHospital);
                _load();
              },
            ),
            DashboardNavCard(
              icon: Icons.insights_outlined,
              color: AppColors.pending,
              title: 'Relatórios & Análises',
              subtitle: 'Conformidade, NCs e inspeções concluídas',
              badge: _ncsAbertas,
              onTap: () => context.push(AppRoutes.relatoriosAnalises),
            ),
            DashboardNavCard(
              icon: Icons.settings_outlined,
              color: AppColors.primary,
              title: 'Templates & Configurações',
              subtitle: 'Templates locais, notificações e dados do hospital',
              onTap: () => context.push(AppRoutes.configuracoes),
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
