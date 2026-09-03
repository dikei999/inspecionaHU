import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, Supabase;
import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/hospital.dart';
import '../../../core/models/profile.dart';
import '../../../core/services/audit_service.dart';
import '../../auth/providers/auth_provider.dart';

class HospitaisScreen extends StatefulWidget {
  const HospitaisScreen({super.key});

  @override
  State<HospitaisScreen> createState() => _HospitaisScreenState();
}

class _HospitaisScreenState extends State<HospitaisScreen> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  List<_HospitalWithDirector> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final hospitais = await _db
          .from('hospitals')
          .select()
          .order('name', ascending: true);

      final directors = await _db
          .from('profiles')
          .select('id, full_name, cpf, hospital_id')
          .eq('role', 'director')
          .eq('status', 'active');

      final dirMap = <String, Profile>{};
      for (final d in directors) {
        final hid = d['hospital_id'] as String?;
        if (hid != null) {
          dirMap[hid] = Profile.fromJson({
            ...d,
            'email': '',
            'status': 'active',
            'created_at': DateTime.now().toIso8601String(),
          });
        }
      }

      if (mounted) {
        setState(() {
          _items = hospitais
              .map((h) => _HospitalWithDirector(
                    hospital: Hospital.fromJson(h),
                    director: dirMap[h['id'] as String],
                  ))
              .toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        _showSnack('Erro ao carregar hospitais.', error: true);
      }
    }
  }

  Future<void> _toggleStatus(Hospital hospital) async {
    final auth = context.read<AuthProvider>();
    final newStatus = hospital.status == 'active' ? 'inactive' : 'active';
    final label = newStatus == 'inactive' ? 'desativar' : 'reativar';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${label[0].toUpperCase()}${label.substring(1)} hospital?'),
        content: Text(
          newStatus == 'inactive'
              ? 'Desativar "${hospital.name}" congela todos os dados. Nenhum usuário deste hospital poderá acessar o sistema.'
              : 'Reativar "${hospital.name}"?',
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
            child: Text(label[0].toUpperCase() + label.substring(1)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await _db.from('hospitals').update({'status': newStatus}).eq('id', hospital.id);
      await AuditService.log(
        userId: auth.profile!.id,
        action: '${label}_hospital',
        entityType: 'hospital',
        entityId: hospital.id,
        details: {'name': hospital.name, 'status': newStatus},
      );
      _showSnack('Hospital ${newStatus == 'active' ? 'reativado' : 'desativado'}.');
      _load();
    } catch (_) {
      _showSnack('Erro ao $label hospital.', error: true);
    }
  }

  /// Apagar é permitido apenas em hospitais SEM dependências — nenhum
  /// setor e nenhum usuário vinculado. Com dependências, explica o motivo
  /// e sugere desativar (soft delete), que preserva o histórico.
  Future<void> _apagar(Hospital hospital) async {
    final auth = context.read<AuthProvider>();

    int setores;
    int usuarios;
    try {
      final setoresData =
          await _db.from('sectors').select('id').eq('hospital_id', hospital.id);
      final usuariosData = await _db
          .from('profiles')
          .select('id')
          .eq('hospital_id', hospital.id);
      setores = setoresData.length;
      usuarios = usuariosData.length;
    } catch (_) {
      _showSnack('Erro ao verificar dependências do hospital.', error: true);
      return;
    }

    if (!mounted) return;

    if (setores > 0 || usuarios > 0) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Não é possível apagar'),
          content: Text(
            '"${hospital.name}" possui '
            '${setores > 0 ? '$setores setor(es)' : ''}'
            '${setores > 0 && usuarios > 0 ? ' e ' : ''}'
            '${usuarios > 0 ? '$usuarios usuário(s)' : ''} vinculado(s). '
            'Apagar destruiria dados operacionais. Use "Desativar" — o '
            'hospital fica inacessível e todo o histórico é preservado.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendi'),
            ),
          ],
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar hospital?'),
        content: Text(
          '"${hospital.name}" não tem setores nem usuários vinculados e '
          'será removido definitivamente. Esta ação NÃO pode ser desfeita.',
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
            child: const Text('Apagar'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await _db.from('hospitals').delete().eq('id', hospital.id);
      await AuditService.log(
        userId: auth.profile!.id,
        action: 'apagar_hospital',
        entityType: 'hospital',
        entityId: hospital.id,
        details: {'name': hospital.name, 'sigla': hospital.sigla},
      );
      _showSnack('Hospital apagado.');
      _load();
    } on PostgrestException catch (e) {
      _showSnack('Erro ao apagar: ${e.message}', error: true);
    } catch (_) {
      _showSnack('Erro ao apagar hospital.', error: true);
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
      appBar: AppBar(title: const Text('Hospitais')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push(AppRoutes.criarHospital);
          _load();
        },
        label: const Text('Novo hospital'),
        icon: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? const Center(child: Text('Nenhum hospital cadastrado.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(AppDimensions.screenPadding),
                      itemCount: _items.length,
                      itemBuilder: (ctx, i) {
                        final item = _items[i];
                        final h = item.hospital;
                        final dir = item.director;
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: h.isActive
                                  ? AppColors.primary
                                  : AppColors.textDisabled,
                              child: Text(
                                h.sigla.substring(0, h.sigla.length.clamp(0, 2)),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12),
                              ),
                            ),
                            title: Text(h.name),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${h.sigla}  •  ${h.city} — ${h.state}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                                if (dir != null)
                                  Text(
                                    'Diretor: ${dir.fullName}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: AppColors.primary),
                                  )
                                else
                                  Text(
                                    'Sem Diretor vinculado',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: AppColors.pending),
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: h.isActive
                                        ? AppColors.compliant.withAlpha(30)
                                        : AppColors.textDisabled.withAlpha(30),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    h.isActive ? 'Ativo' : 'Inativo',
                                    style: TextStyle(
                                      color: h.isActive
                                          ? AppColors.compliant
                                          : AppColors.textDisabled,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                PopupMenuButton<String>(
                                  onSelected: (v) {
                                    if (v == 'toggle') _toggleStatus(h);
                                    if (v == 'apagar') _apagar(h);
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: 'toggle',
                                      child: Text(h.isActive
                                          ? 'Desativar'
                                          : 'Reativar'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'apagar',
                                      child: Text(
                                        'Apagar',
                                        style: TextStyle(
                                            color: AppColors.nonCompliant),
                                      ),
                                    ),
                                  ],
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

class _HospitalWithDirector {
  final Hospital hospital;
  final Profile? director;
  _HospitalWithDirector({required this.hospital, this.director});
}
