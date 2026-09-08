import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/profile.dart';
import '../../../core/models/sector.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/utils/cpf_utils.dart';
import '../../auth/providers/auth_provider.dart';
import '../../shared/screens/convites_enviados_screen.dart';
import 'acesso_compartilhado_screen.dart';
import 'pedidos_acesso_screen.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/skeleton_loader.dart';

class GestaoEquipeScreen extends StatefulWidget {
  const GestaoEquipeScreen({super.key});

  @override
  State<GestaoEquipeScreen> createState() => _GestaoEquipeScreenState();
}

class _GestaoEquipeScreenState extends State<GestaoEquipeScreen>
    with SingleTickerProviderStateMixin {
  final _db = Supabase.instance.client;
  late final TabController _tab;

  bool _loading = true;
  List<Profile> _supervisores = [];
  List<Profile> _inspetores = [];
  List<Sector> _setores = [];
  String _hospitalId = '';
  String? _myRole;

  bool get _isDirector => _myRole == 'director';

  @override
  void initState() {
    super.initState();
    // Diretor: Membros | Convites | Pedidos de acesso | Acesso compartilhado
    // Supervisor: Inspetores | Convites | Acesso compartilhado
    //   (sem "Pedidos de acesso" — quem resolve pedidos é o Diretor/owner
    //    pela tela dedicada; aqui o Supervisor gerencia o que ele concede)
    final role = context.read<AuthProvider>().profile?.role;
    _myRole = role;
    _tab = TabController(length: role == 'director' ? 4 : 3, vsync: this);
    // O FAB muda conforme a aba: sem isto, "Convidar usuário" ficava
    // pairando sobre abas que não têm essa ação.
    _tab.addListener(_onTabChanged);
    _load();
  }

  @override
  void dispose() {
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tab.indexIsChanging) return;
    setState(() {});
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = context.read<AuthProvider>().profile;
    if (profile?.hospitalId == null) {
      // Perfil ainda nao carregado: encerra o loading para
      // a tela nao ficar presa no skeleton indefinidamente.
      if (mounted) setState(() => _loading = false);
      return;
    }
    _hospitalId = profile!.hospitalId!;
    _myRole = profile.role;

    try {
      final sups = await _db
          .from('profiles')
          .select()
          .eq('hospital_id', _hospitalId)
          .eq('role', 'supervisor')
          .order('full_name', ascending: true);

      final insp = await _db
          .from('profiles')
          .select()
          .eq('hospital_id', _hospitalId)
          .eq('role', 'inspector')
          .order('full_name', ascending: true);

      final setores = await _loadSetoresGerenciaveis(profile);

      if (mounted) {
        setState(() {
          _supervisores = sups.map(Profile.fromJson).toList();
          _inspetores = insp.map(Profile.fromJson).toList();
          _setores = setores;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Setores que o usuário logado pode gerenciar vínculos de Inspetor.
  /// Diretor: todos os setores ativos do hospital.
  /// Supervisor: apenas setores onde é owner ou tem sector_access.can_edit
  /// (mesma regra da policy inspector_sectors_supervisor_insert/update —
  /// filtrar aqui evita que o Supervisor marque um setor no dialog e a
  /// operação inteira falhe por RLS).
  Future<List<Sector>> _loadSetoresGerenciaveis(Profile profile) async {
    if (profile.role == 'director') {
      final data = await _db
          .from('sectors')
          .select()
          .eq('hospital_id', _hospitalId)
          .eq('status', 'active')
          .order('name', ascending: true);
      return (data as List).map((e) => Sector.fromJson(e)).toList();
    }

    final owned = await _db
        .from('sectors')
        .select()
        .eq('hospital_id', _hospitalId)
        .eq('status', 'active')
        .eq('owner_supervisor_id', profile.id);

    final accessRows = await _db
        .from('sector_access')
        .select('sector_id')
        .eq('supervisor_id', profile.id)
        .eq('can_edit', true);
    final accessIds =
        (accessRows as List).map((r) => r['sector_id'] as String).toList();

    final byId = <String, Sector>{
      for (final e in (owned as List)) (e['id'] as String): Sector.fromJson(e),
    };

    if (accessIds.isNotEmpty) {
      final shared = await _db
          .from('sectors')
          .select()
          .eq('hospital_id', _hospitalId)
          .eq('status', 'active')
          .inFilter('id', accessIds);
      for (final e in (shared as List)) {
        byId[e['id'] as String] = Sector.fromJson(e);
      }
    }

    return byId.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.nonCompliant : AppColors.compliant,
    ));
  }

  // A vinculação de Supervisor/Inspetor ao hospital agora é feita por
  // convite via código de perfil — o botão "Convidar usuário" abre a tela
  // dedicada. O vínculo de setores do Inspetor (inspector_sectors), porém,
  // não faz parte desse convite e é gerenciado aqui.

  Future<void> _gerenciarSetores(Profile inspetor) async {
    Set<String> vinculados;
    try {
      final data = await _db
          .from('inspector_sectors')
          .select('sector_id')
          .eq('inspector_id', inspetor.id)
          .eq('status', 'active');
      vinculados = (data as List).map((e) => e['sector_id'] as String).toSet();
    } catch (_) {
      if (mounted) _showSnack('Erro ao carregar setores do Inspetor.', error: true);
      return;
    }

    if (!mounted) return;
    final selecionados = Set<String>.from(vinculados);

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Setores de ${inspetor.fullName}'),
          content: SizedBox(
            width: double.maxFinite,
            child: _setores.isEmpty
                ? Text(_myRole == 'supervisor'
                    ? 'Você não é dono nem tem acesso de edição a nenhum setor.'
                    : 'Nenhum setor cadastrado neste hospital.')
                : ListView(
                    shrinkWrap: true,
                    children: _setores
                        .map((s) => CheckboxListTile(
                              title: Text(s.name),
                              value: selecionados.contains(s.id),
                              onChanged: (v) {
                                setDialogState(() {
                                  if (v == true) {
                                    selecionados.add(s.id);
                                  } else {
                                    selecionados.remove(s.id);
                                  }
                                });
                              },
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

    final auth = context.read<AuthProvider>();
    final adicionar = selecionados.difference(vinculados);
    final remover = vinculados.difference(selecionados);

    try {
      if (adicionar.isNotEmpty) {
        await _db.from('inspector_sectors').upsert(
              adicionar
                  .map((sectorId) => {
                        'inspector_id': inspetor.id,
                        'sector_id': sectorId,
                        'assigned_by': auth.profile!.id,
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
            .eq('inspector_id', inspetor.id)
            .inFilter('sector_id', remover.toList());
      }

      await AuditService.log(
        userId: auth.profile!.id,
        hospitalId: _hospitalId,
        action: 'vincular_inspetor_setores',
        entityType: 'profile',
        entityId: inspetor.id,
        details: {
          'adicionados': adicionar.toList(),
          'removidos': remover.toList(),
        },
      );

      if (mounted) _showSnack('Setores de ${inspetor.fullName} atualizados.');
    } on PostgrestException catch (e) {
      if (mounted) _showSnack('Erro ao salvar: ${e.message}', error: true);
    } catch (_) {
      if (mounted) _showSnack('Erro ao salvar vínculos.', error: true);
    }
  }

  /// Desativa OU reativa um membro (soft delete — nunca DELETE).
  ///
  /// Reativar é reversível e não destrutivo: ganhou diálogo e cor próprios
  /// em vez de reaproveitar o alerta vermelho de "Desativar", que dizia a
  /// coisa errada para quem só queria trazer alguém de volta (bloco 2).
  Future<void> _desativar(Profile p) async {
    final auth = context.read<AuthProvider>();
    final desativando = p.isActive;

    // Supervisor com tarefas ativas NO PRÓPRIO ESCOPO exige transferência.
    // Antes a contagem pegava as tarefas do hospital inteiro, então qualquer
    // tarefa pendente em qualquer setor bloqueava a desativação de qualquer
    // Supervisor — inclusive de um sem nenhum setor.
    if (desativando && p.role == 'supervisor') {
      final bloqueado = await _supervisorTemTarefasAtivas(p.id);
      if (!mounted) return;
      if (bloqueado) {
        _showSnack(
          'Este Supervisor tem tarefas ativas nos setores dele. '
          'Transfira as tarefas antes de desativar.',
          error: true,
        );
        return;
      }
    }

    final confirm = await confirmAction(
      context,
      title: desativando ? 'Desativar usuário?' : 'Reativar usuário?',
      message: desativando
          ? '"${p.fullName}" perde o acesso ao sistema. O histórico e as '
              'inspeções já feitas são preservados e você pode reativar '
              'quando quiser.'
          : '"${p.fullName}" volta a ter acesso ao sistema com o mesmo '
              'perfil de antes.',
      confirmLabel: desativando ? 'Desativar' : 'Reativar',
      destructive: desativando,
      icon: desativando ? Icons.person_off_outlined : Icons.person_outline,
    );

    if (!confirm || !mounted) return;

    try {
      await _db
          .from('profiles')
          .update({'status': desativando ? 'inactive' : 'active'})
          .eq('id', p.id);

      await AuditService.log(
        userId: auth.profile!.id,
        hospitalId: _hospitalId,
        action: desativando ? 'desativar_usuario' : 'reativar_usuario',
        entityType: 'profile',
        entityId: p.id,
        details: {'name': p.fullName, 'role': p.role},
      );

      _showSnack(desativando ? 'Usuário desativado.' : 'Usuário reativado.');
      _load();
    } on PostgrestException catch (e) {
      debugPrint('[GestaoEquipe] _desativar PostgrestException: ${e.message} | ${e.code}');
      _showSnack('Erro ao salvar: ${e.message}', error: true);
    } catch (e) {
      debugPrint('[GestaoEquipe] _desativar erro inesperado: $e');
      _showSnack('Erro inesperado ao salvar.', error: true);
    }
  }

  /// Há tarefa pendente/em andamento em algum setor deste Supervisor?
  /// Escopo = setores onde é owner + setores com sector_access.
  Future<bool> _supervisorTemTarefasAtivas(String supervisorId) async {
    try {
      final ids = <String>{};

      final owned = await _db
          .from('sectors')
          .select('id')
          .eq('hospital_id', _hospitalId)
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

      if (ids.isEmpty) return false;

      final tasks = await _db
          .from('tasks')
          .select('id')
          .eq('hospital_id', _hospitalId)
          .inFilter('sector_id', ids.toList())
          .inFilter('status', ['pending', 'in_progress']);
      return tasks.isNotEmpty;
    } catch (e) {
      debugPrint('[GestaoEquipe] _supervisorTemTarefasAtivas: $e');
      // Na dúvida, bloqueia: desativar um Supervisor com tarefas órfãs é
      // pior que exigir uma tentativa a mais.
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Título da primeira aba: o Supervisor só gerencia Inspetores.
    final primeiraAba = _isDirector ? 'Membros' : 'Inspetores';

    return Scaffold(
      appBar: AppBar(
        title: Text(_isDirector ? 'Equipe' : 'Inspetores'),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: primeiraAba),
            const Tab(text: 'Convites enviados'),
            if (_isDirector) const Tab(text: 'Pedidos de acesso'),
            const Tab(text: 'Acesso compartilhado'),
          ],
        ),
      ),
      // Só a aba de membros tem ação própria. "Convites enviados",
      // "Pedidos de acesso" e "Acesso compartilhado" são listas de
      // acompanhamento — convidar dali não fazia sentido.
      floatingActionButton: _tab.index == 0
          ? FloatingActionButton.extended(
              onPressed: () async {
                await context.push(AppRoutes.convidarUsuario);
                _load();
              },
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Convidar usuário'),
            )
          : null,
      body: _loading
          ? const SkeletonList(itemHeight: 84)
          : TabBarView(
              controller: _tab,
              children: [
                _buildMembrosTab(),
                const ConvitesEnviadosScreen(embedded: true),
                if (_isDirector) const PedidosAcessoScreen(embedded: true),
                const AcessoCompartilhadoScreen(embedded: true),
              ],
            ),
    );
  }

  /// Aba de membros. O Diretor vê Supervisores e Inspetores em seções;
  /// o Supervisor vê apenas os Inspetores (não gerencia Supervisores).
  Widget _buildMembrosTab() {
    if (!_isDirector) {
      return _UserList(
        users: _inspetores,
        setores: _setores,
        onDesativar: _desativar,
        onGerenciarSetores: _gerenciarSetores,
        emptyMsg: 'Nenhum Inspetor vinculado.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppDimensions.screenPadding,
            AppDimensions.screenPadding,
            AppDimensions.screenPadding,
            88),
        children: [
          Text('Supervisores', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_supervisores.isEmpty)
            const _EmptyRow(msg: 'Nenhum Supervisor vinculado.')
          else
            ..._supervisores.map((u) => _UserCard(
                  user: u,
                  onDesativar: _desativar,
                )),
          const SizedBox(height: 20),
          Text('Inspetores', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_inspetores.isEmpty)
            const _EmptyRow(msg: 'Nenhum Inspetor vinculado.')
          else
            ..._inspetores.map((u) => _UserCard(
                  user: u,
                  onDesativar: _desativar,
                  onGerenciarSetores: _gerenciarSetores,
                )),
        ],
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  final String msg;
  const _EmptyRow({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading:
            const Icon(Icons.info_outline, color: AppColors.textSecondary),
        title: Text(msg),
      ),
    );
  }
}

class _UserList extends StatelessWidget {
  final List<Profile> users;
  final List<Sector> setores;
  final Future<void> Function(Profile) onDesativar;
  final Future<void> Function(Profile)? onGerenciarSetores;
  final String emptyMsg;

  const _UserList({
    required this.users,
    required this.setores,
    required this.onDesativar,
    this.onGerenciarSetores,
    required this.emptyMsg,
  });

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return EmptyState(
        icon: Icons.groups_outlined,
        title: emptyMsg,
        subtitle: 'Use "Convidar usuário" para trazer alguém para a equipe. '
            'O vínculo é feito pelo código de perfil.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
          AppDimensions.screenPadding,
          AppDimensions.screenPadding,
          AppDimensions.screenPadding,
          88),
      itemCount: users.length,
      itemBuilder: (ctx, i) => _UserCard(
        user: users[i],
        onDesativar: onDesativar,
        onGerenciarSetores: onGerenciarSetores,
      ),
    );
  }
}

/// Card de membro da equipe — usado tanto na lista simples do Supervisor
/// quanto nas seções (Supervisores / Inspetores) da visão do Diretor.
class _UserCard extends StatelessWidget {
  final Profile user;
  final Future<void> Function(Profile) onDesativar;
  final Future<void> Function(Profile)? onGerenciarSetores;

  const _UserCard({
    required this.user,
    required this.onDesativar,
    this.onGerenciarSetores,
  });

  @override
  Widget build(BuildContext context) {
    final u = user;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              u.isActive ? AppColors.primary : AppColors.textDisabled,
          child: Text(
            u.fullName
                .split(' ')
                .map((w) => w.isNotEmpty ? w[0] : '')
                .take(2)
                .join(),
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        title: Text(u.fullName),
        // CPF sempre mascarado (só os 4 últimos dígitos).
        subtitle: Text('${u.email}  •  ${CpfUtils.mask(u.cpf)}'),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'desativar') onDesativar(u);
            if (v == 'setores' && onGerenciarSetores != null) {
              onGerenciarSetores!(u);
            }
          },
          itemBuilder: (_) => [
            if (onGerenciarSetores != null)
              const PopupMenuItem(value: 'setores', child: Text('Setores')),
            PopupMenuItem(
              value: 'desativar',
              child: Text(u.isActive ? 'Desativar' : 'Reativar'),
            ),
          ],
        ),
      ),
    );
  }
}
