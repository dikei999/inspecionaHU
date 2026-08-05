import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/profile.dart';
import '../../../core/models/sector.dart';
import '../../../core/services/invitation_service.dart';
import '../../../core/utils/cpf_utils.dart';
import '../../auth/providers/auth_provider.dart';

/// Tela única de convite para Diretor e Supervisor.
/// - Diretor: pode convidar Supervisor ou Inspetor; vê todos os setores.
/// - Supervisor: só convida Inspetor; vê seus setores (owner) + os com can_edit.
class ConvidarUsuarioScreen extends StatefulWidget {
  const ConvidarUsuarioScreen({super.key});

  @override
  State<ConvidarUsuarioScreen> createState() => _ConvidarUsuarioScreenState();
}

class _ConvidarUsuarioScreenState extends State<ConvidarUsuarioScreen> {
  final _db = Supabase.instance.client;
  final _codeCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();

  bool _searching = false;
  bool _sending = false;
  bool _loadingSectors = true;

  Profile? _found;
  String _role = 'inspector';
  List<Sector> _sectors = [];
  final List<String> _selectedSectorIds = [];

  bool get _isDirector =>
      context.read<AuthProvider>().profile?.role == 'director';

  @override
  void initState() {
    super.initState();
    _loadSectors();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSectors() async {
    setState(() => _loadingSectors = true);
    final profile = context.read<AuthProvider>().profile;
    if (profile?.hospitalId == null) {
      setState(() => _loadingSectors = false);
      return;
    }
    final hospitalId = profile!.hospitalId!;

    try {
      List<Sector> sectors;
      if (profile.role == 'director') {
        // Diretor vê todos os setores ativos do hospital.
        final data = await _db
            .from('sectors')
            .select()
            .eq('hospital_id', hospitalId)
            .eq('status', 'active')
            .order('name');
        sectors = (data as List).map((e) => Sector.fromJson(e)).toList();
      } else {
        // Supervisor: setores que possui (owner) + os com can_edit.
        final owned = await _db
            .from('sectors')
            .select()
            .eq('hospital_id', hospitalId)
            .eq('status', 'active')
            .eq('owner_supervisor_id', profile.id);

        final accessRows = await _db
            .from('sector_access')
            .select('sector_id')
            .eq('supervisor_id', profile.id)
            .eq('can_edit', true);
        final accessIds = (accessRows as List)
            .map((r) => r['sector_id'] as String)
            .toList();

        final byId = <String, Sector>{
          for (final e in (owned as List))
            (e['id'] as String): Sector.fromJson(e),
        };

        if (accessIds.isNotEmpty) {
          final shared = await _db
              .from('sectors')
              .select()
              .eq('hospital_id', hospitalId)
              .eq('status', 'active')
              .inFilter('id', accessIds);
          for (final e in (shared as List)) {
            byId[e['id'] as String] = Sector.fromJson(e);
          }
        }
        sectors = byId.values.toList()
          ..sort((a, b) => a.name.compareTo(b.name));
      }

      if (mounted) {
        setState(() {
          _sectors = sectors;
          _loadingSectors = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSectors = false);
    }
  }

  Future<void> _buscar() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _searching = true;
      _found = null;
    });
    try {
      final result = await InvitationService.lookupUserByCode(code);
      if (!mounted) return;
      if (result == null) {
        _snack('Código não encontrado ou usuário já vinculado.', error: true);
      }
      setState(() => _found = result);
    } catch (_) {
      if (mounted) _snack('Erro ao buscar usuário.', error: true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _enviar() async {
    if (_found == null) return;
    setState(() => _sending = true);
    try {
      await InvitationService.sendInvitation(
        inviteeCode: _codeCtrl.text,
        role: _role,
        sectorIds: List<String>.from(_selectedSectorIds),
        message: _msgCtrl.text.trim().isEmpty ? null : _msgCtrl.text.trim(),
      );
      if (!mounted) return;
      _snack('Convite enviado');
      context.pop();
    } on PostgrestException catch (e) {
      if (mounted) _snack(e.message, error: true);
    } catch (_) {
      if (mounted) _snack('Erro ao enviar convite.', error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.nonCompliant : AppColors.compliant,
    ));
  }

  bool get _canSend {
    if (_found == null || _sending) return false;
    // Supervisor (novo) precisa de ao menos 1 setor (o primeiro vira dono).
    if (_role == 'supervisor' && _selectedSectorIds.isEmpty) return false;
    if (_role == 'inspector' && _selectedSectorIds.isEmpty) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final roleOptions = _isDirector
        ? const [
            DropdownMenuItem(value: 'supervisor', child: Text('Supervisor')),
            DropdownMenuItem(value: 'inspector', child: Text('Inspetor')),
          ]
        : const [
            DropdownMenuItem(value: 'inspector', child: Text('Inspetor')),
          ];

    return Scaffold(
      appBar: AppBar(title: const Text('Convidar usuário')),
      body: ListView(
        padding: const EdgeInsets.all(AppDimensions.screenPadding),
        children: [
          // ── Campo código ────────────────────────────────────────────────
          Text('Código de perfil',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [_ProfileCodeFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Código',
                    hintText: '#ABC123',
                    prefixIcon: Icon(Icons.tag),
                  ),
                  onSubmitted: (_) => _buscar(),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _searching ? null : _buscar,
                  child: _searching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Buscar'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Preview do usuário ──────────────────────────────────────────
          if (_found != null) ...[
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary,
                  child: Text(
                    _found!.fullName
                        .split(' ')
                        .where((w) => w.isNotEmpty)
                        .take(2)
                        .map((w) => w[0].toUpperCase())
                        .join(),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
                title: Text(_found!.fullName),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_found!.email),
                    Text(CpfUtils.mask(_found!.cpf)),
                  ],
                ),
                isThreeLine: true,
              ),
            ),
            const SizedBox(height: 20),

            // ── Cargo ─────────────────────────────────────────────────────
            Text('Cargo', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              items: roleOptions,
              onChanged: (v) => setState(() {
                _role = v ?? 'inspector';
              }),
            ),
            const SizedBox(height: 20),

            // ── Setores ───────────────────────────────────────────────────
            Text(
              _role == 'supervisor' ? 'Setores (o 1º vira dono)' : 'Setores',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_loadingSectors)
              const Center(child: CircularProgressIndicator())
            else if (_sectors.isEmpty)
              Text(
                'Nenhum setor disponível.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.pending),
              )
            else
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border, width: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: _sectors.map((s) {
                    final selected = _selectedSectorIds.contains(s.id);
                    final orderIdx = _selectedSectorIds.indexOf(s.id);
                    return CheckboxListTile(
                      title: Text(s.name),
                      subtitle: (_role == 'supervisor' && orderIdx == 0)
                          ? const Text('Será o setor dono',
                              style: TextStyle(color: AppColors.primary))
                          : null,
                      value: selected,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selectedSectorIds.add(s.id);
                          } else {
                            _selectedSectorIds.remove(s.id);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: 20),

            // ── Mensagem ──────────────────────────────────────────────────
            Text('Mensagem (opcional)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _msgCtrl,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Escreva uma mensagem para o convidado...',
              ),
            ),
            const SizedBox(height: 12),

            // ── Enviar ────────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _canSend ? _enviar : null,
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Enviar convite'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Força maiúsculas e limita a 6 caracteres alfanuméricos (sem o #).
class _ProfileCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final cleaned = newValue.text
        .replaceAll('#', '')
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toUpperCase();
    final limited = cleaned.length > 6 ? cleaned.substring(0, 6) : cleaned;
    return TextEditingValue(
      text: limited,
      selection: TextSelection.collapsed(offset: limited.length),
    );
  }
}
