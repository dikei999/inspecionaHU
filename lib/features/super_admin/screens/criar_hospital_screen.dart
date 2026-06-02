import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/services/audit_service.dart';
import '../../auth/providers/auth_provider.dart';

class CriarHospitalScreen extends StatefulWidget {
  const CriarHospitalScreen({super.key});

  @override
  State<CriarHospitalScreen> createState() => _CriarHospitalScreenState();
}

class _CriarHospitalScreenState extends State<CriarHospitalScreen> {
  final _db = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _nomeCtrl = TextEditingController();
  final _siglaCtrl = TextEditingController();
  final _cidadeCtrl = TextEditingController();
  String? _estado;
  bool _loading = false;

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _siglaCtrl.dispose();
    _cidadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final auth = context.read<AuthProvider>();

    try {
      final result = await _db.from('hospitals').insert({
        'name': _nomeCtrl.text.trim(),
        'sigla': _siglaCtrl.text.trim().toUpperCase(),
        'city': _cidadeCtrl.text.trim(),
        'state': _estado,
        'status': 'active',
      }).select('id').single();

      await AuditService.log(
        userId: auth.profile!.id,
        action: 'criar_hospital',
        entityType: 'hospital',
        entityId: result['id'] as String,
        details: {
          'name': _nomeCtrl.text.trim(),
          'sigla': _siglaCtrl.text.trim().toUpperCase(),
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Hospital criado com sucesso.'),
          backgroundColor: AppColors.compliant,
        ));
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Erro ao criar hospital. Tente novamente.'),
          backgroundColor: AppColors.nonCompliant,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Novo Hospital')),
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
                decoration: const InputDecoration(
                  labelText: 'Nome do hospital *',
                  hintText: 'ex: Hospital Universitário da UFPI',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _siglaCtrl,
                maxLength: 10,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Sigla *',
                  hintText: 'ex: HU-UFPI',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cidadeCtrl,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Cidade *',
                  hintText: 'ex: Teresina',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey(_estado),
                initialValue: _estado,
                decoration: const InputDecoration(labelText: 'Estado (UF) *'),
                items: AppConstants.brazilianStates
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => _estado = v),
                validator: (v) => v == null ? 'Campo obrigatório' : null,
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
                      : const Text('Criar Hospital'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
