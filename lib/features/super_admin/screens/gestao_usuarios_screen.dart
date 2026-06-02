import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/hospital.dart';
import '../../../core/models/profile.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/utils/cpf_utils.dart';
import '../../auth/providers/auth_provider.dart';

class GestaoUsuariosScreen extends StatefulWidget {
  const GestaoUsuariosScreen({super.key});

  @override
  State<GestaoUsuariosScreen> createState() => _GestaoUsuariosScreenState();
}

class _GestaoUsuariosScreenState extends State<GestaoUsuariosScreen> {
  final _db = Supabase.instance.client;
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  List<Profile> _all = [];
  List<Profile> _filtered = [];
  List<Hospital> _hospitais = [];
  String? _filterRole;
  String? _filterHospital;
  String _filterStatus = 'active';

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
      final usuarios = await _db
          .from('profiles')
          .select()
          .order('full_name');

      final hospitaisData = await _db
          .from('hospitals')
          .select()
          .order('name');

      if (mounted) {
        setState(() {
          _all = usuarios.map(Profile.fromJson).toList();
          _hospitais = hospitaisData.map(Hospital.fromJson).toList();
          _loading = false;
          _applyFilters();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilters() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = _all.where((p) {
        if (_filterStatus == 'active' && !p.isActive) return false;
        if (_filterStatus == 'inactive' && p.isActive) return false;
        if (_filterRole != null && p.role != _filterRole) return false;
        if (_filterHospital != null && p.hospitalId != _filterHospital) {
          return false;
        }
        if (q.isNotEmpty) {
          return p.fullName.toLowerCase().contains(q) ||
              p.email.toLowerCase().contains(q) ||
              CpfUtils.strip(p.cpf).contains(CpfUtils.strip(q));
        }
        return true;
      }).toList();
    });
  }

  Future<void> _toggleStatus(Profile p) async {
    final auth = context.read<AuthProvider>();

    // Regra: Director ativo não pode ser desativado sem substituto
    if (p.role == 'director' && p.isActive) {
      _showSnack(
        'Desative o Diretor somente após vincular um substituto em "Vincular Diretor".',
        error: true,
      );
      return;
    }

    final newStatus = p.isActive ? 'inactive' : 'active';
    final label = newStatus == 'inactive' ? 'desativar' : 'reativar';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${label[0].toUpperCase()}${label.substring(1)} usuário?'),
        content: Text('${label[0].toUpperCase()}${label.substring(1)} "${p.fullName}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: newStatus == 'inactive'
                ? ElevatedButton.styleFrom(backgroundColor: AppColors.nonCompliant)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(label[0].toUpperCase() + label.substring(1)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await _db
          .from('profiles')
          .update({'status': newStatus})
          .eq('id', p.id);

      await AuditService.log(
        userId: auth.profile!.id,
        action: '${label}_usuario',
        entityType: 'profile',
        entityId: p.id,
        details: {'target_name': p.fullName, 'role': p.role},
      );

      _showSnack('Usuário ${newStatus == 'active' ? 'reativado' : 'desativado'}.');
      _load();
    } catch (_) {
      _showSnack('Erro ao $label usuário.', error: true);
    }
  }

  Future<void> _editarUsuario(Profile p) async {
    final nomeCtrl = TextEditingController(text: p.fullName);
    final emailCtrl = TextEditingController(text: p.email);
    final auth = context.read<AuthProvider>();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar usuário'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nomeCtrl,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Nome completo'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: emailCtrl,
              maxLength: 200,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-mail'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salvar')),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await _db.from('profiles').update({
        'full_name': nomeCtrl.text.trim(),
        'email': emailCtrl.text.trim().toLowerCase(),
      }).eq('id', p.id);

      await AuditService.log(
        userId: auth.profile!.id,
        action: 'editar_usuario',
        entityType: 'profile',
        entityId: p.id,
        details: {'full_name': nomeCtrl.text.trim()},
      );

      _showSnack('Dados atualizados.');
      _load();
    } catch (_) {
      _showSnack('Erro ao salvar.', error: true);
    } finally {
      nomeCtrl.dispose();
      emailCtrl.dispose();
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.nonCompliant : AppColors.compliant,
    ));
  }

  Hospital? _hospitalOf(Profile p) =>
      p.hospitalId != null
          ? _hospitais.where((h) => h.id == p.hospitalId).firstOrNull
          : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Usuários'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Busca ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Buscar por nome, e-mail ou CPF...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => _applyFilters(),
            ),
          ),
          // ── Chips de filtro ────────────────────────────────────────────
          if (_filterRole != null || _filterHospital != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  if (_filterRole != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Chip(
                        label: Text(AppConstants.roleLabel(_filterRole)),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () {
                          setState(() => _filterRole = null);
                          _applyFilters();
                        },
                      ),
                    ),
                  if (_filterHospital != null)
                    Chip(
                      label: Text(
                        _hospitais
                            .where((h) => h.id == _filterHospital)
                            .firstOrNull
                            ?.sigla ?? '',
                      ),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () {
                        setState(() => _filterHospital = null);
                        _applyFilters();
                      },
                    ),
                ],
              ),
            ),
          // ── Lista ──────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _filtered.isEmpty
                        ? const Center(child: Text('Nenhum usuário encontrado.'))
                        : ListView.builder(
                            padding: const EdgeInsets.all(
                                AppDimensions.screenPadding),
                            itemCount: _filtered.length,
                            itemBuilder: (ctx, i) {
                              final p = _filtered[i];
                              final hospital = _hospitalOf(p);
                              return Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: p.isActive
                                        ? AppColors.primary
                                        : AppColors.textDisabled,
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
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          '${p.email}  •  ${CpfUtils.mask(p.cpf)}'),
                                      Text(
                                        '${AppConstants.roleLabel(p.role)}${hospital != null ? '  •  ${hospital.sigla}' : ''}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                                color: AppColors.primary),
                                      ),
                                    ],
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (v) {
                                      if (v == 'edit') _editarUsuario(p);
                                      if (v == 'toggle') _toggleStatus(p);
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Editar dados')),
                                      PopupMenuItem(
                                        value: 'toggle',
                                        child: Text(p.isActive
                                            ? 'Desativar'
                                            : 'Reativar'),
                                      ),
                                    ],
                                  ),
                                  isThreeLine: true,
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Filtros', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                key: ValueKey(_filterRole),
                decoration: const InputDecoration(labelText: 'Perfil'),
                initialValue: _filterRole,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todos')),
                  ...['super_admin', 'director', 'supervisor', 'inspector']
                      .map((r) => DropdownMenuItem(
                          value: r,
                          child: Text(AppConstants.roleLabel(r)))),
                ],
                onChanged: (v) =>
                    setLocal(() => _filterRole = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: ValueKey(_filterHospital),
                decoration: const InputDecoration(labelText: 'Hospital'),
                initialValue: _filterHospital,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todos')),
                  ..._hospitais.map((h) => DropdownMenuItem(
                      value: h.id,
                      child: Text('${h.sigla} — ${h.name}'))),
                ],
                onChanged: (v) =>
                    setLocal(() => _filterHospital = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(_filterStatus),
                decoration: const InputDecoration(labelText: 'Status'),
                initialValue: _filterStatus,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Todos')),
                  DropdownMenuItem(value: 'active', child: Text('Ativos')),
                  DropdownMenuItem(value: 'inactive', child: Text('Inativos')),
                ],
                onChanged: (v) =>
                    setLocal(() => _filterStatus = v ?? 'active'),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _applyFilters();
                },
                child: const Text('Aplicar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
