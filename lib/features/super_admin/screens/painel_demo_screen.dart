import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, PostgrestException;
import '../../../core/constants/app_colors.dart';

/// Painel de gestão de contas demo (ferramenta de desenvolvimento).
/// Chama as RPCs de migration_demo_rpcs.sql — só afeta contas @demo.com.
class PainelDemoScreen extends StatefulWidget {
  const PainelDemoScreen({super.key});

  @override
  State<PainelDemoScreen> createState() => _PainelDemoScreenState();
}

class _PainelDemoScreenState extends State<PainelDemoScreen> {
  final _db = Supabase.instance.client;

  bool _provisioning = false;
  bool _resetting = false;
  bool _seeding = false;

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.nonCompliant : AppColors.compliant,
    ));
  }

  Future<void> _provisionar() async {
    setState(() => _provisioning = true);
    try {
      final result = await _db.rpc('provision_demo_accounts');
      final map = result as Map<String, dynamic>;
      final created = map['created'] as int? ?? 0;
      final existing = map['existing'] as int? ?? 0;
      _snack('$created conta(s) criada(s), $existing já existia(m).');
    } on PostgrestException catch (e) {
      _snack(e.message, error: true);
    } catch (_) {
      _snack('Erro ao provisionar contas demo.', error: true);
    } finally {
      if (mounted) setState(() => _provisioning = false);
    }
  }

  Future<void> _resetarSenhas() async {
    setState(() => _resetting = true);
    try {
      final result = await _db.rpc('reset_demo_passwords');
      _snack('$result senha(s) resetada(s) para "demo1234".');
    } on PostgrestException catch (e) {
      _snack(e.message, error: true);
    } catch (_) {
      _snack('Erro ao resetar senhas demo.', error: true);
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  Future<void> _popularDados() async {
    setState(() => _seeding = true);
    try {
      await _db.rpc('seed_demo_data');
      _snack('Dados demo populados com sucesso.');
    } on PostgrestException catch (e) {
      _snack(e.message, error: true);
    } catch (_) {
      _snack('Erro ao popular dados demo.', error: true);
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _provisioning || _resetting || _seeding;

    return Scaffold(
      appBar: AppBar(title: const Text('Painel Demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.pending.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.pending.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.pending, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Estas ações só afetam contas @demo.com. Não use em produção.',
                    style: TextStyle(
                      color: AppColors.pending,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _DemoActionCard(
            icon: Icons.person_add_alt_1_outlined,
            title: 'Provisionar contas demo',
            subtitle:
                'Cria (se faltarem) as 4 contas fixas e o hospital HU-DEMO.',
            buttonLabel: 'Provisionar',
            loading: _provisioning,
            disabled: busy && !_provisioning,
            onPressed: _provisionar,
          ),
          const SizedBox(height: 12),
          _DemoActionCard(
            icon: Icons.lock_reset_outlined,
            title: 'Resetar senhas demo',
            subtitle: 'Redefine a senha das 4 contas para "demo1234".',
            buttonLabel: 'Resetar senhas',
            loading: _resetting,
            disabled: busy && !_resetting,
            onPressed: _resetarSenhas,
          ),
          const SizedBox(height: 12),
          _DemoActionCard(
            icon: Icons.dataset_outlined,
            title: 'Popular dados de exemplo',
            subtitle:
                'Cria setores, checklists, vínculos e tarefas de exemplo no HU-DEMO.',
            buttonLabel: 'Popular dados',
            loading: _seeding,
            disabled: busy && !_seeding,
            onPressed: _popularDados,
          ),
        ],
      ),
    );
  }
}

class _DemoActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final bool loading;
  final bool disabled;
  final VoidCallback onPressed;

  const _DemoActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.loading,
    required this.disabled,
    required this.onPressed,
  });

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
              Icon(icon, color: AppColors.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: Theme.of(context).textTheme.titleSmall),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: ElevatedButton(
              onPressed: (loading || disabled) ? null : onPressed,
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }
}
