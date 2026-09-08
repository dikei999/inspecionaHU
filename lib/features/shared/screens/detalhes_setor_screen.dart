import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/checklist.dart';
import '../../../core/services/archive_service.dart';
import '../../../core/models/profile.dart';
import '../../../core/models/sector.dart';
import '../../../core/models/task.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/skeleton_loader.dart';
import '../../../widgets/status_badge.dart';
import '../../auth/providers/auth_provider.dart';

/// Tela central do modelo "Setor como unidade central".
/// Reúne em abas tudo que pertence a um setor: dados, checklists, tarefas,
/// equipe vinculada e histórico de inspeções.
///
/// Compartilhada entre Diretor e Supervisor — as ações de escrita são
/// filtradas por role (Diretor: tudo; Supervisor: só onde é owner ou
/// tem sector_access.can_edit).
class DetalhesSetorScreen extends StatefulWidget {
  final String sectorId;

  const DetalhesSetorScreen({super.key, required this.sectorId});

  @override
  State<DetalhesSetorScreen> createState() => _DetalhesSetorScreenState();
}

class _DetalhesSetorScreenState extends State<DetalhesSetorScreen>
    with SingleTickerProviderStateMixin {
  final _db = Supabase.instance.client;
  late final TabController _tab;

  bool _loading = true;
  String? _accessError; // preenchido quando o usuário não pode ver o setor

  Sector? _sector;
  Profile? _owner;
  Profile? _creator;

  // Permissões calculadas
  bool _canEdit = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _accessError = null;
    });

    final profile = context.read<AuthProvider>().profile;
    if (profile?.hospitalId == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _accessError = 'Perfil não carregado. Tente novamente.';
        });
      }
      return;
    }

    try {
      // RLS já restringe o SELECT; maybeSingle evita exceção quando o
      // Supervisor não tem visibilidade sobre este setor.
      final data = await _db
          .from('sectors')
          .select()
          .eq('id', widget.sectorId)
          .eq('hospital_id', profile!.hospitalId!)
          .maybeSingle();

      if (data == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _accessError =
                'Você não tem acesso a este setor ou ele não existe mais.';
          });
        }
        return;
      }

      final sector = Sector.fromJson(data);

      // Perfis relacionados (owner + criador)
      final peopleIds = <String>{
        if (sector.ownerSupervisorId != null) sector.ownerSupervisorId!,
        sector.createdBy,
      };
      final people = <String, Profile>{};
      if (peopleIds.isNotEmpty) {
        final rows = await _db
            .from('profiles')
            .select()
            .inFilter('id', peopleIds.toList());
        for (final r in rows) {
          final p = Profile.fromJson(r);
          people[p.id] = p;
        }
      }

      final canEdit = await _resolveCanEdit(profile, sector);

      if (mounted) {
        setState(() {
          _sector = sector;
          _owner = sector.ownerSupervisorId != null
              ? people[sector.ownerSupervisorId]
              : null;
          _creator = people[sector.createdBy];
          _canEdit = canEdit;
          _loading = false;
        });
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _accessError = 'Erro ao carregar o setor: ${e.message}';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _accessError = 'Erro ao carregar o setor.';
        });
      }
    }
  }

  /// Diretor edita qualquer setor do hospital.
  /// Supervisor só edita setores onde é owner ou tem sector_access.can_edit
  /// (mesma regra das policies do banco).
  Future<bool> _resolveCanEdit(Profile profile, Sector sector) async {
    if (profile.role == 'director') return true;
    if (profile.role != 'supervisor') return false;
    if (sector.ownerSupervisorId == profile.id) return true;

    try {
      final access = await _db
          .from('sector_access')
          .select('can_edit')
          .eq('sector_id', sector.id)
          .eq('supervisor_id', profile.id)
          .eq('can_edit', true)
          .maybeSingle();
      return access != null;
    } catch (_) {
      return false;
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.nonCompliant : AppColors.compliant,
    ));
  }

  // ── Ativar / desativar setor (NUNCA apagar — soft delete sempre) ──────────
  Future<void> _toggleStatus() async {
    final sector = _sector;
    if (sector == null) return;
    final auth = context.read<AuthProvider>();
    final newStatus = sector.isActive ? 'inactive' : 'active';
    final label = newStatus == 'inactive' ? 'Desativar' : 'Reativar';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$label setor?'),
        content: Text(
          newStatus == 'inactive'
              ? '"${sector.name}" ficará invisível para os usuários. O histórico é preservado.'
              : 'Reativar "${sector.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: newStatus == 'inactive'
                ? ElevatedButton.styleFrom(
                    backgroundColor: AppColors.nonCompliant)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(label),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await _db
          .from('sectors')
          .update({'status': newStatus}).eq('id', sector.id);

      await AuditService.log(
        userId: auth.profile!.id,
        hospitalId: auth.profile!.hospitalId,
        action: '${newStatus == 'inactive' ? 'desativar' : 'reativar'}_setor',
        entityType: 'sector',
        entityId: sector.id,
        details: {'name': sector.name},
      );

      _showSnack(
          'Setor ${newStatus == 'active' ? 'reativado' : 'desativado'}.');
      _load();
    } on PostgrestException catch (e) {
      _showSnack('Erro ao alterar status: ${e.message}', error: true);
    } catch (_) {
      _showSnack('Erro ao alterar status.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Setor')),
        body: const SkeletonList(itemHeight: 88),
      );
    }

    if (_accessError != null || _sector == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Setor')),
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Sem acesso a este setor',
          subtitle: _accessError,
          actionLabel: 'Voltar',
          onAction: () {
            if (context.canPop()) {
              context.pop();
            } else {
              final role = context.read<AuthProvider>().profile?.role;
              context.go(AppRoutes.dashboardForRole(role));
            }
          },
        ),
      );
    }

    final sector = _sector!;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sector.name, overflow: TextOverflow.ellipsis),
            if (sector.nr32Category != null)
              Text(
                sector.nr32Category!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: StatusBadge(status: sector.status, compact: true),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Info'),
            Tab(text: 'Checklists'),
            Tab(text: 'Tarefas'),
            Tab(text: 'Equipe'),
            Tab(text: 'Histórico'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _InfoTab(
            sector: sector,
            owner: _owner,
            creator: _creator,
            canEdit: _canEdit,
            onEdit: () async {
              await context.push(AppRoutes.editarSetor(sector.id));
              _load();
            },
            onToggleStatus: _toggleStatus,
          ),
          _ChecklistsTab(sectorId: sector.id, canEdit: _canEdit),
          _TarefasTab(sectorId: sector.id, canEdit: _canEdit),
          _EquipeTab(sector: sector, owner: _owner, canEdit: _canEdit),
          _HistoricoTab(sectorId: sector.id),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Aba 1 — Info
// ═══════════════════════════════════════════════════════════════════════════

class _InfoTab extends StatelessWidget {
  final Sector sector;
  final Profile? owner;
  final Profile? creator;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onToggleStatus;

  const _InfoTab({
    required this.sector,
    required this.owner,
    required this.creator,
    required this.canEdit,
    required this.onEdit,
    required this.onToggleStatus,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppDimensions.screenPadding),
      children: [
        _InfoRow(label: 'Nome', value: sector.name),
        _InfoRow(
          label: 'Descrição',
          value: (sector.description?.trim().isNotEmpty ?? false)
              ? sector.description!
              : '—',
        ),
        _InfoRow(label: 'Categoria NR-32', value: sector.nr32Category ?? '—'),
        _InfoRow(
          label: 'Supervisor responsável',
          value: owner?.fullName ?? 'Sem Supervisor vinculado',
        ),
        _InfoRow(label: 'Criado por', value: creator?.fullName ?? '—'),
        _InfoRow(
          label: 'Criado em',
          value: AppDateUtils.formatDateTime(sector.createdAt),
        ),
        _InfoRow(
          label: 'Status',
          value: sector.isActive ? 'Ativo' : 'Inativo',
        ),

        if (canEdit) ...[
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Editar setor'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, AppDimensions.buttonHeight),
            ),
          ),
          const SizedBox(height: 12),
          // Sem opção de apagar: setor é sempre soft delete (regra do projeto).
          OutlinedButton.icon(
            onPressed: onToggleStatus,
            icon: Icon(
              sector.isActive
                  ? Icons.block_outlined
                  : Icons.check_circle_outline,
              size: 18,
            ),
            label: Text(sector.isActive ? 'Desativar setor' : 'Reativar setor'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, AppDimensions.buttonHeight),
              foregroundColor: sector.isActive
                  ? AppColors.nonCompliant
                  : AppColors.compliant,
              side: BorderSide(
                color: sector.isActive
                    ? AppColors.nonCompliant
                    : AppColors.compliant,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Setores nunca são apagados — desativar preserva todo o histórico.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ],
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

// ═══════════════════════════════════════════════════════════════════════════
// Aba 2 — Checklists do setor
// ═══════════════════════════════════════════════════════════════════════════

class _ChecklistsTab extends StatefulWidget {
  final String sectorId;
  final bool canEdit;

  const _ChecklistsTab({required this.sectorId, required this.canEdit});

  @override
  State<_ChecklistsTab> createState() => _ChecklistsTabState();
}

class _ChecklistsTabState extends State<_ChecklistsTab> {
  final _db = Supabase.instance.client;
  bool _loading = true;
  List<Checklist> _checklists = [];

  /// Filtro "Arquivados": false = lista de trabalho (padrão),
  /// true = só os arquivados. Nada é deletado — é só uma visão.
  bool _verArquivados = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _db
          .from('checklists')
          .select()
          .eq('sector_id', widget.sectorId)
          .eq('status', 'active')
          .order('title', ascending: true);
      if (mounted) {
        final todos = (data as List).map((e) => Checklist.fromJson(e)).toList();
        setState(() {
          // Arquivado some da lista de trabalho e só aparece no filtro.
          _checklists =
              todos.where((c) => c.isArchived == _verArquivados).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleArquivar(Checklist checklist) async {
    final auth = context.read<AuthProvider>();
    final arquivar = !checklist.isArchived;

    if (arquivar) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Arquivar checklist?'),
          content: Text(
            '"${checklist.title}" sai das listas de trabalho e deixa de contar '
            'na taxa de conformidade e nos gráficos.\n\n'
            'As inspeções já respondidas continuam salvas e acessíveis pelo '
            'filtro "Arquivados". Nada é apagado e você pode desarquivar '
            'quando quiser.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Arquivar'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }

    final erro = await ArchiveService.setArchived(
      checklistId: checklist.id,
      archive: arquivar,
      userId: auth.profile!.id,
      hospitalId: auth.profile!.hospitalId,
      title: checklist.title,
    );

    if (!mounted) return;
    if (erro != null) {
      _showSnack(erro, error: true);
      return;
    }
    _showSnack(arquivar
        ? 'Checklist arquivado. Fora dos indicadores.'
        : 'Checklist desarquivado. De volta à operação.');
    _load();
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.nonCompliant : AppColors.compliant,
    ));
  }

  Future<void> _desativar(Checklist checklist) async {
    final auth = context.read<AuthProvider>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desativar checklist?'),
        content: Text(
          '"${checklist.title}" deixa de aparecer para novas tarefas. '
          'As inspeções já feitas continuam no histórico.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.nonCompliant),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desativar'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await _db
          .from('checklists')
          .update({'status': 'inactive'}).eq('id', checklist.id);

      await AuditService.log(
        userId: auth.profile!.id,
        hospitalId: auth.profile!.hospitalId,
        action: 'desativar_checklist',
        entityType: 'checklist',
        entityId: checklist.id,
        details: {'title': checklist.title},
      );

      _showSnack('Checklist desativado.');
      _load();
    } on PostgrestException catch (e) {
      _showSnack('Erro ao desativar: ${e.message}', error: true);
    } catch (_) {
      _showSnack('Erro ao desativar checklist.', error: true);
    }
  }

  String _frequencyLabel(String frequency) {
    switch (frequency) {
      case 'daily':
        return 'Diário';
      case 'weekly':
        return 'Semanal';
      case 'biweekly':
        return 'Quinzenal';
      case 'monthly':
        return 'Mensal';
      case 'custom':
        return 'Personalizado';
      default:
        return frequency;
    }
  }

  Future<void> _novoChecklist() async {
    await context.push(AppRoutes.novoChecklistNoSetor(widget.sectorId));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: widget.canEdit
          ? FloatingActionButton.extended(
              heroTag: 'fab_checklist_setor',
              onPressed: _novoChecklist,
              icon: const Icon(Icons.add),
              label: const Text('Novo checklist'),
            )
          : null,
      body: Column(
        children: [
          // Filtro Em operação / Arquivados — arquivar é reversível e
          // nada some do banco, só muda de visão.
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppDimensions.screenPadding, 12, AppDimensions.screenPadding, 0),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                    value: false,
                    label: Text('Em operação'),
                    icon: Icon(Icons.play_circle_outline, size: 18)),
                ButtonSegment(
                    value: true,
                    label: Text('Arquivados'),
                    icon: Icon(Icons.inventory_2_outlined, size: 18)),
              ],
              selected: {_verArquivados},
              showSelectedIcon: false,
              onSelectionChanged: (sel) {
                setState(() => _verArquivados = sel.first);
                _load();
              },
            ),
          ),
          Expanded(child: _buildLista()),
        ],
      ),
    );
  }

  Widget _buildLista() {
    return _loading
          ? const SkeletonList(itemHeight: 76)
          : RefreshIndicator(
              onRefresh: _load,
              child: _checklists.isEmpty
                  ? EmptyState(
                      icon: _verArquivados
                          ? Icons.inventory_2_outlined
                          : Icons.checklist_outlined,
                      title: _verArquivados
                          ? 'Nenhum checklist arquivado'
                          : 'Nenhum checklist neste setor',
                      subtitle: _verArquivados
                          ? 'Checklists arquivados ficam aqui, fora dos '
                              'indicadores, e podem voltar à operação a '
                              'qualquer momento.'
                          : widget.canEdit
                              ? 'Crie um checklist para começar a atribuir tarefas aqui.'
                              : 'Este setor ainda não tem checklists ativos.',
                      actionLabel:
                          widget.canEdit && !_verArquivados ? 'Novo checklist' : null,
                      onAction:
                          widget.canEdit && !_verArquivados ? _novoChecklist : null,
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                          AppDimensions.screenPadding,
                          AppDimensions.screenPadding,
                          AppDimensions.screenPadding,
                          88),
                      itemCount: _checklists.length,
                      itemBuilder: (ctx, i) {
                        final c = _checklists[i];
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: c.isArchived
                                  ? AppColors.border
                                  : AppColors.primary50,
                              child: Icon(
                                  c.isArchived
                                      ? Icons.inventory_2_outlined
                                      : Icons.checklist_outlined,
                                  color: c.isArchived
                                      ? AppColors.textSecondary
                                      : AppColors.primary),
                            ),
                            title: Text(c.title),
                            subtitle: Text(c.isArchived
                                ? '${_frequencyLabel(c.frequency)} • Arquivado'
                                : _frequencyLabel(c.frequency)),
                            trailing: widget.canEdit
                                ? PopupMenuButton<String>(
                                    tooltip: 'Ações do checklist',
                                    onSelected: (v) async {
                                      if (v == 'edit') {
                                        await context.push(
                                            AppRoutes.editarChecklist(c.id));
                                        _load();
                                      }
                                      if (v == 'archive' ||
                                          v == 'unarchive') {
                                        _toggleArquivar(c);
                                      }
                                      if (v == 'disable') _desativar(c);
                                    },
                                    itemBuilder: (_) => c.isArchived
                                        ? const [
                                            PopupMenuItem(
                                              value: 'unarchive',
                                              child: ListTile(
                                                contentPadding:
                                                    EdgeInsets.zero,
                                                dense: true,
                                                leading: Icon(
                                                    Icons.unarchive_outlined),
                                                title: Text(
                                                    'Voltar à operação'),
                                              ),
                                            ),
                                          ]
                                        : const [
                                            PopupMenuItem(
                                              value: 'edit',
                                              child: ListTile(
                                                contentPadding:
                                                    EdgeInsets.zero,
                                                dense: true,
                                                leading:
                                                    Icon(Icons.edit_outlined),
                                                title: Text('Editar'),
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'archive',
                                              child: ListTile(
                                                contentPadding:
                                                    EdgeInsets.zero,
                                                dense: true,
                                                leading: Icon(Icons
                                                    .inventory_2_outlined),
                                                title: Text('Arquivar'),
                                                subtitle: Text(
                                                    'Sai dos indicadores'),
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'disable',
                                              child: ListTile(
                                                contentPadding:
                                                    EdgeInsets.zero,
                                                dense: true,
                                                leading: Icon(
                                                    Icons.block_outlined),
                                                title: Text('Desativar'),
                                              ),
                                            ),
                                          ],
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
            );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Aba 3 — Tarefas do setor (agrupadas por mês, com busca por código)
// ═══════════════════════════════════════════════════════════════════════════

class _TarefasTab extends StatefulWidget {
  final String sectorId;
  final bool canEdit;

  const _TarefasTab({required this.sectorId, required this.canEdit});

  @override
  State<_TarefasTab> createState() => _TarefasTabState();
}

class _TarefasTabState extends State<_TarefasTab> {
  final _db = Supabase.instance.client;
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  List<_SectorTaskView> _tasks = [];
  String _search = '';
  String? _filterStatus;

  /// Chaves de mês (yyyy-MM) colapsadas. O mês mais recente inicia aberto —
  /// na primeira carga todos os outros entram neste conjunto.
  final Set<String> _collapsed = {};
  bool _collapsedInitialized = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final tasksData = await _db
          .from('tasks')
          .select()
          .eq('sector_id', widget.sectorId)
          // Tarefa cancelada (serie interrompida) sai das listas.
          .neq('status', 'cancelled')
          .order('due_date', ascending: false);

      final tasks = (tasksData as List)
          .map((e) => Task.fromJson(e as Map<String, dynamic>))
          .toList();

      // Enriquecimento: título do checklist + nome do Inspetor
      final checklistIds = tasks.map((t) => t.checklistId).toSet().toList();
      final inspectorIds = tasks.map((t) => t.inspectorId).toSet().toList();

      final checklistMap = <String, Checklist>{};
      if (checklistIds.isNotEmpty) {
        final rows =
            await _db.from('checklists').select().inFilter('id', checklistIds);
        for (final r in rows) {
          final c = Checklist.fromJson(r);
          checklistMap[c.id] = c;
        }
      }

      final inspectorMap = <String, Profile>{};
      if (inspectorIds.isNotEmpty) {
        final rows =
            await _db.from('profiles').select().inFilter('id', inspectorIds);
        for (final r in rows) {
          final p = Profile.fromJson(r);
          inspectorMap[p.id] = p;
        }
      }

      if (mounted) {
        setState(() {
          _tasks = tasks
              .map((t) => _SectorTaskView(
                    task: t,
                    checklist: checklistMap[t.checklistId],
                    inspector: inspectorMap[t.inspectorId],
                  ))
              .toList();
          _loading = false;
        });
        _initCollapsed();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Colapsa todos os meses exceto o mais recente (só na primeira carga).
  void _initCollapsed() {
    if (_collapsedInitialized) return;
    final keys = _monthKeysOrdered(_tasks);
    if (keys.isEmpty) return;
    setState(() {
      _collapsed
        ..clear()
        ..addAll(keys.skip(1));
      _collapsedInitialized = true;
    });
  }

  List<String> _monthKeysOrdered(List<_SectorTaskView> items) {
    final keys = <String>{};
    for (final tv in items) {
      keys.add(_monthKey(tv.task.dueDate));
    }
    return keys.toList()..sort((a, b) => b.compareTo(a));
  }

  String _monthKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  List<_SectorTaskView> get _filtered {
    final query = _search.trim().toLowerCase();
    return _tasks.where((tv) {
      final task = tv.task;
      if (_filterStatus != null) {
        if (_filterStatus == 'overdue') {
          if (!task.isOverdue) return false;
        } else if (task.status != _filterStatus) {
          return false;
        }
      }
      if (query.isEmpty) return true;
      return task.displayCode.toLowerCase().contains(query) ||
          (tv.checklist?.title.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  Future<void> _abrirRelatorio(Task task) async {
    try {
      final insp = await _db
          .from('inspections')
          .select('id')
          .eq('task_id', task.id)
          .order('created_at', ascending: false)
          .limit(1);
      if (insp.isNotEmpty && mounted) {
        context.push(AppRoutes.relatorioIndividual(insp.first['id'] as String));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Erro ao abrir o relatório.'),
          backgroundColor: AppColors.nonCompliant,
        ));
      }
    }
  }

  Future<void> _atribuirTarefa() async {
    await context.push(AppRoutes.atribuirTarefaNoSetor(widget.sectorId));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    final monthKeys = _monthKeysOrdered(items);
    final monthFmt = DateFormat('MMMM yyyy', 'pt_BR');

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: widget.canEdit
          ? FloatingActionButton.extended(
              heroTag: 'fab_tarefa_setor',
              onPressed: _atribuirTarefa,
              icon: const Icon(Icons.assignment_add),
              label: const Text('Atribuir tarefa'),
            )
          : null,
      body: Column(
        children: [
          // ── Busca por código + filtro de status ────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              maxLength: 60,
              decoration: InputDecoration(
                counterText: '',
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: 'Buscar por código (ex.: OS-2026-00001)',
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _statusChip(null, 'Todas'),
                _statusChip('pending', 'Pendente'),
                _statusChip('in_progress', 'Em andamento'),
                _statusChip('submitted', 'Enviado'),
                _statusChip('validated', 'Validado'),
                _statusChip('overdue', 'Atrasado'),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: _loading
                ? const SkeletonList(itemHeight: 88)
                : items.isEmpty
                    ? EmptyState(
                        icon: Icons.view_kanban_outlined,
                        title: 'Nenhuma tarefa encontrada',
                        subtitle: _search.isNotEmpty || _filterStatus != null
                            ? 'Ajuste a busca ou os filtros.'
                            : 'Atribua a primeira tarefa deste setor a um Inspetor.',
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                          itemCount: monthKeys.length,
                          itemBuilder: (ctx, i) {
                            final key = monthKeys[i];
                            final monthTasks = items
                                .where(
                                    (tv) => _monthKey(tv.task.dueDate) == key)
                                .toList();
                            final parts = key.split('-');
                            final headerDate = DateTime(
                                int.parse(parts[0]), int.parse(parts[1]));
                            final collapsed = _collapsed.contains(key);

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => setState(() {
                                    if (collapsed) {
                                      _collapsed.remove(key);
                                    } else {
                                      _collapsed.add(key);
                                    }
                                  }),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 8, horizontal: 4),
                                    child: Row(
                                      children: [
                                        Icon(
                                          collapsed
                                              ? Icons.chevron_right
                                              : Icons.expand_more,
                                          size: 20,
                                          color: AppColors.textSecondary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          monthFmt.format(headerDate),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall,
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 7, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary50,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            '${monthTasks.length}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (!collapsed)
                                  ...monthTasks.map((tv) => _SectorTaskCard(
                                        view: tv,
                                        onOpenReport: () =>
                                            _abrirRelatorio(tv.task),
                                      )),
                                const SizedBox(height: 8),
                              ],
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String? value, String label) {
    final selected = _filterStatus == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _filterStatus = value),
      ),
    );
  }
}

class _SectorTaskView {
  final Task task;
  final Checklist? checklist;
  final Profile? inspector;
  _SectorTaskView({required this.task, this.checklist, this.inspector});
}

class _SectorTaskCard extends StatelessWidget {
  final _SectorTaskView view;
  final VoidCallback onOpenReport;

  const _SectorTaskCard({required this.view, required this.onOpenReport});

  @override
  Widget build(BuildContext context) {
    final task = view.task;
    final concluida = task.status == 'submitted' || task.status == 'validated';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
        onTap: concluida ? onOpenReport : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      view.checklist?.title ?? 'Checklist removido',
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusBadge(
                    status: task.isOverdue ? 'overdue' : task.status,
                    compact: true,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                task.displayCode,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.person_outline,
                      size: 13, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      view.inspector?.fullName ?? '—',
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 13,
                    color: task.isOverdue
                        ? AppColors.nonCompliant
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    AppDateUtils.formatDate(task.dueDate),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: task.isOverdue
                              ? AppColors.nonCompliant
                              : AppColors.textSecondary,
                          fontWeight: task.isOverdue ? FontWeight.w600 : null,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Aba 4 — Equipe do setor
// ═══════════════════════════════════════════════════════════════════════════

class _EquipeTab extends StatefulWidget {
  final Sector sector;
  final Profile? owner;
  final bool canEdit;

  const _EquipeTab({
    required this.sector,
    required this.owner,
    required this.canEdit,
  });

  @override
  State<_EquipeTab> createState() => _EquipeTabState();
}

class _EquipeTabState extends State<_EquipeTab> {
  final _db = Supabase.instance.client;
  bool _loading = true;
  List<Profile> _inspetores = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final links = await _db
          .from('inspector_sectors')
          .select('inspector_id')
          .eq('sector_id', widget.sector.id)
          .eq('status', 'active');

      List<Profile> inspetores = [];
      final ids =
          (links as List).map((e) => e['inspector_id'] as String).toList();
      if (ids.isNotEmpty) {
        final rows = await _db
            .from('profiles')
            .select()
            .inFilter('id', ids)
            .order('full_name', ascending: true);
        inspetores = (rows as List).map((e) => Profile.fromJson(e)).toList();
      }

      if (mounted) {
        setState(() {
          _inspetores = inspetores;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.nonCompliant : AppColors.compliant,
    ));
  }

  /// Dialog de vínculo: lista os Inspetores do hospital e marca os que já
  /// pertencem a este setor. Mesma operação de inspector_sectors usada em
  /// gestao_equipe_screen, aqui na direção "setor → inspetores".
  Future<void> _vincularInspetores() async {
    final profile = context.read<AuthProvider>().profile;
    if (profile == null || profile.hospitalId == null) return;
    final hospitalId = profile.hospitalId!;

    List<Profile> todos;
    Set<String> vinculados;
    try {
      final rows = await _db
          .from('profiles')
          .select()
          .eq('hospital_id', hospitalId)
          .eq('role', 'inspector')
          .eq('status', 'active')
          .order('full_name', ascending: true);
      todos = (rows as List).map((e) => Profile.fromJson(e)).toList();

      final links = await _db
          .from('inspector_sectors')
          .select('inspector_id')
          .eq('sector_id', widget.sector.id)
          .eq('status', 'active');
      vinculados =
          (links as List).map((e) => e['inspector_id'] as String).toSet();
    } catch (_) {
      _showSnack('Erro ao carregar Inspetores.', error: true);
      return;
    }

    if (!mounted) return;
    final selecionados = Set<String>.from(vinculados);

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Inspetores de ${widget.sector.name}'),
          content: SizedBox(
            width: double.maxFinite,
            child: todos.isEmpty
                ? const Text(
                    'Nenhum Inspetor ativo neste hospital. '
                    'Convide um Inspetor pela tela de Equipe.')
                : ListView(
                    shrinkWrap: true,
                    children: todos
                        .map((p) => CheckboxListTile(
                              title: Text(p.fullName),
                              subtitle: Text(p.email),
                              value: selecionados.contains(p.id),
                              onChanged: (v) => setDialogState(() {
                                if (v == true) {
                                  selecionados.add(p.id);
                                } else {
                                  selecionados.remove(p.id);
                                }
                              }),
                            ))
                        .toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );

    if (confirmou != true || !mounted) return;

    final adicionar = selecionados.difference(vinculados);
    final remover = vinculados.difference(selecionados);
    if (adicionar.isEmpty && remover.isEmpty) return;

    try {
      if (adicionar.isNotEmpty) {
        await _db.from('inspector_sectors').upsert(
              adicionar
                  .map((inspectorId) => {
                        'inspector_id': inspectorId,
                        'sector_id': widget.sector.id,
                        'assigned_by': profile.id,
                        'status': 'active',
                      })
                  .toList(),
              onConflict: 'inspector_id,sector_id',
            );
      }
      if (remover.isNotEmpty) {
        await _db
            .from('inspector_sectors')
            .update({'status': 'inactive'})
            .eq('sector_id', widget.sector.id)
            .inFilter('inspector_id', remover.toList());
      }

      await AuditService.log(
        userId: profile.id,
        hospitalId: profile.hospitalId,
        action: 'vincular_inspetor_setores',
        entityType: 'sector',
        entityId: widget.sector.id,
        details: {
          'adicionados': adicionar.toList(),
          'removidos': remover.toList(),
        },
      );

      _showSnack('Equipe do setor atualizada.');
      _load();
    } on PostgrestException catch (e) {
      _showSnack('Erro ao salvar: ${e.message}', error: true);
    } catch (_) {
      _showSnack('Erro ao salvar vínculos.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: widget.canEdit
          ? FloatingActionButton.extended(
              heroTag: 'fab_equipe_setor',
              onPressed: _vincularInspetores,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Vincular Inspetor'),
            )
          : null,
      body: _loading
          ? const SkeletonList(itemHeight: 72)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppDimensions.screenPadding,
                    AppDimensions.screenPadding,
                    AppDimensions.screenPadding,
                    88),
                children: [
                  Text(
                    'Supervisor responsável',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: widget.owner != null
                            ? AppColors.primary
                            : AppColors.textDisabled,
                        child: Icon(
                          widget.owner != null
                              ? Icons.supervisor_account_outlined
                              : Icons.person_off_outlined,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      title: Text(
                          widget.owner?.fullName ?? 'Sem Supervisor vinculado'),
                      subtitle: Text(widget.owner?.email ??
                          'Setor gerenciado diretamente pelo Diretor'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Inspetores vinculados',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  if (_inspetores.isEmpty)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.info_outline,
                            color: AppColors.textSecondary),
                        title: const Text('Nenhum Inspetor vinculado'),
                        subtitle: Text(widget.canEdit
                            ? 'Use "Vincular Inspetor" para adicionar.'
                            : 'Peça ao Diretor para vincular Inspetores.'),
                      ),
                    )
                  else
                    ..._inspetores.map((p) => Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppColors.compliant,
                              child: Text(
                                p.fullName
                                    .split(' ')
                                    .map((w) => w.isNotEmpty ? w[0] : '')
                                    .take(2)
                                    .join(),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12),
                              ),
                            ),
                            title: Text(p.fullName),
                            subtitle: Text(p.email),
                          ),
                        )),
                ],
              ),
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Aba 5 — Histórico de inspeções do setor
// ═══════════════════════════════════════════════════════════════════════════

class _HistoricoTab extends StatefulWidget {
  final String sectorId;
  const _HistoricoTab({required this.sectorId});

  @override
  State<_HistoricoTab> createState() => _HistoricoTabState();
}

class _HistoricoTabState extends State<_HistoricoTab> {
  final _db = Supabase.instance.client;
  bool _loading = true;
  List<_InspectionView> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _db
          .from('inspections')
          .select(
              'id, checklist_id, inspector_id, submitted_at, overall_status')
          .eq('sector_id', widget.sectorId)
          .inFilter('overall_status', ['submitted', 'validated'])
          .order('submitted_at', ascending: false);

      final list = (rows as List).cast<Map<String, dynamic>>();

      final checklistIds =
          list.map((e) => e['checklist_id'] as String).toSet().toList();
      final inspectorIds =
          list.map((e) => e['inspector_id'] as String).toSet().toList();

      final checklistMap = <String, Checklist>{};
      if (checklistIds.isNotEmpty) {
        final cl =
            await _db.from('checklists').select().inFilter('id', checklistIds);
        for (final c in cl) {
          final parsed = Checklist.fromJson(c);
          checklistMap[parsed.id] = parsed;
        }
      }

      final inspectorMap = <String, Profile>{};
      if (inspectorIds.isNotEmpty) {
        final ps =
            await _db.from('profiles').select().inFilter('id', inspectorIds);
        for (final p in ps) {
          final parsed = Profile.fromJson(p);
          inspectorMap[parsed.id] = parsed;
        }
      }

      if (mounted) {
        setState(() {
          _items = list
              .map((e) => _InspectionView(
                    id: e['id'] as String,
                    status: e['overall_status'] as String,
                    submittedAt:
                        AppDateUtils.parseDate(e['submitted_at'] as String?),
                    checklistTitle:
                        checklistMap[e['checklist_id']]?.title ?? 'Checklist',
                    inspectorName:
                        inspectorMap[e['inspector_id']]?.fullName ?? '—',
                  ))
              .toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SkeletonList(itemHeight: 80);

    if (_items.isEmpty) {
      return const EmptyState(
        icon: Icons.history_outlined,
        title: 'Nenhuma inspeção concluída',
        subtitle:
            'As inspeções enviadas pelos Inspetores deste setor aparecem aqui.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppDimensions.screenPadding),
        itemCount: _items.length,
        itemBuilder: (ctx, i) {
          final item = _items[i];
          return Card(
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.compliant50,
                child: Icon(Icons.assignment_turned_in_outlined,
                    color: AppColors.compliant),
              ),
              title: Text(item.checklistTitle),
              subtitle: Text(
                '${item.inspectorName}  •  '
                '${item.submittedAt != null ? AppDateUtils.formatDateTime(item.submittedAt!) : '—'}',
              ),
              trailing: StatusBadge(status: item.status, compact: true),
              onTap: () => context.push(AppRoutes.relatorioIndividual(item.id)),
            ),
          );
        },
      ),
    );
  }
}

class _InspectionView {
  final String id;
  final String status;
  final DateTime? submittedAt;
  final String checklistTitle;
  final String inspectorName;

  _InspectionView({
    required this.id,
    required this.status,
    required this.submittedAt,
    required this.checklistTitle,
    required this.inspectorName,
  });
}
