import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../app/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../widgets/charts.dart';
import '../../../widgets/skeleton_loader.dart';
import '../../../widgets/stat_card.dart';
import '../../auth/providers/auth_provider.dart';

class SuperAdminDashboardScreen extends StatefulWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  State<SuperAdminDashboardScreen> createState() =>
      _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState extends State<SuperAdminDashboardScreen> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  int _totalHospitais = 0;
  int _totalUsuarios = 0;
  int _semVinculo = 0;
  int _totalTemplates = 0;
  List<double> _usuariosPorPerfil = List.filled(5, 0);

  static const _perfilLabels = [
    'Diretor',
    'Superv.',
    'Inspetor',
    'Admin',
    'Sem vínc.'
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _db.from('hospitals').select('id').eq('status', 'active'),
        _db.from('profiles').select('id, role').eq('status', 'active'),
        _db.from('checklist_templates')
            .select('id')
            .isFilter('hospital_id', null),
      ]);

      final profiles = results[1];
      final porPerfil = List<double>.filled(5, 0);
      int semVinculo = 0;
      for (final p in profiles) {
        switch (p['role'] as String?) {
          case 'director':
            porPerfil[0] += 1;
          case 'supervisor':
            porPerfil[1] += 1;
          case 'inspector':
            porPerfil[2] += 1;
          case 'super_admin':
            porPerfil[3] += 1;
          default:
            porPerfil[4] += 1;
            semVinculo++;
        }
      }

      if (mounted) {
        setState(() {
          _totalHospitais = results[0].length;
          _totalUsuarios = profiles.length;
          _semVinculo = semVinculo;
          _totalTemplates = results[2].length;
          _usuariosPorPerfil = porPerfil;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[SuperAdminDashboard] erro: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Super Admin'),
        automaticallyImplyLeading: false,
        actions: [
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
            // ── Header ────────────────────────────────────────────────
            Text(
              'Visão geral',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),

            // ── Cards de métricas ──────────────────────────────────────
            if (_loading)
              const SkeletonDashboard()
            else ...[
              Row(
                children: [
                  Expanded(
                    child: StatCard(
                      icon: Icons.local_hospital_outlined,
                      label: 'Hospitais',
                      value: _totalHospitais.toString(),
                      subtitle: 'ativos',
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      icon: Icons.people_outline,
                      label: 'Usuários',
                      value: _totalUsuarios.toString(),
                      subtitle: 'cadastrados',
                      color: AppColors.compliant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: StatCard(
                      icon: Icons.link_off,
                      label: 'Sem vínculo',
                      value: _semVinculo.toString(),
                      subtitle: 'aguardando',
                      color: _semVinculo > 0
                          ? AppColors.pending
                          : AppColors.compliant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      icon: Icons.checklist_outlined,
                      label: 'Templates',
                      value: _totalTemplates.toString(),
                      subtitle: 'globais NR-32',
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Gráfico: distribuição de usuários ──────────────────
              ChartCard(
                title: 'Usuários por perfil',
                subtitle: 'Contas ativas na plataforma',
                child: SingleSeriesBarChart(
                  values: _usuariosPorPerfil,
                  labels: _perfilLabels,
                  tooltipSuffix: ' usuário(s)',
                ),
              ),
            ],

            const SizedBox(height: 28),

            // ── Ações ──────────────────────────────────────────────────
            Text('Gestão', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),

            _NavCard(
              icon: Icons.local_hospital_outlined,
              color: AppColors.primary,
              title: 'Hospitais',
              subtitle: 'Criar e gerenciar unidades hospitalares',
              badge: _totalHospitais,
              onTap: () => context.push(AppRoutes.hospitais),
            ),
            const SizedBox(height: 8),
            _NavCard(
              icon: Icons.link,
              color: _semVinculo > 0 ? AppColors.pending : AppColors.primary,
              title: 'Convidar Diretor',
              subtitle: 'Enviar convite de Diretor a um hospital',
              badge: _semVinculo > 0 ? _semVinculo : null,
              badgeColor: AppColors.pending,
              onTap: () => context.push(AppRoutes.vincularDirector),
            ),
            const SizedBox(height: 8),
            _NavCard(
              icon: Icons.outgoing_mail,
              color: AppColors.primary,
              title: 'Convites enviados',
              subtitle: 'Acompanhar convites de Diretor',
              onTap: () => context.push(AppRoutes.convitesEnviados),
            ),
            const SizedBox(height: 8),
            _NavCard(
              icon: Icons.manage_accounts_outlined,
              color: AppColors.compliant,
              title: 'Usuários',
              subtitle: 'Buscar e editar usuários cadastrados',
              onTap: () => context.push(AppRoutes.gestaoUsuarios),
            ),
            const SizedBox(height: 8),
            _NavCard(
              icon: Icons.checklist_outlined,
              color: AppColors.primary,
              title: 'Templates NR-32',
              subtitle: 'Modelos globais para todos os hospitais',
              onTap: () => context.push(AppRoutes.templatesGlobais),
            ),
            if (AppConfig.showDemoLogin) ...[
              const SizedBox(height: 8),
              _NavCard(
                icon: Icons.science_outlined,
                color: Colors.grey.shade600,
                title: 'Painel Demo',
                subtitle: 'Provisionar contas e dados de teste (dev only)',
                onTap: () => context.push(AppRoutes.painelDemo),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final int? badge;
  final Color? badgeColor;
  final VoidCallback onTap;

  const _NavCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.badge,
    this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 0.5),
            boxShadow: AppShadows.card,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        if (badge != null && badge! > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: (badgeColor ?? AppColors.primary)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              badge.toString(),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: badgeColor ?? AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
