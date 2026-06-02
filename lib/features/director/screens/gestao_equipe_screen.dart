import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
    if (profile?.hospitalId == null) return;
    _hospitalId = profile!.hospitalId!;

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

      final setoresData = await _db
          .from('sectors')
          .select()
          .eq('hospital_id', _hospitalId)
          .eq('status', 'active')
          .order('name');

      if (mounted) {
        setState(() {
          _supervisores = sups.map(Profile.fromJson).toList();
          _inspetores = insp.map(Profile.fromJson).toList();
          _setores = setoresData.map(Sector.fromJson).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.nonCompliant : AppColors.compliant,
    ));
  }

  // ── Vincular usuário (supervisor ou inspector) ─────────────────────────────
  Future<void> _vincular(String role) async {
    final searchCtrl = TextEditingController();
    List<Profile> results = [];
    List<String> selectedSectorIds = [];
    Profile? selectedProfile;
    bool searching = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> buscar(String q) async {
            if (q.trim().isEmpty) {
              setLocal(() => results = []);
              return;
            }
            setLocal(() => searching = true);
            final data = await _db
                .from('profiles')
                .select()
                .eq('status', 'active')
                .isFilter('role', null)
                .isFilter('hospital_id', null)
                .or('email.ilike.%${q.trim()}%,full_name.ilike.%${q.trim()}%,cpf.ilike.%${CpfUtils.strip(q.trim())}%');
            setLocal(() {
              results = data.map(Profile.fromJson).toList();
              searching = false;
            });
          }

          return AlertDialog(
            title: Text(
                'Vincular ${role == 'supervisor' ? 'Supervisor' : 'Inspetor'}'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selectedProfile == null) ...[
                    TextField(
                      controller: searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Buscar por e-mail, nome ou CPF...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: searching
                            ? const Padding(
                                padding: EdgeInsets.all(10),
                                child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)),
                              )
                            : null,
                      ),
                      onChanged: buscar,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 200,
                      child: ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (_, i) => ListTile(
                          title: Text(results[i].fullName),
                          subtitle: Text(
                              '${results[i].email}  •  ${CpfUtils.mask(results[i].cpf)}'),
                          onTap: () =>
                              setLocal(() => selectedProfile = results[i]),
                        ),
                      ),
                    ),
                  ] else ...[
                    ListTile(
                      leading: const Icon(Icons.person, color: AppColors.primary),
                      title: Text(selectedProfile!.fullName),
                      subtitle: Text(selectedProfile!.email),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () =>
                            setLocal(() => selectedProfile = null),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('Selecionar setor(es):'),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 200,
                      child: ListView(
                        children: _setores.map((s) {
                          final selected =
                              selectedSectorIds.contains(s.id);
                          return CheckboxListTile(
                            title: Text(s.name),
                            value: selected,
                            onChanged: (v) {
                              setLocal(() {
                                if (v == true) {
                                  selectedSectorIds.add(s.id);
                                } else {
                                  selectedSectorIds.remove(s.id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
              if (selectedProfile != null &&
                  selectedSectorIds.isNotEmpty)
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _confirmarVinculo(
                        selectedProfile!, role, selectedSectorIds);
                  },
                  child: const Text('Confirmar'),
                ),
            ],
          );
        },
      ),
    );
    searchCtrl.dispose();
  }

  Future<void> _confirmarVinculo(
      Profile profile, String role, List<String> sectorIds) async {
    final auth = context.read<AuthProvider>();
    final myProfile = auth.profile!;

    try {
      // Atualiza role e hospital_id no perfil
      await _db.from('profiles').update({
        'role': role,
        'hospital_id': _hospitalId,
      }).eq('id', profile.id);

      if (role == 'inspector') {
        // Cria entradas em inspector_sectors para cada setor selecionado
        final entries = sectorIds.map((sid) => {
              'inspector_id': profile.id,
              'sector_id': sid,
              'assigned_by': myProfile.id,
              'status': 'active',
            }).toList();
        await _db.from('inspector_sectors').upsert(entries,
            onConflict: 'inspector_id,sector_id');
      } else if (role == 'supervisor' && sectorIds.isNotEmpty) {
        // Define o setor principal do supervisor (owner do primeiro setor selecionado)
        await _db.from('sectors').update({
          'owner_supervisor_id': profile.id,
        }).eq('id', sectorIds.first);
      }

      await AuditService.log(
        userId: myProfile.id,
        hospitalId: _hospitalId,
        action: 'vincular_${role == 'supervisor' ? 'supervisor' : 'inspetor'}',
        entityType: 'profile',
        entityId: profile.id,
        details: {'sector_ids': sectorIds},
      );

      _showSnack(
          '${profile.fullName} vinculado como ${role == 'supervisor' ? 'Supervisor' : 'Inspetor'}.');
      _load();
    } on PostgrestException catch (e) {
      debugPrint(
        '[GestaoEquipe] _confirmarVinculo PostgrestException:\n'
        '  message: ${e.message}\n'
        '  code:    ${e.code}\n'
        '  details: ${e.details}\n'
        '  hint:    ${e.hint}',
      );
      _showSnack('Erro ao vincular: ${e.message}', error: true);
    } catch (e) {
      debugPrint('[GestaoEquipe] _confirmarVinculo erro inesperado: $e');
      _showSnack('Erro inesperado ao vincular.', error: true);
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
        onPressed: () => _vincular(_tab.index == 0 ? 'supervisor' : 'inspector'),
        icon: const Icon(Icons.person_add_outlined),
        label: Text(_tab.index == 0 ? 'Vincular Supervisor' : 'Vincular Inspetor'),
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
  final String emptyMsg;

  const _UserList({
    required this.users,
    required this.setores,
    required this.onDesativar,
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
              },
              itemBuilder: (_) => [
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
