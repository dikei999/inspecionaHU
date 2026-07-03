import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../widgets/charts.dart';
import '../../../widgets/notification_bell.dart';
import '../../../widgets/skeleton_loader.dart';
import '../../../widgets/stat_card.dart';
import '../../auth/providers/auth_provider.dart';

/// Dashboard do Supervisor — mesma visão do Diretor com permissões restritas.
/// Supervisor NÃO cria templates locais nem vincula Supervisores.
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

  // Agregados para os gráficos
  int _totalCompliant = 0;
  int _totalNonCompliant = 0;
  int _totalNotApplicable = 0;
  List<double> _inspecoesPorDia = List.filled(7, 0);
  List<String> _diasLabels = List.filled(7, '');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = context.read<AuthProvider>().profile;
    if (profile == null) return;
    final hospitalId = profile.hospitalId!;

    try {
      final reports = await _db
          .from('reports')
          .select(
              'compliance_rate, compliant_items, non_compliant_items, not_applicable_items')
          .eq('hospital_id', hospitalId);

      double conf = 0;
      int sumC = 0, sumNc = 0, sumNa = 0;
      if (reports.isNotEmpty) {
        final sum = reports.fold<double>(
            0, (acc, r) => acc + (r['compliance_rate'] as num).toDouble());
        conf = sum / reports.length;
        for (final r in reports) {
          sumC += (r['compliant_items'] as num? ?? 0).toInt();
          sumNc += (r['non_compliant_items'] as num? ?? 0).toInt();
          sumNa += (r['not_applicable_items'] as num? ?? 0).toInt();
        }
      }

      final today = DateTime.now();
      final todayStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final inspToday = await _db
          .from('inspections')
          .select('id')
          .eq('hospital_id', hospitalId)
          .gte('submitted_at', '${todayStr}T00:00:00')
          .lt('submitted_at', '${todayStr}T23:59:59');

      // Inspeções enviadas nos últimos 7 dias (para o gráfico de barras)
      final weekAgo = today.subtract(const Duration(days: 6));
      final weekAgoStr =
          '${weekAgo.year}-${weekAgo.month.toString().padLeft(2, '0')}-${weekAgo.day.toString().padLeft(2, '0')}';
      final inspWeek = await _db
          .from('inspections')
          .select('submitted_at')
          .eq('hospital_id', hospitalId)
          .gte('submitted_at', '${weekAgoStr}T00:00:00');

      final porDia = List<double>.filled(7, 0);
      final labels = List<String>.filled(7, '');
      const weekdayNames = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
      for (int i = 0; i < 7; i++) {
        final day = today.subtract(Duration(days: 6 - i));
        labels[i] = weekdayNames[day.weekday - 1];
      }
      for (final insp in inspWeek) {
        final submitted = AppDateUtils.parseDate(insp['submitted_at'] as String?);
        if (submitted == null) continue;
        final diff = DateTime(today.year, today.month, today.day)
            .difference(
                DateTime(submitted.year, submitted.month, submitted.day))
            .inDays;
        if (diff >= 0 && diff < 7) porDia[6 - diff] += 1;
      }

      final openInspections = await _db
          .from('inspections')
          .select('id')
          .eq('hospital_id', hospitalId)
          .neq('overall_status', 'validated');

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

      final pendingTasks = await _db
          .from('tasks')
          .select('sector_id')
          .eq('hospital_id', hospitalId)
          .inFilter('status', ['pending', 'in_progress']);

      final sectorIds =
          pendingTasks.map((t) => t['sector_id'] as String).toSet().length;

      if (mounted) {
        setState(() {
          _conformidade = conf;
          _inspecoesHoje = inspToday.length;
          _ncsAbertas = ncCount;
          _setoresPendentes = sectorIds;
          _totalCompliant = sumC;
          _totalNonCompliant = sumNc;
          _totalNotApplicable = sumNa;
          _inspecoesPorDia = porDia;
          _diasLabels = labels;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[SupervisorDashboard] erro: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final profile = context.watch<AuthProvider>().profile;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Dashboard'),
            if (profile?.fullName != null)
              Text(
                'Olá, ${profile!.fullName.split(' ').first}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
          ],
        ),
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
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Métricas ─────────────────────────────────────────────
            if (_loading)
              const SkeletonDashboard()
            else ...[
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
              const SizedBox(height: 16),

              // ── Gráficos ────────────────────────────────────────────
              ChartCard(
                title: 'Conformidade geral',
                subtitle: 'Itens respondidos em todas as inspeções',
                child: ComplianceDonut(
                  compliant: _totalCompliant,
                  nonCompliant: _totalNonCompliant,
                  notApplicable: _totalNotApplicable,
                ),
              ),
              const SizedBox(height: 12),
              ChartCard(
                title: 'Inspeções na semana',
                subtitle: 'Enviadas nos últimos 7 dias',
                child: SingleSeriesBarChart(
                  values: _inspecoesPorDia,
                  labels: _diasLabels,
                  tooltipSuffix: ' inspeção(ões)',
                ),
              ),
            ],

            const SizedBox(height: 28),
            Text('Gestão', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),

            _buildNavGrid(context),
          ],
        ),
      ),
    );
  }

  Widget _buildNavGrid(BuildContext context) {
    final items = [
      _NavItem(
        icon: Icons.domain_outlined,
        label: 'Setores',
        color: AppColors.primary,
        onTap: () => context.push(AppRoutes.gestaoSetores),
      ),
      _NavItem(
        icon: Icons.people_outline,
        label: 'Inspetores',
        color: AppColors.compliant,
        onTap: () => context.push(AppRoutes.gestaoEquipe),
      ),
      _NavItem(
        icon: Icons.checklist_outlined,
        label: 'Novo Checklist',
        color: AppColors.primary,
        onTap: () => context.push(AppRoutes.novoChecklist),
      ),
      _NavItem(
        icon: Icons.assignment_add,
        label: 'Atribuir Tarefa',
        color: AppColors.pending,
        onTap: () => context.push(AppRoutes.atribuirTarefa),
      ),
      _NavItem(
        icon: Icons.view_kanban_outlined,
        label: 'Quadro de Tarefas',
        color: AppColors.pending,
        badge: _setoresPendentes,
        onTap: () => context.push(AppRoutes.quadroTarefasGestao),
      ),
      _NavItem(
        icon: Icons.calendar_month_outlined,
        label: 'Calendário',
        color: AppColors.primary,
        onTap: () => context.push(AppRoutes.calendarioInstitucional),
      ),
      _NavItem(
        icon: Icons.share_outlined,
        label: 'Acesso Compartilhado',
        color: AppColors.primary,
        onTap: () => context.push(AppRoutes.acessoCompartilhado),
      ),
      _NavItem(
        icon: Icons.approval_outlined,
        label: 'Pedidos de Acesso',
        color: AppColors.primary,
        onTap: () => context.push(AppRoutes.pedidosAcesso),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.0,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => _NavTile(item: items[i]),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final Color color;
  final int badge;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.color,
    this.badge = 0,
    required this.onTap,
  });
}

class _NavTile extends StatelessWidget {
  final _NavItem item;
  const _NavTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 0.5),
            boxShadow: AppShadows.card,
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: item.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(item.icon, color: item.color, size: 22),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: AppColors.textPrimary,
                            height: 1.3,
                          ),
                    ),
                  ],
                ),
              ),
              if (item.badge > 0)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.pending,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      item.badge.toString(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
