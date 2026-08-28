import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/profile.dart';
import '../../../core/models/sector.dart';
import '../../../core/models/sector_access.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/utils/cpf_utils.dart';
import '../../auth/providers/auth_provider.dart';

class AcessoCompartilhadoScreen extends StatefulWidget {
  /// Quando true a tela é renderizada como aba dentro de outra Scaffold
  /// (Equipe) — sem AppBar própria. A lógica de negócio é a mesma.
  final bool embedded;

  const AcessoCompartilhadoScreen({super.key, this.embedded = false});

  @override
  State<AcessoCompartilhadoScreen> createState() =>
      _AcessoCompartilhadoScreenState();
}

class _AcessoCompartilhadoScreenState
    extends State<AcessoCompartilhadoScreen> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  List<_AccessView> _accesses = [];
  List<Sector> _setores = [];
  List<Profile> _supervisores = [];
  String? _hospitalId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = context.read<AuthProvider>().profile;
    _hospitalId = profile?.hospitalId;
    if (_hospitalId == null) {
      // Perfil ainda nao carregado: encerra o loading para
      // a tela nao ficar presa no skeleton indefinidamente.
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final setoresData = await _db
          .from('sectors')
          .select()
          .eq('hospital_id', _hospitalId!)
          .eq('status', 'active')
          .order('name');

      final supsData = await _db
          .from('profiles')
          .select()
          .eq('hospital_id', _hospitalId!)
          .eq('role', 'supervisor')
          .eq('status', 'active')
          .order('full_name');

      final accessData = await _db
          .from('sector_access')
          .select()
          .inFilter(
              'sector_id', setoresData.map((s) => s['id'] as String).toList());

      final sectorMap = <String, Sector>{};
      for (final s in setoresData) {
        final sec = Sector.fromJson(s);
        sectorMap[sec.id] = sec;
      }

      final supMap = <String, Profile>{};
      for (final s in supsData) {
        final p = Profile.fromJson(s);
        supMap[p.id] = p;
      }

      if (mounted) {
        setState(() {
          _setores = setoresData.map(Sector.fromJson).toList();
          _supervisores = supsData.map(Profile.fromJson).toList();
          _accesses = accessData.map((a) {
            final access = SectorAccess.fromJson(a);
            return _AccessView(
              access: access,
              sector: sectorMap[access.sectorId],
              supervisor: supMap[access.supervisorId],
            );
          }).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _conceder() async {
    Sector? sector;
    Profile? supervisor;
    bool canView = true;
    bool canEdit = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Conceder Acesso Compartilhado'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<Sector>(
                key: ValueKey(sector),
                decoration: const InputDecoration(labelText: 'Setor *'),
                initialValue: sector,
                items: _setores
                    .map((s) =>
                        DropdownMenuItem(value: s, child: Text(s.name)))
                    .toList(),
                onChanged: (v) => setLocal(() => sector = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Profile>(
                key: ValueKey(supervisor),
                decoration:
                    const InputDecoration(labelText: 'Supervisor *'),
                initialValue: supervisor,
                items: _supervisores
                    .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text(
                            '${p.fullName}  •  ${CpfUtils.mask(p.cpf)}')))
                    .toList(),
                onChanged: (v) => setLocal(() => supervisor = v),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                title: const Text('Visualização'),
                value: canView,
                onChanged: (v) => setLocal(() => canView = v ?? true),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              CheckboxListTile(
                title: const Text('Modificação'),
                value: canEdit,
                onChanged: (v) => setLocal(() => canEdit = v ?? false),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: sector != null && supervisor != null
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Conceder'),
            ),
          ],
        ),
      ),
    );

    if (sector == null || supervisor == null || !mounted) return;

    final auth = context.read<AuthProvider>();
    try {
      await _db.from('sector_access').upsert({
        'sector_id': sector!.id,
        'supervisor_id': supervisor!.id,
        'can_view': true,
        'can_edit': canEdit,
        'granted_by': auth.profile!.id,
      }, onConflict: 'sector_id,supervisor_id');

      await AuditService.log(
        userId: auth.profile!.id,
        hospitalId: _hospitalId,
        action: 'conceder_acesso_compartilhado',
        entityType: 'sector_access',
        entityId: sector!.id,
        details: {
          'supervisor_id': supervisor!.id,
          'can_view': canView,
          'can_edit': canEdit,
        },
      );

      _showSnack('Acesso concedido para ${supervisor!.fullName}.');
      _load();
    } catch (_) {
      _showSnack('Erro ao conceder acesso.', error: true);
    }
  }

  Future<void> _revogar(_AccessView item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revogar acesso?'),
        content: Text(
          'Revogar acesso de "${item.supervisor?.fullName}" ao setor "${item.sector?.name}"?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.nonCompliant),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revogar'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final auth = context.read<AuthProvider>();
    try {
      await _db
          .from('sector_access')
          .delete()
          .eq('id', item.access.id);

      await AuditService.log(
        userId: auth.profile!.id,
        hospitalId: _hospitalId,
        action: 'revogar_acesso_compartilhado',
        entityType: 'sector_access',
        entityId: item.access.id,
        details: {
          'supervisor_id': item.access.supervisorId,
          'sector_id': item.access.sectorId,
        },
      );

      _showSnack('Acesso revogado.');
      _load();
    } catch (_) {
      _showSnack('Erro ao revogar acesso.', error: true);
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
      backgroundColor: widget.embedded ? Colors.transparent : null,
      appBar: widget.embedded
          ? null
          : AppBar(title: const Text('Acesso Compartilhado')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: widget.embedded ? 'fab_acesso_embedded' : null,
        onPressed: _conceder,
        icon: const Icon(Icons.share_outlined),
        label: const Text('Conceder acesso'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _accesses.isEmpty
                  ? const Center(
                      child: Text('Nenhum acesso compartilhado configurado.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(
                          AppDimensions.screenPadding),
                      itemCount: _accesses.length,
                      itemBuilder: (ctx, i) {
                        final item = _accesses[i];
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.share_outlined,
                                color: AppColors.primary),
                            title: Text(item.supervisor?.fullName ?? '—'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    'Setor: ${item.sector?.name ?? '—'}'),
                                Row(
                                  children: [
                                    if (item.access.canView)
                                      const _PermChip(
                                          label: 'Visualização',
                                          color: AppColors.primary),
                                    const SizedBox(width: 4),
                                    if (item.access.canEdit)
                                      const _PermChip(
                                          label: 'Modificação',
                                          color: AppColors.compliant),
                                  ],
                                ),
                              ],
                            ),
                            isThreeLine: true,
                            trailing: IconButton(
                              icon: const Icon(Icons.remove_circle_outline,
                                  color: AppColors.nonCompliant),
                              tooltip: 'Revogar',
                              onPressed: () => _revogar(item),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

class _AccessView {
  final SectorAccess access;
  final Sector? sector;
  final Profile? supervisor;
  _AccessView({required this.access, this.sector, this.supervisor});
}

class _PermChip extends StatelessWidget {
  final String label;
  final Color color;
  const _PermChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 11,
              fontWeight: FontWeight.w600)),
    );
  }
}
