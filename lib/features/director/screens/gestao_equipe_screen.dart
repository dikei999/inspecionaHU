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

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
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
          .order('full_name');

      final insp = await _db
          .from('profiles')
          .select()
          .eq('hospital_id', _hospitalId)
          .eq('role', 'inspector')
          .order('full_name');

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
          .order('name');
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

  Future<void> _desativar(Profile p) async {
    final auth = context.read<AuthProvider>();

    // Verifica tarefas ativas do supervisor
    if (p.role == 'supervisor') {
      final tasks = await _db
          .from('tasks')
          .select('id')
          .eq('hospital_id', _hospitalId)
          .inFilter('status', ['pending', 'in_progress']);
      if (!mounted) return;
      if (tasks.isNotEmpty) {
        _showSnack(
          'Transfira as tarefas ativas deste Supervisor antes de desativar.',
          error: true,
        );
        return;
      }
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desativar usuário?'),
        content: Text('Desativar "${p.fullName}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
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
          .from('profiles')
          .update({'status': 'inactive'})
          .eq('id', p.id);

      await AuditService.log(
        userId: auth.profile!.id,
        hospitalId: _hospitalId,
        action: 'desativar_usuario',
        entityType: 'profile',
        entityId: p.id,
        details: {'name': p.fullName, 'role': p.role},
      );

      _showSnack('Usuário desativado.');
      _load();
    } on PostgrestException catch (e) {
      debugPrint('[GestaoEquipe] _desativar PostgrestException: ${e.message} | ${e.code}');
      _showSnack('Erro ao desativar: ${e.message}', error: true);
    } catch (e) {
      debugPrint('[GestaoEquipe] _desativar erro inesperado: $e');
      _showSnack('Erro inesperado ao desativar.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Equipe'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Supervisores'),
            Tab(text: 'Inspetores'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.convidarUsuario),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Convidar usuário'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [
                _UserList(
                  users: _supervisores,
                  setores: _setores,
                  onDesativar: _desativar,
                  emptyMsg: 'Nenhum Supervisor vinculado.',
                ),
                _UserList(
                  users: _inspetores,
                  setores: _setores,
                  onDesativar: _desativar,
                  onGerenciarSetores: _gerenciarSetores,
                  emptyMsg: 'Nenhum Inspetor vinculado.',
                ),
              ],
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
      return Center(child: Text(emptyMsg));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(AppDimensions.screenPadding),
      itemCount: users.length,
      itemBuilder: (ctx, i) {
        final u = users[i];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: u.isActive
                  ? AppColors.primary
                  : AppColors.textDisabled,
              child: Text(
                u.fullName.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join(),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
            title: Text(u.fullName),
            subtitle: Text(
                '${u.email}  •  ${CpfUtils.mask(u.cpf)}'),
            trailing: PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'desativar') onDesativar(u);
                if (v == 'setores' && onGerenciarSetores != null) {
                  onGerenciarSetores!(u);
                }
              },
              itemBuilder: (_) => [
                if (onGerenciarSetores != null)
                  const PopupMenuItem(
                    value: 'setores',
                    child: Text('Setores'),
                  ),
                PopupMenuItem(
                  value: 'desativar',
                  child: Text(u.isActive ? 'Desativar' : 'Reativar'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
