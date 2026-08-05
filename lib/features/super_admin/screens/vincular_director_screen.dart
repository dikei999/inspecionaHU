import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/hospital.dart';
import '../../../core/models/profile.dart';
import '../../../core/services/invitation_service.dart';
import '../../../core/utils/upper_case_text_formatter.dart';

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
  List<Hospital> _hospitais = [];
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
      _hospitais = [];
    });

    try {
      final result = await InvitationService.lookupUserByCode(code);
      if (!mounted) return;

      if (result == null) {
        _snack('Código não encontrado ou usuário já vinculado.', error: true);
        setState(() => _searching = false);
        return;
      }

      // Hospitais ativos SEM diretor ativo.
      final allHospitais =
          await _db.from('hospitals').select().eq('status', 'active').order('name');

      final directorRows = await _db
          .from('profiles')
          .select('hospital_id')
          .eq('role', 'director')
          .eq('status', 'active')
          .not('hospital_id', 'is', null);

      final comDiretor = (directorRows as List)
          .map((r) => r['hospital_id'] as String)
          .toSet();

      final semDiretor = (allHospitais as List)
          .map((h) => Hospital.fromJson(h as Map<String, dynamic>))
          .where((h) => !comDiretor.contains(h.id))
          .toList();

      if (!mounted) return;
      setState(() {
        _found = result;
        _hospitais = semDiretor;
        _searching = false;
      });
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
        inviteeCode: _codeCtrl.text.trim(),
        hospitalId: _hospitalSelecionado!.id,
        message: _msgCtrl.text.trim().isEmpty ? null : _msgCtrl.text.trim(),
      );
      if (!mounted) return;
      _snack('Convite enviado! O usuário precisa aceitar ao abrir o app.');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Convidar Diretor')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimensions.screenPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Código de perfil ──────────────────────────────────────────
            const Text('Código de perfil',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeCtrl,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 6,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                      UpperCaseTextFormatter(),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Código',
                      hintText: 'ABC123',
                      prefixIcon: Icon(Icons.tag),
                      counterText: '',
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

            // ── Preview do usuário ────────────────────────────────────────
            if (_found != null) ...[
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.primary,
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  title: Text(_found!.fullName),
                  subtitle: Text(_found!.email),
                ),
              ),
              const SizedBox(height: 20),

              // ── Hospital ────────────────────────────────────────────────
              const Text('Selecionar hospital',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (_hospitais.isEmpty)
                const Text(
                  'Nenhum hospital disponível (todos já possuem Diretor ativo).',
                  style: TextStyle(color: AppColors.pending),
                )
              else
                DropdownButtonFormField<Hospital>(
                  initialValue: _hospitalSelecionado,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Hospital',
                    prefixIcon: Icon(Icons.local_hospital_outlined),
                  ),
                  items: _hospitais
                      .map((h) => DropdownMenuItem(
                            value: h,
                            child: Text('${h.sigla} — ${h.name}',
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _hospitalSelecionado = v),
                ),
              const SizedBox(height: 20),

              // ── Mensagem ────────────────────────────────────────────────
              const Text('Mensagem (opcional)',
                  style: TextStyle(fontWeight: FontWeight.w600)),
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

              // ── Enviar ──────────────────────────────────────────────────
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed:
                      (_hospitalSelecionado != null && !_sending) ? _enviar : null,
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
      ),
    );
  }
}
