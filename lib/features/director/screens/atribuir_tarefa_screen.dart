import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/checklist.dart';
import '../../../core/models/profile.dart';
import '../../../core/models/sector.dart';
import '../../../core/services/audit_service.dart';
import '../../auth/providers/auth_provider.dart';

class AtribuirTarefaScreen extends StatefulWidget {
  const AtribuirTarefaScreen({super.key});

  @override
  State<AtribuirTarefaScreen> createState() => _AtribuirTarefaScreenState();
}

class _AtribuirTarefaScreenState extends State<AtribuirTarefaScreen> {
  final _db = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _loadingData = true;

  List<Sector> _setores = [];
  List<Checklist> _checklists = [];
  List<Profile> _inspetores = [];

  Sector? _setorSel;
  Checklist? _checklistSel;
  final Set<String> _inspetoresSel = {};
  DateTime? _prazo;

  String? _hospitalId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadingData = true);
    final profile = context.read<AuthProvider>().profile;
    _hospitalId = profile?.hospitalId;
    if (_hospitalId == null) return;

    try {
      final setoresData = await _db
          .from('sectors')
          .select()
          .eq('hospital_id', _hospitalId!)
          .eq('status', 'active')
          .order('name');

      if (mounted) {
        setState(() {
          _setores = setoresData.map(Sector.fromJson).toList();
          _loadingData = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  Future<void> _onSetorChanged(Sector? setor) async {
    setState(() {
      _setorSel = setor;
      _checklistSel = null;
      _checklists = [];
      _inspetores = [];
      _inspetoresSel.clear();
    });
    if (setor == null) return;

    try {
      final clData = await _db
          .from('checklists')
          .select()
          .eq('sector_id', setor.id)
          .eq('status', 'active')
          .order('title');

      // Inspetores vinculados ao setor via inspector_sectors
      final inspLinks = await _db
          .from('inspector_sectors')
          .select('inspector_id')
          .eq('sector_id', setor.id)
          .eq('status', 'active');

      List<Profile> insp = [];
      if (inspLinks.isNotEmpty) {
        final ids = inspLinks.map((e) => e['inspector_id'] as String).toList();
        final inspData = await _db
            .from('profiles')
            .select()
            .inFilter('id', ids)
            .eq('status', 'active');
        insp = inspData.map(Profile.fromJson).toList();
      }

      if (mounted) {
        setState(() {
          _checklists = clData.map(Checklist.fromJson).toList();
          _inspetores = insp;
        });
      }
    } catch (_) {}
  }

  Future<void> _atribuir() async {
    if (!_formKey.currentState!.validate()) return;
    if (_checklistSel == null) {
      _showSnack('Selecione um checklist.', error: true);
      return;
    }
    if (_inspetoresSel.isEmpty) {
      _showSnack('Selecione ao menos um Inspetor.', error: true);
      return;
    }
    if (_prazo == null) {
      _showSnack('Defina o prazo.', error: true);
      return;
    }

    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    final profile = auth.profile!;

    try {
      final tasks = _inspetoresSel.map((inspId) => {
            'checklist_id': _checklistSel!.id,
            'sector_id': _setorSel!.id,
            'hospital_id': _hospitalId,
            'inspector_id': inspId,
            'assigned_by': profile.id,
            'due_date': _prazo!.toIso8601String().substring(0, 10),
            'status': 'pending',
          }).toList();

      final results = await _db
          .from('tasks')
          .insert(tasks)
          .select('id');

      for (final r in results) {
        await AuditService.log(
          userId: profile.id,
          hospitalId: _hospitalId,
          action: 'atribuir_tarefa',
          entityType: 'task',
          entityId: r['id'] as String,
          details: {
            'checklist_id': _checklistSel!.id,
            'checklist_title': _checklistSel!.title,
            'sector_id': _setorSel!.id,
            'due_date': _prazo!.toIso8601String().substring(0, 10),
          },
        );
      }

      if (mounted) {
        _showSnack(
            '${_inspetoresSel.length} tarefa(s) atribuída(s) com sucesso.');
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) _showSnack('Erro ao atribuir tarefas.', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.nonCompliant : AppColors.compliant,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingData) {
      return Scaffold(
          appBar: AppBar(title: const Text('Atribuir Tarefa')),
          body: const Center(child: CircularProgressIndicator()));
    }

    final fmt = DateFormat('dd/MM/yyyy');

    return Scaffold(
      appBar: AppBar(title: const Text('Atribuir Tarefa')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppDimensions.screenPadding),
          children: [
            DropdownButtonFormField<Sector>(
              key: ValueKey(_setorSel),
              decoration: const InputDecoration(labelText: 'Setor *'),
              initialValue: _setorSel,
              items: _setores
                  .map((s) =>
                      DropdownMenuItem(value: s, child: Text(s.name)))
                  .toList(),
              onChanged: _onSetorChanged,
              validator: (v) => v == null ? 'Selecione um setor' : null,
            ),
            const SizedBox(height: 16),

            if (_setorSel != null) ...[
              DropdownButtonFormField<Checklist>(
                key: ValueKey(_checklistSel),
                decoration: const InputDecoration(labelText: 'Checklist *'),
                initialValue: _checklistSel,
                items: _checklists
                    .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(
                            '${c.title}  (${AppConstants.frequencyLabel(c.frequency)})')))
                    .toList(),
                onChanged: (v) => setState(() => _checklistSel = v),
                validator: (v) =>
                    v == null ? 'Selecione um checklist' : null,
              ),
              const SizedBox(height: 16),

              // Seleção de Inspetores
              Text('Inspetores *',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              if (_inspetores.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius:
                        BorderRadius.circular(AppDimensions.radiusCard),
                  ),
                  child: const Text(
                    'Nenhum Inspetor vinculado a este setor.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              else
                ...(_inspetores.map((insp) => CheckboxListTile(
                      title: Text(insp.fullName),
                      subtitle: Text(insp.email),
                      value: _inspetoresSel.contains(insp.id),
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _inspetoresSel.add(insp.id);
                          } else {
                            _inspetoresSel.remove(insp.id);
                          }
                        });
                      },
                    ))),
              const SizedBox(height: 16),

              // Prazo
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now().add(const Duration(days: 1)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null && mounted) {
                    setState(() => _prazo = picked);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Prazo *'),
                  child: Text(
                    _prazo != null ? fmt.format(_prazo!) : 'Selecionar data',
                    style: TextStyle(
                      color: _prazo != null
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              SizedBox(
                height: AppDimensions.buttonHeight,
                child: ElevatedButton(
                  onPressed: _loading ? null : _atribuir,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Atribuir Tarefa(s)'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
