import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/hospital.dart';
import '../../../core/models/invitation.dart';
import '../../../core/models/profile.dart';
import '../../../core/services/invitation_service.dart';

/// Tela do Super Admin para convidar Diretores e acompanhar os convites
/// já enviados — duas abas: "Novo convite" e "Convites enviados".
class VincularDirectorScreen extends StatefulWidget {
  const VincularDirectorScreen({super.key});

  @override
  State<VincularDirectorScreen> createState() => _VincularDirectorScreenState();
}

class _VincularDirectorScreenState extends State<VincularDirectorScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Convites de Diretor'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Novo convite'),
            Tab(text: 'Convites enviados'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _NovoConviteTab(),
          _ConvitesEnviadosTab(),
        ],
      ),
    );
  }
}

// ============================================================
// Aba 1 — Novo convite
// ============================================================

class _NovoConviteTab extends StatefulWidget {
  const _NovoConviteTab();

  @override
  State<_NovoConviteTab> createState() => _NovoConviteTabState();
}

class _NovoConviteTabState extends State<_NovoConviteTab> {
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
    final code = _codeCtrl.text.trim().toUpperCase();
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
      setState(() {
        _found = null;
        _hospitais = [];
        _hospitalSelecionado = null;
        _codeCtrl.clear();
        _msgCtrl.clear();
      });
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDimensions.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Código de perfil',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'Código',
                    hintText: 'ABC123',
                    prefixText: '# ',
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

            Text('Selecionar hospital',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
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
                decoration: const InputDecoration(labelText: 'Hospital'),
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

            Text('Mensagem (opcional)',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
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
    );
  }
}

// ============================================================
// Aba 2 — Convites enviados (só convites de Diretor: o Super
// Admin nunca envia convite de Supervisor/Inspetor)
// ============================================================

class _ConvitesEnviadosTab extends StatefulWidget {
  const _ConvitesEnviadosTab();

  @override
  State<_ConvitesEnviadosTab> createState() => _ConvitesEnviadosTabState();
}

class _ConvitesEnviadosTabState extends State<_ConvitesEnviadosTab> {
  bool _loading = true;
  List<Invitation> _invites = [];
  String? _cancellingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await InvitationService.getSentInvitations();
      if (mounted) {
        setState(() {
          _invites = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancelar(Invitation inv) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar convite?'),
        content: Text(
            'Cancelar o convite enviado a ${inv.inviteeName ?? 'este usuário'}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.nonCompliant),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancelar convite'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _cancellingId = inv.id);
    try {
      await InvitationService.cancelInvitation(inv.id);
      if (mounted) {
        _snack('Convite cancelado.');
        await _load();
      }
    } on PostgrestException catch (e) {
      if (mounted) _snack(e.message, error: true);
    } catch (_) {
      if (mounted) _snack('Erro ao cancelar convite.', error: true);
    } finally {
      if (mounted) setState(() => _cancellingId = null);
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: _invites.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 120),
                Center(child: Text('Nenhum convite de Diretor enviado ainda.')),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(AppDimensions.screenPadding),
              itemCount: _invites.length,
              itemBuilder: (ctx, i) => _DirectorInviteCard(
                invitation: _invites[i],
                cancelling: _cancellingId == _invites[i].id,
                onCancel: () => _cancelar(_invites[i]),
              ),
            ),
    );
  }
}

class _DirectorInviteCard extends StatelessWidget {
  final Invitation invitation;
  final bool cancelling;
  final VoidCallback onCancel;

  const _DirectorInviteCard({
    required this.invitation,
    required this.cancelling,
    required this.onCancel,
  });

  ({Color color, String label}) _statusInfo() {
    switch (invitation.status) {
      case 'pending':
        return (color: AppColors.pending, label: 'Pendente');
      case 'accepted':
        return (color: AppColors.compliant, label: 'Aceito');
      case 'declined':
        return (color: AppColors.nonCompliant, label: 'Recusado');
      case 'cancelled':
        return (color: AppColors.textSecondary, label: 'Cancelado');
      case 'expired':
        return (color: AppColors.textSecondary, label: 'Expirado');
      default:
        return (color: AppColors.textSecondary, label: invitation.status);
    }
  }

  String _trailingLabel() {
    if (invitation.isPending) {
      final exp = invitation.expiresAt;
      if (exp == null) return '';
      final diff = exp.difference(DateTime.now());
      if (diff.isNegative) return 'Expirado';
      if (diff.inDays >= 1) return 'Expira em ${diff.inDays}d';
      if (diff.inHours >= 1) return 'Expira em ${diff.inHours}h';
      return 'Expira em ${diff.inMinutes}min';
    }
    if (invitation.respondedAt != null) {
      final d = invitation.respondedAt!.toLocal();
      return 'Respondido em ${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/${d.year}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final status = _statusInfo();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  invitation.inviteeName ?? 'Usuário convidado',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status.label,
                  style: TextStyle(
                      color: status.color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (invitation.hospitalName != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.local_hospital_outlined,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(invitation.hospitalName!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.textSecondary)),
                ),
              ],
            ),
          ],
          if (_trailingLabel().isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.timer_outlined,
                    size: 16,
                    color: invitation.isPending
                        ? AppColors.pending
                        : AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_trailingLabel(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: invitation.isPending
                              ? AppColors.pending
                              : AppColors.textSecondary)),
                ),
              ],
            ),
          ],
          if (invitation.isPending) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: cancelling ? null : onCancel,
                icon: cancelling
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Cancelar convite'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.nonCompliant,
                  side: const BorderSide(color: AppColors.nonCompliant),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
