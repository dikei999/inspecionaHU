import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/hospital.dart';
import '../../../core/models/profile.dart';
import '../../../core/services/invitation_service.dart';
import '../../../core/utils/cpf_utils.dart';

/// Convida um usuário para ser Diretor de um hospital (Super Admin).
/// Envia convite via RPC send_director_invitation — o usuário precisa aceitar.
class VincularDirectorScreen extends StatefulWidget {
  const VincularDirectorScreen({super.key});

  @override
  State<VincularDirectorScreen> createState() => _VincularDirectorScreenState();
}

class _VincularDirectorScreenState extends State<VincularDirectorScreen> {
  final _db = Supabase.instance.client;
  final _codeCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();

  bool _searching = false;
  bool _sending = false;

  Profile? _found;

  List<Hospital> _hospitaisSemDiretor = [];
  Hospital? _hospitalSelecionado;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _searching = true;
      _found = null;
      _hospitalSelecionado = null;
      _hospitaisSemDiretor = [];
    });

    try {
      final result = await InvitationService.lookupUserByCode(code);
      if (!mounted) return;
      if (result == null) {
        _snack('Código não encontrado ou usuário já vinculado.', error: true);
        setState(() => _searching = false);
        return;
      }

      // Carrega hospitais ativos sem diretor ativo.
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
          _found = result;
          _hospitaisSemDiretor = hospitaisSemDiretor;
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted) {
        _snack('Erro ao buscar. Tente novamente.', error: true);
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _enviar() async {
    if (_found == null || _hospitalSelecionado == null) return;
    setState(() => _sending = true);
    try {
      await InvitationService.sendDirectorInvitation(
        inviteeCode: _codeCtrl.text,
        hospitalId: _hospitalSelecionado!.id,
        message: _msgCtrl.text.trim().isEmpty ? null : _msgCtrl.text.trim(),
      );

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Convite enviado'),
          content: const Text(
              'O usuário receberá o convite ao abrir o app e precisa aceitar.'),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) context.pop();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Convidar Diretor')),
      body: ListView(
        padding: const EdgeInsets.all(AppDimensions.screenPadding),
        children: [
          // ── Campo de código ─────────────────────────────────────────────
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

          // ── Preview do usuário encontrado ───────────────────────────────
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

            // ── Dropdown de hospitais sem diretor ────────────────────────
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
            const SizedBox(height: 20),

            // ── Mensagem opcional ─────────────────────────────────────────
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

            // ── Botão enviar ──────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: (_hospitalSelecionado != null && !_sending)
                    ? _enviar
                    : null,
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Enviar convite como Diretor'),
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
