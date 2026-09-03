import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/checklist_template.dart';
import '../../../core/models/hospital.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/skeleton_loader.dart';
import '../../auth/providers/auth_provider.dart';

/// Templates & Configurações — um dos 4 cards principais do dashboard.
///
/// Diretor: templates locais (com criação/edição) + globais (leitura).
/// Supervisor: apenas templates globais em leitura — criar template local
/// é atribuição do Diretor.
class ConfiguracoesScreen extends StatefulWidget {
  const ConfiguracoesScreen({super.key});

  @override
  State<ConfiguracoesScreen> createState() => _ConfiguracoesScreenState();
}

class _ConfiguracoesScreenState extends State<ConfiguracoesScreen>
    with SingleTickerProviderStateMixin {
  final _db = Supabase.instance.client;
  late final TabController _tab;

  bool _isDirector = false;
  bool _loading = true;

  List<ChecklistTemplate> _templates = [];
  Hospital? _hospital;

  @override
  void initState() {
    super.initState();
    final profile = context.read<AuthProvider>().profile;
    _isDirector = profile?.role == 'director';
    _tab = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = context.read<AuthProvider>().profile;
    if (profile?.hospitalId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final hospitalId = profile!.hospitalId!;

    try {
      // Diretor gerencia os templates locais do hospital;
      // Supervisor só enxerga os globais (leitura).
      final templatesData = _isDirector
          ? await _db
              .from('checklist_templates')
              .select()
              .eq('scope', 'local')
              .eq('hospital_id', hospitalId)
              .eq('status', 'active')
              .order('title', ascending: true)
          : await _db
              .from('checklist_templates')
              .select()
              .eq('scope', 'global')
              .eq('status', 'active')
              .order('title', ascending: true);

      final hospitalData = await _db
          .from('hospitals')
          .select()
          .eq('id', hospitalId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _templates = (templatesData as List)
              .map((e) => ChecklistTemplate.fromJson(e))
              .toList();
          _hospital =
              hospitalData != null ? Hospital.fromJson(hospitalData) : null;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[Configuracoes] erro: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Templates & Configurações'),
        bottom: TabBar(
          controller: _tab,
          tabs: [
            Tab(text: _isDirector ? 'Templates locais' : 'Templates globais'),
            const Tab(text: 'Notificações'),
            const Tab(text: 'Hospital'),
          ],
        ),
      ),
      floatingActionButton: _isDirector
          ? FloatingActionButton.extended(
              onPressed: () async {
                await context.push(AppRoutes.novoTemplateLocal);
                _load();
              },
              icon: const Icon(Icons.add),
              label: const Text('Novo template'),
            )
          : null,
      body: TabBarView(
        controller: _tab,
        children: [
          _buildTemplatesTab(context),
          _buildNotificacoesTab(context),
          _buildHospitalTab(context),
        ],
      ),
    );
  }

  // ── Aba 1: Templates ─────────────────────────────────────────────────────
  Widget _buildTemplatesTab(BuildContext context) {
    if (_loading) return const SkeletonList(itemHeight: 72);

    if (_templates.isEmpty) {
      return EmptyState(
        icon: Icons.description_outlined,
        title: _isDirector
            ? 'Nenhum template local'
            : 'Nenhum template global disponível',
        subtitle: _isDirector
            ? 'Crie templates NR-32 do seu hospital para reaproveitar em checklists.'
            : 'Os templates globais são cadastrados pelo Super Admin.',
        actionLabel: _isDirector ? 'Novo template' : null,
        onAction: _isDirector
            ? () async {
                await context.push(AppRoutes.novoTemplateLocal);
                _load();
              }
            : null,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(
            AppDimensions.screenPadding,
            AppDimensions.screenPadding,
            AppDimensions.screenPadding,
            88),
        itemCount: _templates.length,
        itemBuilder: (ctx, i) {
          final t = _templates[i];
          return Card(
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.primary50,
                child: Icon(Icons.description_outlined,
                    color: AppColors.primary),
              ),
              title: Text(t.title),
              subtitle: Text(
                  t.nr32Category ?? (_isDirector ? 'Local' : 'Global')),
              trailing: _isDirector
                  ? IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Editar',
                      onPressed: () async {
                        await context.push(AppRoutes.editarTemplateLocal(t.id));
                        _load();
                      },
                    )
                  : const Icon(Icons.lock_outline,
                      size: 18, color: AppColors.textDisabled),
            ),
          );
        },
      ),
    );
  }

  // ── Aba 2: Notificações ──────────────────────────────────────────────────
  Widget _buildNotificacoesTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppDimensions.screenPadding),
      children: [
        Card(
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: AppColors.primary50,
              child:
                  Icon(Icons.notifications_outlined, color: AppColors.primary),
            ),
            title: const Text('Central de notificações'),
            subtitle: const Text('Ver e marcar notificações como lidas'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.notificacoes),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Quando as notificações são enviadas',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        const _RuleTile(
          icon: Icons.schedule_outlined,
          title: 'Tarefa próxima do prazo',
          subtitle: '24h antes do vencimento — enviada ao Inspetor',
        ),
        const _RuleTile(
          icon: Icons.warning_amber_rounded,
          title: 'Tarefa atrasada',
          subtitle: 'Após o prazo — enviada ao Inspetor',
        ),
        const _RuleTile(
          icon: Icons.edit_note_outlined,
          title: 'Rascunho pendente',
          subtitle: 'Inspeção iniciada e não enviada — lembrete ao Inspetor',
        ),
        const _RuleTile(
          icon: Icons.verified_outlined,
          title: 'Relatório validado',
          subtitle: 'Ao validar uma inspeção — enviada ao Inspetor',
        ),
        const _RuleTile(
          icon: Icons.share_outlined,
          title: 'Pedidos de acesso',
          subtitle: 'Solicitação, aprovação e negação — enviadas ao Supervisor',
        ),
        const _RuleTile(
          icon: Icons.visibility_off_outlined,
          title: 'NC Crítica',
          subtitle: 'Sem push — apenas destaque visual no relatório',
        ),
      ],
    );
  }

  // ── Aba 3: Hospital (somente leitura) ────────────────────────────────────
  Widget _buildHospitalTab(BuildContext context) {
    if (_loading) return const SkeletonList(itemHeight: 72);

    final h = _hospital;
    if (h == null) {
      return const EmptyState(
        icon: Icons.local_hospital_outlined,
        title: 'Hospital não encontrado',
        subtitle: 'Não foi possível carregar os dados do hospital.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppDimensions.screenPadding),
      children: [
        _InfoRow(label: 'Nome', value: h.name),
        _InfoRow(label: 'Sigla', value: h.sigla),
        _InfoRow(label: 'Cidade', value: '${h.city} — ${h.state}'),
        _InfoRow(label: 'Status', value: h.isActive ? 'Ativo' : 'Inativo'),
        _InfoRow(
          label: 'Cadastrado em',
          value: AppDateUtils.formatDate(h.createdAt),
        ),
        const SizedBox(height: 8),
        Text(
          'Os dados do hospital são mantidos pelo Super Admin.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _RuleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _RuleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: AppColors.textSecondary),
        title: Text(title, style: Theme.of(context).textTheme.titleSmall),
        subtitle: Text(subtitle),
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
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(value, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}
