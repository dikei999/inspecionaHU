import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../providers/auth_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/invitation.dart';
import '../../../core/services/invitation_service.dart';

class AguardoScreen extends StatefulWidget {
  const AguardoScreen({super.key});

  @override
  State<AguardoScreen> createState() => _AguardoScreenState();
}

class _AguardoScreenState extends State<AguardoScreen> {
  bool _refreshing = false;
  bool _loadingInvites = true;
  List<Invitation> _invites = [];
  String? _actingId; // id do convite em processamento (aceitar/recusar)
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadInvites();
    // Auto-refresh dos convites a cada 30 segundos.
    _timer = Timer.periodic(
        const Duration(seconds: 30), (_) => _loadInvites(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadInvites({bool silent = false}) async {
    if (!silent) setState(() => _loadingInvites = true);
    try {
      final invites = await InvitationService.getMyPendingInvitations();
      if (mounted) {
        setState(() {
          _invites = invites;
          _loadingInvites = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingInvites = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await context.read<AuthProvider>().refreshProfile();
    await _loadInvites(silent: true);
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _aceitar(Invitation inv) async {
    setState(() => _actingId = inv.id);
    try {
      await InvitationService.acceptInvitation(inv.id);
      if (!mounted) return;
      // Recarrega o perfil — o GoRouter redireciona para o dashboard do
      // novo role automaticamente.
      await context.read<AuthProvider>().refreshProfile();
      _snack('Convite aceito! Bem-vindo(a).');
    } on PostgrestException catch (e) {
      if (mounted) _snack(e.message, error: true);
    } catch (_) {
      if (mounted) _snack('Erro ao aceitar convite.', error: true);
    } finally {
      if (mounted) setState(() => _actingId = null);
    }
  }

  Future<void> _recusar(Invitation inv) async {
    setState(() => _actingId = inv.id);
    try {
      await InvitationService.declineInvitation(inv.id);
      if (mounted) {
        setState(() => _invites.removeWhere((i) => i.id == inv.id));
        _snack('Convite recusado.');
      }
    } on PostgrestException catch (e) {
      if (mounted) _snack(e.message, error: true);
    } catch (_) {
      if (mounted) _snack('Erro ao recusar convite.', error: true);
    } finally {
      if (mounted) setState(() => _actingId = null);
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
    final profile = context.watch<AuthProvider>().profile;
    final code = profile?.profileCode ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('InspecionaHU'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton.icon(
            onPressed: () => context.read<AuthProvider>().signOut(),
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sair'),
            style:
                TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Ícone ────────────────────────────────────────────
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.shield_outlined,
                            size: 36, color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Aguardando vinculação',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (profile?.fullName != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Olá, ${profile!.fullName.split(' ').first}!',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w500),
                      ),
                    ],
                    const SizedBox(height: 24),

                    // ── Card do código de perfil ─────────────────────────
                    _CodeCard(code: code),
                    const SizedBox(height: 20),

                    // ── Seção: Convites recebidos ────────────────────────
                    Row(
                      children: [
                        Text('Convites recebidos',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(width: 8),
                        if (_invites.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('${_invites.length}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (_loadingInvites)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_invites.isEmpty)
                      _NoInvitesCard()
                    else
                      ..._invites.map((inv) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _InviteCard(
                              invitation: inv,
                              busy: _actingId == inv.id,
                              onAccept: () => _aceitar(inv),
                              onDecline: () => _recusar(inv),
                            ),
                          )),

                    const SizedBox(height: 24),

                    // ── Botão atualizar ──────────────────────────────────
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _refreshing ? null : _refresh,
                        icon: _refreshing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                        label: const Text('Atualizar'),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Card do código de perfil ──────────────────────────────────────────────
class _CodeCard extends StatelessWidget {
  final String code;
  const _CodeCard({required this.code});

  @override
  Widget build(BuildContext context) {
    final display = code.isEmpty ? '------' : code;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          Text(
            'Seu código de perfil',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          FittedBox(
            child: Text(
              '#$display',
              style: const TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: code.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: '#$code'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Código copiado'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: const Text('Copiar código'),
          ),
          const SizedBox(height: 12),
          Text(
            'Envie este código à pessoa que vai te vincular a um hospital.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textSecondary, height: 1.4),
          ),
        ],
      ),
    );
  }
}

// ── Estado vazio ──────────────────────────────────────────────────────────
class _NoInvitesCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.pending.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: AppColors.pending.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.access_time_outlined,
              color: AppColors.pending, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Nenhum convite pendente. Assim que alguém te convidar usando seu código, o convite aparecerá aqui.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.pending,
                    height: 1.5,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card de convite recebido ──────────────────────────────────────────────
class _InviteCard extends StatelessWidget {
  final Invitation invitation;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _InviteCard({
    required this.invitation,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  String _expiresLabel() {
    final exp = invitation.expiresAt;
    if (exp == null) return '';
    final diff = exp.difference(DateTime.now());
    if (diff.isNegative) return 'Expirado';
    if (diff.inDays >= 1) return 'Expira em ${diff.inDays}d';
    if (diff.inHours >= 1) return 'Expira em ${diff.inHours}h';
    return 'Expira em ${diff.inMinutes}min';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
              const Icon(Icons.mail_outline, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  invitation.inviterName ?? 'Um administrador',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                _expiresLabel(),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: AppColors.pending),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _InfoRow(
              icon: Icons.local_hospital_outlined,
              label: 'Hospital',
              value: invitation.hospitalName ?? '—'),
          const SizedBox(height: 4),
          _InfoRow(
              icon: Icons.badge_outlined,
              label: 'Cargo',
              value: AppConstants.roleLabel(invitation.role)),
          if (invitation.sectorIds.isNotEmpty) ...[
            const SizedBox(height: 4),
            _InfoRow(
                icon: Icons.domain_outlined,
                label: 'Setores',
                value: '${invitation.sectorIds.length} setor(es)'),
          ],
          if (invitation.message != null &&
              invitation.message!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                invitation.message!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onDecline,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.nonCompliant,
                    side: const BorderSide(color: AppColors.nonCompliant),
                  ),
                  child: const Text('Recusar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: busy ? null : onAccept,
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Aceitar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text('$label: ',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textSecondary)),
        Expanded(
          child: Text(value,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}
