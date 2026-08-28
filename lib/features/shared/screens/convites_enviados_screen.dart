import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/invitation.dart';
import '../../../core/services/invitation_service.dart';

/// Lista os convites enviados pelo usuário logado, com filtro por status.
/// Acessível por Super Admin, Diretor e Supervisor.
class ConvitesEnviadosScreen extends StatefulWidget {
  /// Quando true a tela é renderizada como aba dentro de outra Scaffold
  /// (Equipe) — sem AppBar própria. A lógica de negócio é a mesma.
  final bool embedded;

  const ConvitesEnviadosScreen({super.key, this.embedded = false});

  @override
  State<ConvitesEnviadosScreen> createState() => _ConvitesEnviadosScreenState();
}

class _ConvitesEnviadosScreenState extends State<ConvitesEnviadosScreen> {
  bool _loading = true;
  List<Invitation> _invites = [];
  String _filter = 'all';
  String? _cancellingId;

  static const _filters = [
    {'value': 'all', 'label': 'Todos'},
    {'value': 'pending', 'label': 'Pendente'},
    {'value': 'accepted', 'label': 'Aceito'},
    {'value': 'declined', 'label': 'Recusado'},
    {'value': 'cancelled', 'label': 'Cancelado'},
    {'value': 'expired', 'label': 'Expirado'},
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await InvitationService.getSentInvitations(
          statusFilter: _filter == 'all' ? null : _filter);
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
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.nonCompliant),
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
    return Scaffold(
      backgroundColor: widget.embedded ? Colors.transparent : null,
      appBar:
          widget.embedded ? null : AppBar(title: const Text('Convites enviados')),
      body: Column(
        children: [
          // ── Filtros por status ──────────────────────────────────────────
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: _filters.map((f) {
                final selected = _filter == f['value'];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f['label']!),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _filter = f['value']!);
                      _load();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _invites.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 120),
                              Center(child: Text('Nenhum convite encontrado.')),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(
                                AppDimensions.screenPadding),
                            itemCount: _invites.length,
                            itemBuilder: (ctx, i) => _InviteCard(
                              invitation: _invites[i],
                              cancelling: _cancellingId == _invites[i].id,
                              onCancel: () => _cancelar(_invites[i]),
                            ),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  final Invitation invitation;
  final bool cancelling;
  final VoidCallback onCancel;

  const _InviteCard({
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
    return '';
  }

  String _sentLabel() {
    final d = invitation.createdAt.toLocal();
    return 'Enviado em ${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
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
          const SizedBox(height: 8),
          _row(context, Icons.badge_outlined,
              AppConstants.roleLabel(invitation.role)),
          if (invitation.hospitalName != null)
            _row(context, Icons.local_hospital_outlined,
                invitation.hospitalName!),
          _row(context, Icons.schedule, _sentLabel()),
          if (_trailingLabel().isNotEmpty)
            _row(context, Icons.timer_outlined, _trailingLabel(),
                color: AppColors.pending),
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

  Widget _row(BuildContext context, IconData icon, String text,
      {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color ?? AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: color ?? AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}
