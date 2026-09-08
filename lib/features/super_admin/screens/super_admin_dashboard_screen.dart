import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../app/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../widgets/charts.dart';
import '../../../widgets/skeleton_loader.dart';
import '../../auth/providers/auth_provider.dart';
import '../../shared/widgets/dashboard_header.dart';
import '../../../widgets/confirm_dialog.dart';

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
                  : 'Super Admin',
              subtitle: 'Administração global · Rede EBSERH',
              actions: [
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
                  : Row(
                      children: [
                        Expanded(
                          child: HeaderMetric(
                            value: _totalHospitais.toString(),
                            label: 'Hospitais ativos',
                          ),
                        ),
                        Expanded(
                          child: HeaderMetric(
                            value: _totalUsuarios.toString(),
                            label: 'Usuários',
                          ),
                        ),
                        Expanded(
                          child: HeaderMetric(
                            value: _semVinculo.toString(),
                            label: 'Sem vínculo',
                          ),
                        ),
                        Expanded(
                          child: HeaderMetric(
                            value: _totalTemplates.toString(),
                            label: 'Templates',
                          ),
                        ),
                      ],
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
            else
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
              title: 'Convites de Diretor',
              subtitle: 'Enviar e acompanhar convites de Diretor',
              badge: _semVinculo > 0 ? _semVinculo : null,
              badgeColor: AppColors.pending,
              onTap: () => context.push(AppRoutes.vincularDirector),
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
