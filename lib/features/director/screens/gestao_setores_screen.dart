import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/profile.dart';
import '../../../core/models/sector.dart';
import '../../../core/services/audit_service.dart';
import '../../auth/providers/auth_provider.dart';

class GestaoSetoresScreen extends StatefulWidget {
  const GestaoSetoresScreen({super.key});

  @override
  State<GestaoSetoresScreen> createState() => _GestaoSetoresScreenState();
}

class _GestaoSetoresScreenState extends State<GestaoSetoresScreen> {
  final _db = Supabase.instance.client;
  bool _loading = true;
  List<_SectorWithSupervisor> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final hospitalId =
        context.read<AuthProvider>().profile?.hospitalId;
    if (hospitalId == null) {
      // Perfil ainda nao carregado: encerra o loading para
      // a tela nao ficar presa no skeleton indefinidamente.
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final setores = await _loadSetores(hospitalId);

      final ownerIds = setores
          .map((s) => s['owner_supervisor_id'] as String?)
          .where((id) => id != null)
          .toSet()
          .toList();

      Map<String, Profile> supervisors = {};
      if (ownerIds.isNotEmpty) {
        final sups = await _db
            .from('profiles')
            .select('id, full_name, cpf')
            .inFilter('id', ownerIds);
        for (final s in sups) {
          supervisors[s['id'] as String] = Profile.fromJson({
            ...s,
            'email': '',
            'status': 'active',
            'created_at': DateTime.now().toIso8601String(),
          });
        }
      }

      if (mounted) {
        setState(() {
          _items = setores.map((s) {
            final sector = Sector.fromJson(s);
            return _SectorWithSupervisor(
              sector: sector,
              supervisor: sector.ownerSupervisorId != null
                  ? supervisors[sector.ownerSupervisorId]
                  : null,
            );
          }).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Diretor vê todos os setores do hospital.
  /// Supervisor vê apenas onde é owner ou tem sector_access (regra do card
  /// "Setores" do dashboard do Supervisor).
  Future<List<Map<String, dynamic>>> _loadSetores(String hospitalId) async {
    final profile = context.read<AuthProvider>().profile;
    if (profile?.role != 'supervisor') {
      final data = await _db
          .from('sectors')
          .select()
          .eq('hospital_id', hospitalId)
          .order('name', ascending: true);
      return (data as List).cast<Map<String, dynamic>>();
    }

    final owned = await _db
        .from('sectors')
        .select()
        .eq('hospital_id', hospitalId)
        .eq('owner_supervisor_id', profile!.id);

    final accessRows = await _db
        .from('sector_access')
        .select('sector_id')
        .eq('supervisor_id', profile.id)
        .eq('can_edit', true);
    final accessIds =
        (accessRows as List).map((r) => r['sector_id'] as String).toList();

    final byId = <String, Map<String, dynamic>>{
      for (final e in (owned as List).cast<Map<String, dynamic>>())
        (e['id'] as String): e,
    };

    if (accessIds.isNotEmpty) {
      final shared = await _db
          .from('sectors')
          .select()
          .eq('hospital_id', hospitalId)
          .inFilter('id', accessIds);
      for (final e in (shared as List).cast<Map<String, dynamic>>()) {
        byId[e['id'] as String] = e;
      }
    }

    final list = byId.values.toList()
      ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return list;
  }

  Future<void> _toggleStatus(Sector sector) async {
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
              child: const Text('Cancelar')),
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
          .update({'status': newStatus})
          .eq('id', sector.id);

      await AuditService.log(
        userId: auth.profile!.id,
        hospitalId: auth.profile!.hospitalId,
        action: '${newStatus == 'inactive' ? 'desativar' : 'reativar'}_setor',
        entityType: 'sector',
        entityId: sector.id,
        details: {'name': sector.name},
      );

      _showSnack('Setor ${newStatus == 'active' ? 'reativado' : 'desativado'}.');
      _load();
    } catch (_) {
      _showSnack('Erro ao alterar status.', error: true);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.nonCompliant : AppColors.compliant,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Setores')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push(AppRoutes.novoSetor);
          _load();
        },
        label: const Text('Novo setor'),
        icon: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? const Center(child: Text('Nenhum setor cadastrado.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(AppDimensions.screenPadding),
                      itemCount: _items.length,
                      itemBuilder: (ctx, i) {
                        final item = _items[i];
                        final s = item.sector;
                        return Card(
                          child: ListTile(
                            onTap: () async {
                              await context
                                  .push(AppRoutes.detalhesSetor(s.id));
                              _load();
                            },
                            leading: CircleAvatar(
                              backgroundColor: s.isActive
                                  ? AppColors.primary.withAlpha(30)
                                  : AppColors.textDisabled.withAlpha(30),
                              child: Icon(
                                Icons.domain_outlined,
                                color: s.isActive
                                    ? AppColors.primary
                                    : AppColors.textDisabled,
                              ),
                            ),
                            title: Text(s.name),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (s.nr32Category != null)
                                  Text(s.nr32Category!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                Text(
                                  item.supervisor != null
                                      ? 'Supervisor: ${item.supervisor!.fullName}'
                                      : 'Sem Supervisor (criado pelo Diretor)',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: item.supervisor != null
                                            ? AppColors.primary
                                            : AppColors.textSecondary,
                                      ),
                                ),
                              ],
                            ),
                            isThreeLine: s.nr32Category != null,
                            // Sem opção "Apagar": setor é sempre soft delete.
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'detalhes') {
                                  context
                                      .push(AppRoutes.detalhesSetor(s.id))
                                      .then((_) => _load());
                                }
                                if (v == 'edit') {
                                  context
                                      .push(AppRoutes.editarSetor(s.id))
                                      .then((_) => _load());
                                }
                                if (v == 'toggle') _toggleStatus(s);
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                    value: 'detalhes',
                                    child: Text('Abrir detalhes')),
                                const PopupMenuItem(
                                    value: 'edit', child: Text('Editar')),
                                PopupMenuItem(
                                  value: 'toggle',
                                  child: Text(
                                      s.isActive ? 'Desativar' : 'Reativar'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

class _SectorWithSupervisor {
  final Sector sector;
  final Profile? supervisor;
  _SectorWithSupervisor({required this.sector, this.supervisor});
}
