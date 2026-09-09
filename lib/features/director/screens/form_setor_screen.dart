import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/profile.dart';
import '../../../core/services/audit_service.dart';
import '../../auth/providers/auth_provider.dart';

class FormSetorScreen extends StatefulWidget {
  final String? sectorId; // null = criar novo

  const FormSetorScreen({super.key, this.sectorId});

  @override
  State<FormSetorScreen> createState() => _FormSetorScreenState();
}

class _FormSetorScreenState extends State<FormSetorScreen> {
  final _db = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _nomeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _categoria;

  bool _loading = false;
  bool _loadingData = false;
  bool _isEdit = false;

  /// Supervisor responsável pelo setor. Só o Diretor escolhe: um Supervisor
  /// que cria setor vira dono automaticamente (exigência da policy
  /// sectors_supervisor_insert) e não pode transferir a responsabilidade.
  bool _isDirector = false;
  List<Profile> _supervisores = [];
  String? _ownerSelecionado;

  @override
  void initState() {
    super.initState();
    _isEdit = widget.sectorId != null;
    _isDirector = context.read<AuthProvider>().profile?.role == 'director';
    if (_isDirector) _loadSupervisores();
    if (_isEdit) _loadSetor();
  }

  /// Supervisores ativos do hospital, para o Diretor escolher o responsável.
  Future<void> _loadSupervisores() async {
    final profile = context.read<AuthProvider>().profile;
    if (profile?.hospitalId == null) return;
    try {
      final rows = await _db
          .from('profiles')
          .select()
          .eq('hospital_id', profile!.hospitalId!)
          .eq('role', 'supervisor')
          .eq('status', 'active')
          .order('full_name', ascending: true);
      if (mounted) {
        setState(() {
          _supervisores = (rows as List).map((e) => Profile.fromJson(e)).toList();
        });
      }
    } catch (e) {
      debugPrint('[FormSetor] _loadSupervisores: $e');
    }
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSetor() async {
    setState(() => _loadingData = true);
    try {
      final data = await _db
          .from('sectors')
          .select()
          .eq('id', widget.sectorId!)
          .single();

      if (mounted) {
        _nomeCtrl.text = data['name'] as String;
        _descCtrl.text = (data['description'] as String?) ?? '';
        setState(() {
          _categoria = data['nr32_category'] as String?;
          _ownerSelecionado = data['owner_supervisor_id'] as String?;
          _loadingData = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final auth = context.read<AuthProvider>();
    final profile = auth.profile!;

    try {
      if (_isEdit) {
        await _db.from('sectors').update({
          'name': _nomeCtrl.text.trim(),
          'description': _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
          'nr32_category': _categoria,
          // Só o Diretor mexe no responsável. Omitir a chave quando é
          // Supervisor evita que ele se remova do próprio setor e caia fora
          // da policy sectors_supervisor_update no meio da operação.
          if (_isDirector) 'owner_supervisor_id': _ownerSelecionado,
        }).eq('id', widget.sectorId!);

        await AuditService.log(
          userId: profile.id,
          hospitalId: profile.hospitalId,
          action: 'editar_setor',
          entityType: 'sector',
          entityId: widget.sectorId!,
          details: {
            'name': _nomeCtrl.text.trim(),
            if (_isDirector) 'owner_supervisor_id': _ownerSelecionado,
          },
        );
      } else {
        // Supervisor que cria um setor vira automaticamente o owner
        // (policy sectors_supervisor_insert exige owner_supervisor_id =
        // auth.uid()). O Diretor agora escolhe o responsável já na criação:
        // antes o campo ficava sempre nulo e não havia como preenchê-lo
        // depois, então setor criado por Diretor nunca ganhava Supervisor.
        final result = await _db.from('sectors').insert({
          'hospital_id': profile.hospitalId,
          'owner_supervisor_id':
              profile.role == 'supervisor' ? profile.id : _ownerSelecionado,
          'name': _nomeCtrl.text.trim(),
          'description': _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
          'nr32_category': _categoria,
          'created_by': profile.id,
          'status': 'active',
        }).select('id').single();

        await AuditService.log(
          userId: profile.id,
          hospitalId: profile.hospitalId,
          action: 'criar_setor',
          entityType: 'sector',
          entityId: result['id'] as String,
          details: {
            'name': _nomeCtrl.text.trim(),
            'owner_supervisor_id':
                profile.role == 'supervisor' ? profile.id : _ownerSelecionado,
          },
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(_isEdit ? 'Setor atualizado.' : 'Setor criado.'),
          backgroundColor: AppColors.compliant,
        ));
        Navigator.pop(context);
      }
    } on PostgrestException catch (e) {
      debugPrint('[FormSetor] PostgrestException: ${e.message} | code: ${e.code} | details: ${e.details} | hint: ${e.hint}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(
              'Não foi possível salvar o setor. Tente novamente.'),
          backgroundColor: AppColors.nonCompliant,
          duration: const Duration(seconds: 6),
        ));
      }
    } catch (e) {
      debugPrint('[FormSetor] erro inesperado: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(
              'Não foi possível salvar o setor. Tente novamente.'),
          backgroundColor: AppColors.nonCompliant,
          duration: const Duration(seconds: 6),
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingData) {
      return Scaffold(
          appBar: AppBar(title: Text(_isEdit ? 'Editar Setor' : 'Novo Setor')),
          body: const Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar:
          AppBar(title: Text(_isEdit ? 'Editar Setor' : 'Novo Setor')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimensions.screenPadding),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nomeCtrl,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Nome do setor *'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Campo obrigatório'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descCtrl,
                maxLength: 1000,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Descrição (opcional)'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                key: ValueKey(_categoria),
                decoration: const InputDecoration(
                    labelText: 'Categoria NR-32 (opcional)'),
                initialValue: _categoria,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Nenhuma')),
                  // Valor legado já salvo entra como opção extra para não
                  // quebrar o dropdown após a mudança da lista de categorias.
                  ...AppConstants.nr32CategoryOptions(_categoria)
                      .map((c) => DropdownMenuItem(value: c, child: Text(c))),
                ],
                onChanged: (v) => setState(() => _categoria = v),
              ),

              // Responsável pelo setor — só o Diretor define.
              if (_isDirector) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  key: ValueKey(_ownerSelecionado),
                  decoration: const InputDecoration(
                    labelText: 'Supervisor responsável',
                    helperText: 'Pode ficar sem responsável — nesse caso o '
                        'setor é gerenciado direto pelo Diretor.',
                    helperMaxLines: 2,
                  ),
                  initialValue: _ownerSelecionado,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Sem responsável'),
                    ),
                    ..._supervisores.map((sup) => DropdownMenuItem<String?>(
                          value: sup.id,
                          child: Text(sup.fullName),
                        )),
                  ],
                  onChanged: (v) => setState(() => _ownerSelecionado = v),
                ),
                if (_supervisores.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Nenhum Supervisor ativo neste hospital ainda. '
                      'Convide um pela tela de Equipe.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
              ],

              const SizedBox(height: 32),
              SizedBox(
                height: AppDimensions.buttonHeight,
                child: ElevatedButton(
                  onPressed: _loading ? null : _salvar,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(_isEdit ? 'Salvar alterações' : 'Criar Setor'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
