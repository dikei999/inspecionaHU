import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
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
          .select('compliance_rate')
          .eq('hospital_id', hospitalId);

      double conf = 0;
      if (reports.isNotEmpty) {
        final sum = reports.fold<double>(
            0, (acc, r) => acc + (r['compliance_rate'] as num).toDouble());
        conf = sum / reports.length;
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
                profile!.fullName.split(' ').first,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Notificações',
            onPressed: () => context.push(AppRoutes.notificacoes),
          ),
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
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
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
                    child: _MetricCard(
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
                    child: _MetricCard(
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
                    child: _MetricCard(
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
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 0.5),
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

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
