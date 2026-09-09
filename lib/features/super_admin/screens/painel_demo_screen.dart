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
  bool _wiping = false;

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

  /// Limpeza total do ambiente demo. Exige digitar LIMPAR para habilitar
  /// o botão — ação irreversível (única exceção ao soft delete, restrita
  /// ao hospital HU-DEMO).
  Future<void> _limparDados() async {
    final confirmCtrl = TextEditingController();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final habilitado = confirmCtrl.text.trim().toUpperCase() == 'LIMPAR';
          return AlertDialog(
            title: const Text('Limpar dados de demonstração'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.nonCompliant.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.nonCompliant.withValues(alpha: 0.35)),
                  ),
                  child: const Text(
                    'Esta ação é IRREVERSÍVEL e restrita ao ambiente de '
                    'demonstração (hospital HU-DEMO).',
                    style: TextStyle(
                      color: AppColors.nonCompliant,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Serão apagados os setores, checklists, itens, tarefas, '
                  'inspeções, respostas e as fotos no Storage.\n\n'
                  'São preservados: as 4 contas demo, o hospital HU-DEMO e '
                  'os templates globais da biblioteca NR-32.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                const Text('Digite LIMPAR para habilitar o botão:',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(hintText: 'LIMPAR'),
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.nonCompliant),
                onPressed: habilitado ? () => Navigator.pop(ctx, true) : null,
                child: const Text('Limpar tudo'),
              ),
            ],
          );
        },
      ),
    );
    confirmCtrl.dispose();

    if (confirmado != true || !mounted) return;

    setState(() => _wiping = true);
    try {
      final result = await _db.rpc('reset_demo_data');
      final map = result as Map<String, dynamic>;
      final setores = map['setores'] as int? ?? 0;
      final checklists = map['checklists'] as int? ?? 0;
      final inspecoes = map['inspecoes'] as int? ?? 0;
      var fotos = map['fotos_storage'] as int? ?? 0;

      // fotos_storage == -1 significa que o banco NÃO conseguiu apagar
      // as fotos: o Supabase bloqueia DELETE direto em storage.objects
      // ("Use the Storage API instead"). Nesse caso a limpeza dos dados
      // já aconteceu e as fotos saem por aqui, pela API, que é o
      // caminho permitido.
      if (fotos < 0) {
        fotos = await _limparFotosDemo();
      }

      _snack('Ambiente demo limpo: $setores setor(es), $checklists '
          'checklist(s), $inspecoes inspeção(ões) e $fotos foto(s).');
    } on PostgrestException catch (e) {
      debugPrint('[PainelDemo] limpar: ${e.message}');
      _snack('Não foi possível limpar o ambiente demo. Tente novamente.',
          error: true);
    } catch (e) {
      debugPrint('[PainelDemo] limpar: $e');
      _snack('Não foi possível limpar o ambiente demo. Tente novamente.',
          error: true);
    } finally {
      if (mounted) setState(() => _wiping = false);
    }
  }

  /// Apaga as fotos do hospital demo pela Storage API.
  ///
  /// O prefixo do caminho é o hospital_id, então a varredura é limitada
  /// ao HU-DEMO — nenhuma foto de outra unidade é alcançada. Devolve
  /// quantos arquivos foram removidos.
  Future<int> _limparFotosDemo() async {
    try {
      final hospital = await _db
          .from('hospitals')
          .select('id')
          .eq('sigla', 'HU-DEMO')
          .maybeSingle();
      final hospitalId = hospital?['id'] as String?;
      if (hospitalId == null) return 0;

      final bucket = _db.storage.from('inspection-photos');
      final caminhos = <String>[];

      // A estrutura é {hospital_id}/{inspection_id}/{uuid}.jpg: uma
      // varredura por inspeção, sem listar o bucket inteiro.
      final pastas = await bucket.list(path: hospitalId);
      for (final pasta in pastas) {
        final arquivos = await bucket.list(path: '$hospitalId/${pasta.name}');
        for (final a in arquivos) {
          caminhos.add('$hospitalId/${pasta.name}/${a.name}');
        }
      }

      if (caminhos.isEmpty) return 0;
      await bucket.remove(caminhos);
      return caminhos.length;
    } catch (e) {
      debugPrint('[PainelDemo] limpar fotos: $e');
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _provisioning || _resetting || _seeding || _wiping;

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
          const SizedBox(height: 28),
          const Divider(color: AppColors.border, thickness: 0.5),
          const SizedBox(height: 16),
          Text('Zona de risco',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.nonCompliant,
                    fontWeight: FontWeight.w700,
                  )),
          const SizedBox(height: 8),
          _DemoActionCard(
            icon: Icons.delete_forever_outlined,
            title: 'Limpar dados de demonstração',
            subtitle:
                'Apaga DEFINITIVAMENTE setores, checklists, tarefas, inspeções, '
                'respostas e fotos do HU-DEMO. Ação irreversível, restrita ao '
                'ambiente de demonstração. Contas demo e templates globais '
                'NR-32 são preservados.',
            buttonLabel: 'Limpar dados demo',
            loading: _wiping,
            disabled: busy && !_wiping,
            onPressed: _limparDados,
            destructive: true,
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
  final bool destructive;

  const _DemoActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.loading,
    required this.disabled,
    required this.onPressed,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: destructive
                ? AppColors.nonCompliant.withValues(alpha: 0.4)
                : AppColors.border,
            width: destructive ? 1 : 0.5),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon,
                  color: destructive
                      ? AppColors.nonCompliant
                      : AppColors.primary,
                  size: 22),
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
              style: destructive
                  ? ElevatedButton.styleFrom(
                      backgroundColor: AppColors.nonCompliant)
                  : null,
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
