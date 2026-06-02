import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/hospital.dart';
import '../../../core/models/profile.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/utils/cpf_utils.dart';
import '../../auth/providers/auth_provider.dart';

class VincularDirectorScreen extends StatefulWidget {
  const VincularDirectorScreen({super.key});

  @override
  State<VincularDirectorScreen> createState() => _VincularDirectorScreenState();
}

class _VincularDirectorScreenState extends State<VincularDirectorScreen> {
  final _db = Supabase.instance.client;
  final _emailCtrl = TextEditingController();

  bool _searching = false;
  bool _linking = false;
  bool _searchDone = false;

  Profile? _found;
  String? _notFoundMsg;

  List<Hospital> _hospitaisSemDiretor = [];
  Hospital? _hospitalSelecionado;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    if (email.isEmpty) return;

    setState(() {
      _searching = true;
      _found = null;
      _notFoundMsg = null;
      _hospitalSelecionado = null;
      _hospitaisSemDiretor = [];
      _searchDone = false;
    });

    try {
      // Busca usuário pelo e-mail: sem vínculo, ativo
      final profileData = await _db
          .from('profiles')
          .select()
          .eq('email', email)
          .eq('status', 'active')
          .isFilter('role', null)
          .maybeSingle();

      if (!mounted) return;

      if (profileData == null) {
        setState(() {
          _notFoundMsg =
              'Usuário não encontrado, já vinculado, ou ainda não se cadastrou.';
          _searching = false;
          _searchDone = true;
        });
        return;
      }

      // Carrega hospitais sem diretor ativo
      final allHospitais = await _db
          .from('hospitals')
          .select()
          .eq('status', 'active')
          .order('name');

      final directorRows = await _db
          .from('profiles')
          .select('hospital_id')
          .eq('role', 'director')
          .eq('status', 'active')
          .not('hospital_id', 'is', null);

      final dirHospitalIds = (directorRows as List)
          .map((r) => r['hospital_id'] as String)
          .toSet();

      final hospitaisSemDiretor = (allHospitais as List)
          .map((h) => Hospital.fromJson(h as Map<String, dynamic>))
          .where((h) => !dirHospitalIds.contains(h.id))
          .toList();

      if (mounted) {
        setState(() {
          _found = Profile.fromJson(profileData);
          _hospitaisSemDiretor = hospitaisSemDiretor;
          _searching = false;
          _searchDone = true;
        });
      }
    } catch (_) {
      if (mounted) {
        _showSnack('Erro ao buscar. Tente novamente.', error: true);
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _vincular() async {
    if (_found == null || _hospitalSelecionado == null) return;
    final auth = context.read<AuthProvider>();

    setState(() => _linking = true);
    try {
      await _db.from('profiles').update({
        'role': 'director',
        'hospital_id': _hospitalSelecionado!.id,
      }).eq('id', _found!.id);

      await AuditService.log(
        userId: auth.profile!.id,
        action: 'vincular_director',
        entityType: 'profile',
        entityId: _found!.id,
        details: {
          'hospital_id': _hospitalSelecionado!.id,
          'hospital_name': _hospitalSelecionado!.name,
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Diretor vinculado com sucesso!'),
            backgroundColor: AppColors.compliant,
          ),
        );
        context.pop();
      }
    } catch (_) {
      if (mounted) _showSnack('Erro ao vincular Diretor.', error: true);
    } finally {
      if (mounted) setState(() => _linking = false);
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
      appBar: AppBar(title: const Text('Vincular Diretor')),
      body: ListView(
        padding: const EdgeInsets.all(AppDimensions.screenPadding),
        children: [
          // ── Campo de e-mail ────────────────────────────────────────────
          Text('E-mail do usuário',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-mail do usuário',
                    hintText: 'usuario@email.com',
                    prefixIcon: Icon(Icons.email_outlined),
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

          // ── Mensagem: não encontrado ───────────────────────────────────
          if (_searchDone && _notFoundMsg != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.nonCompliant.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.nonCompliant.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      color: AppColors.nonCompliant, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _notFoundMsg!,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.nonCompliant),
                    ),
                  ),
                ],
              ),
            ),

          // ── Preview do usuário encontrado ──────────────────────────────
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
                title: Text(_found!.fullName,
                    style: Theme.of(context).textTheme.titleMedium),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_found!.email,
                        style: Theme.of(context).textTheme.bodySmall),
                    Text(CpfUtils.mask(_found!.cpf),
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
                isThreeLine: true,
              ),
            ),
            const SizedBox(height: 20),

            // ── Dropdown de hospitais sem diretor ─────────────────────
            Text('Selecionar hospital',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_hospitaisSemDiretor.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Nenhum hospital disponível (todos já possuem Diretor ativo).',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.pending),
                ),
              )
            else
              DropdownButtonFormField<Hospital>(
                key: ValueKey(_hospitalSelecionado),
                decoration: const InputDecoration(
                  labelText: 'Hospital *',
                  prefixIcon: Icon(Icons.local_hospital_outlined),
                ),
                initialValue: _hospitalSelecionado,
                items: _hospitaisSemDiretor
                    .map((h) => DropdownMenuItem(
                        value: h, child: Text('${h.sigla} — ${h.name}')))
                    .toList(),
                onChanged: (v) => setState(() => _hospitalSelecionado = v),
              ),
            const SizedBox(height: 24),

            // ── Botão vincular ─────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_hospitalSelecionado != null && !_linking)
                    ? _vincular
                    : null,
                child: _linking
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Vincular como Diretor'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
