import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/profile.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/utils/cpf_utils.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/skeleton_loader.dart';

/// Aba "Membros" de Gestão de Usuários: o que é de alcance HOSPITALAR.
///
/// Lista Supervisores e Inspetores do hospital e permite desativar ou
/// reativar (soft delete). Um Supervisor recém-convidado, ainda sem setor,
/// só aparece aqui — por isso esta visão não pôde ser dissolvida nas abas
/// de setor.
///
/// O que é de SETOR saiu daqui e vive na aba Equipe do setor: vincular
/// Inspetor a setores, acesso compartilhado, convite já vinculado e os
/// convites enviados daquele setor.
class MembrosHospitalTab extends StatefulWidget {
  const MembrosHospitalTab({super.key});

  @override
  State<MembrosHospitalTab> createState() => _MembrosHospitalTabState();
}

class _MembrosHospitalTabState extends State<MembrosHospitalTab> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  List<Profile> _supervisores = [];
  List<Profile> _inspetores = [];
  String _hospitalId = '';
  String? _myRole;

  bool get _isDirector => _myRole == 'director';

  @override
  void initState() {
    super.initState();
    _myRole = context.read<AuthProvider>().profile?.role;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = context.read<AuthProvider>().profile;
    if (profile?.hospitalId == null) {
      // Perfil ainda nao carregado: encerra o loading para
      // a tela nao ficar presa no skeleton indefinidamente.
      if (mounted) setState(() => _loading = false);
      return;
    }
    _hospitalId = profile!.hospitalId!;
    _myRole = profile.role;

    try {
      final sups = await _db
          .from('profiles')
          .select()
          .eq('hospital_id', _hospitalId)
          .eq('role', 'supervisor')
          .order('full_name', ascending: true);

      final insp = await _db
          .from('profiles')
          .select()
          .eq('hospital_id', _hospitalId)
          .eq('role', 'inspector')
          .order('full_name', ascending: true);

      if (mounted) {
        setState(() {
          _supervisores = sups.map(Profile.fromJson).toList();
          _inspetores = insp.map(Profile.fromJson).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.nonCompliant : AppColors.compliant,
    ));
  }

  // A vinculação de Supervisor/Inspetor ao hospital agora é feita por
  // convite via código de perfil — o botão "Convidar usuário" abre a tela
  // dedicada. O vínculo de setores do Inspetor (inspector_sectors), porém,
  // não faz parte desse convite e é gerenciado aqui.

  Future<void> _desativar(Profile p) async {
    final auth = context.read<AuthProvider>();
    final desativando = p.isActive;

    // Supervisor com tarefas ativas NO PRÓPRIO ESCOPO exige transferência.
    // Antes a contagem pegava as tarefas do hospital inteiro, então qualquer
    // tarefa pendente em qualquer setor bloqueava a desativação de qualquer
    // Supervisor — inclusive de um sem nenhum setor.
    if (desativando && p.role == 'supervisor') {
      final bloqueado = await _supervisorTemTarefasAtivas(p.id);
      if (!mounted) return;
      if (bloqueado) {
        _showSnack(
          'Este Supervisor tem tarefas ativas nos setores dele. '
          'Transfira as tarefas antes de desativar.',
          error: true,
        );
        return;
      }
    }

    final confirm = await confirmAction(
      context,
      title: desativando ? 'Desativar usuário?' : 'Reativar usuário?',
      message: desativando
          ? '"${p.fullName}" perde o acesso ao sistema. O histórico e as '
              'inspeções já feitas são preservados, e a reativação pode ser '
              'feita a qualquer momento.'
          : '"${p.fullName}" volta a ter acesso ao sistema com o mesmo '
              'perfil de antes.',
      confirmLabel: desativando ? 'Desativar' : 'Reativar',
      destructive: desativando,
      icon: desativando ? Icons.person_off_outlined : Icons.person_outline,
    );

    if (!confirm || !mounted) return;

    try {
      await _db
          .from('profiles')
          .update({'status': desativando ? 'inactive' : 'active'})
          .eq('id', p.id);

      await AuditService.log(
        userId: auth.profile!.id,
        hospitalId: _hospitalId,
        action: desativando ? 'desativar_usuario' : 'reativar_usuario',
        entityType: 'profile',
        entityId: p.id,
        details: {'name': p.fullName, 'role': p.role},
      );

      _showSnack(desativando ? 'Usuário desativado.' : 'Usuário reativado.');
      _load();
    } on PostgrestException catch (e) {
      debugPrint('[GestaoEquipe] _desativar PostgrestException: ${e.message} | ${e.code}');
      _showSnack('Erro ao salvar: ${e.message}', error: true);
    } catch (e) {
      debugPrint('[GestaoEquipe] _desativar erro inesperado: $e');
      _showSnack('Erro inesperado ao salvar.', error: true);
    }
  }

  /// Há tarefa pendente/em andamento em algum setor deste Supervisor?
  /// Escopo = setores onde é owner + setores com sector_access.
  Future<bool> _supervisorTemTarefasAtivas(String supervisorId) async {
    try {
      final ids = <String>{};

      final owned = await _db
          .from('sectors')
          .select('id')
          .eq('hospital_id', _hospitalId)
          .eq('owner_supervisor_id', supervisorId);
      for (final r in owned) {
        ids.add(r['id'] as String);
      }

      final shared = await _db
          .from('sector_access')
          .select('sector_id')
          .eq('supervisor_id', supervisorId);
      for (final r in shared) {
        ids.add(r['sector_id'] as String);
      }

      if (ids.isEmpty) return false;

      final tasks = await _db
          .from('tasks')
          .select('id')
          .eq('hospital_id', _hospitalId)
          .inFilter('sector_id', ids.toList())
          .inFilter('status', ['pending', 'in_progress']);
      return tasks.isNotEmpty;
    } catch (e) {
      debugPrint('[GestaoEquipe] _supervisorTemTarefasAtivas: $e');
      // Na dúvida, bloqueia: desativar um Supervisor com tarefas órfãs é
      // pior que exigir uma tentativa a mais.
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SkeletonList(itemHeight: 84);
    return _buildMembrosTab();
  }

  Widget _buildMembrosTab() {
    if (!_isDirector) {
      return _UserList(
        users: _inspetores,
        onDesativar: _desativar,
        emptyMsg: 'Nenhum Inspetor vinculado.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppDimensions.screenPadding,
            AppDimensions.screenPadding,
            AppDimensions.screenPadding,
            88),
        children: [
          Text('Supervisores', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_supervisores.isEmpty)
            const _EmptyRow(msg: 'Nenhum Supervisor vinculado.')
          else
            ..._supervisores.map((u) => _UserCard(
                  user: u,
                  onDesativar: _desativar,
                )),
          const SizedBox(height: 20),
          Text('Inspetores', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_inspetores.isEmpty)
            const _EmptyRow(msg: 'Nenhum Inspetor vinculado.')
          else
            ..._inspetores.map((u) => _UserCard(
                  user: u,
                  onDesativar: _desativar,
                )),
        ],
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  final String msg;
  const _EmptyRow({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading:
            const Icon(Icons.info_outline, color: AppColors.textSecondary),
        title: Text(msg),
      ),
    );
  }
}

class _UserList extends StatelessWidget {
  final List<Profile> users;
  final Future<void> Function(Profile) onDesativar;
  final String emptyMsg;

  const _UserList({
    required this.users,
    required this.onDesativar,
    required this.emptyMsg,
  });

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return EmptyState(
        icon: Icons.groups_outlined,
        title: emptyMsg,
        subtitle: 'O convite é enviado pelo código de perfil do '
            'usuário e vincula a pessoa a este hospital.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
          AppDimensions.screenPadding,
          AppDimensions.screenPadding,
          AppDimensions.screenPadding,
          88),
      itemCount: users.length,
      itemBuilder: (ctx, i) => _UserCard(
        user: users[i],
        onDesativar: onDesativar,
      ),
    );
  }
}

/// Card de membro da equipe — usado tanto na lista simples do Supervisor
/// quanto nas seções (Supervisores / Inspetores) da visão do Diretor.
class _UserCard extends StatelessWidget {
  final Profile user;
  final Future<void> Function(Profile) onDesativar;

  const _UserCard({
    required this.user,
    required this.onDesativar,
  });

  @override
  Widget build(BuildContext context) {
    final u = user;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              u.isActive ? AppColors.primary : AppColors.textDisabled,
          child: Text(
            u.fullName
                .split(' ')
                .map((w) => w.isNotEmpty ? w[0] : '')
                .take(2)
                .join(),
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        title: Text(u.fullName),
        // CPF sempre mascarado (só os 4 últimos dígitos).
        subtitle: Text('${u.email}  •  ${CpfUtils.mask(u.cpf)}'),
        // Vincular a setores saiu daqui: isso e da aba Equipe do setor,
        // que e o unico lugar para gerir as pessoas de um setor.
        trailing: PopupMenuButton<String>(
          tooltip: 'Acoes do membro',
          onSelected: (v) {
            if (v == 'desativar') onDesativar(u);
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'desativar',
              child: Text(u.isActive ? 'Desativar' : 'Reativar'),
            ),
          ],
        ),
      ),
    );
  }
}
