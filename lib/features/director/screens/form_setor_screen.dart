import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_dimensions.dart';
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

  @override
  void initState() {
    super.initState();
    _isEdit = widget.sectorId != null;
    if (_isEdit) _loadSetor();
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
        }).eq('id', widget.sectorId!);

        await AuditService.log(
          userId: profile.id,
          hospitalId: profile.hospitalId,
          action: 'editar_setor',
          entityType: 'sector',
          entityId: widget.sectorId!,
          details: {'name': _nomeCtrl.text.trim()},
        );
      } else {
        final result = await _db.from('sectors').insert({
          'hospital_id': profile.hospitalId,
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
          details: {'name': _nomeCtrl.text.trim()},
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
          content: Text('Erro ao salvar setor: ${e.message}'),
          backgroundColor: AppColors.nonCompliant,
          duration: const Duration(seconds: 6),
        ));
      }
    } catch (e) {
      debugPrint('[FormSetor] erro inesperado: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro inesperado: $e'),
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
                  ...AppConstants.nr32Categories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c))),
                ],
                onChanged: (v) => setState(() => _categoria = v),
              ),
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
