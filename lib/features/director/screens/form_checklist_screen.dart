import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/checklist_template.dart';
import '../../../core/models/sector.dart';
import '../../../core/services/audit_service.dart';
import '../../auth/providers/auth_provider.dart';

class FormChecklistScreen extends StatefulWidget {
  final String? checklistId; // null = criar novo

  const FormChecklistScreen({super.key, this.checklistId});

  @override
  State<FormChecklistScreen> createState() => _FormChecklistScreenState();
}

class _FormChecklistScreenState extends State<FormChecklistScreen> {
  final _db = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _tituloCtrl = TextEditingController();

  bool _loading = false;
  bool _loadingData = true;
  bool _isEdit = false;

  List<Sector> _setores = [];
  Sector? _setorSelecionado;
  String _frequencia = 'monthly';
  final Set<String> _diasCustom = {};
  DateTime? _periodoInicio;
  DateTime? _periodoFim;
  final List<_ChecklistItemForm> _itens = [];

  List<ChecklistTemplate> _templates = [];
  String? _hospitalId;

  @override
  void initState() {
    super.initState();
    _isEdit = widget.checklistId != null;
    _loadInitialData();
  }

  @override
  void dispose() {
    _tituloCtrl.dispose();
    for (final item in _itens) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInitialData() async {
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

      final templatesData = await _db
          .from('checklist_templates')
          .select()
          .eq('status', 'active')
          .or('scope.eq.global,and(scope.eq.local,hospital_id.eq.$_hospitalId)')
          .order('title');

      if (mounted) {
        setState(() {
          _setores = setoresData.map(Sector.fromJson).toList();
          _templates = templatesData.map(ChecklistTemplate.fromJson).toList();
        });
      }

      if (_isEdit) await _loadChecklist();

      if (mounted) setState(() => _loadingData = false);
    } catch (_) {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  Future<void> _loadChecklist() async {
    final data = await _db
        .from('checklists')
        .select()
        .eq('id', widget.checklistId!)
        .single();

    final itemsData = await _db
        .from('checklist_items')
        .select()
        .eq('checklist_id', widget.checklistId!)
        .eq('status', 'active')
        .order('order_index');

    if (!mounted) return;

    _tituloCtrl.text = data['title'] as String;
    final sectorId = data['sector_id'] as String;
    setState(() {
      _setorSelecionado =
          _setores.where((s) => s.id == sectorId).firstOrNull;
      _frequencia = data['frequency'] as String;
      if (data['custom_days'] != null) {
        _diasCustom.addAll(
            (data['custom_days'] as List).map((d) => d as String));
      }
      _periodoInicio = data['period_start'] != null
          ? DateTime.parse(data['period_start'] as String)
          : null;
      _periodoFim = data['period_end'] != null
          ? DateTime.parse(data['period_end'] as String)
          : null;
      _itens.clear();
      for (final item in itemsData) {
        _itens.add(_ChecklistItemForm.fromJson(item));
      }
    });
  }

  Future<void> _importarTemplate() async {
    if (_templates.isEmpty) {
      _showSnack('Nenhum template disponível.', error: true);
      return;
    }

    ChecklistTemplate? selected;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importar de template'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: _templates.length,
            itemBuilder: (_, i) {
              final t = _templates[i];
              return ListTile(
                title: Text(t.title),
                subtitle:
                    t.nr32Category != null ? Text(t.nr32Category!) : null,
                leading: Icon(
                  t.isGlobal ? Icons.public : Icons.business,
                  color: AppColors.primary,
                ),
                onTap: () {
                  selected = t;
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
        ],
      ),
    );

    if (selected == null || !mounted) return;

    try {
      final items = await _db
          .from('checklist_template_items')
          .select()
          .eq('template_id', selected!.id)
          .order('order_index');

      if (mounted) {
        setState(() {
          _itens.addAll(items.map(
            (item) => _ChecklistItemForm(
              descricao: item['description'] as String,
              referencia: (item['nr32_reference'] as String?) ?? '',
              critico: (item['criticality'] as String) == 'critical',
              requiresPhoto: item['requires_photo'] as bool,
            ),
          ));
        });
        _showSnack(
            '${items.length} itens importados de "${selected!.title}".');
      }
    } catch (_) {
      if (mounted) _showSnack('Erro ao importar template.', error: true);
    }
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isStart) {
          _periodoInicio = picked;
        } else {
          _periodoFim = picked;
        }
      });
    }
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_setorSelecionado == null) {
      _showSnack('Selecione um setor.', error: true);
      return;
    }
    if (_itens.isEmpty) {
      _showSnack('Adicione ao menos um item.', error: true);
      return;
    }
    for (int i = 0; i < _itens.length; i++) {
      if (_itens[i].descricaoCtrl.text.trim().isEmpty) {
        _showSnack('Item ${i + 1}: descrição obrigatória.', error: true);
        return;
      }
    }
    if (_frequencia == 'custom' && _diasCustom.isEmpty) {
      _showSnack('Selecione ao menos um dia da semana.', error: true);
      return;
    }

    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    final profile = auth.profile!;

    try {
      final payload = {
        'sector_id': _setorSelecionado!.id,
        'hospital_id': _hospitalId,
        'title': _tituloCtrl.text.trim(),
        'frequency': _frequencia,
        'custom_days':
            _frequencia == 'custom' ? _diasCustom.toList() : null,
        'period_start': _periodoInicio?.toIso8601String().substring(0, 10),
        'period_end': _periodoFim?.toIso8601String().substring(0, 10),
        'created_by': profile.id,
        'status': 'active',
      };

      String checklistId;

      if (_isEdit) {
        await _db
            .from('checklists')
            .update({
              'title': payload['title'],
              'frequency': payload['frequency'],
              'custom_days': payload['custom_days'],
              'period_start': payload['period_start'],
              'period_end': payload['period_end'],
            })
            .eq('id', widget.checklistId!);
        checklistId = widget.checklistId!;

        // Desativa itens antigos e reinsere
        await _db
            .from('checklist_items')
            .update({
              'status': 'inactive',
              'last_modified_at': DateTime.now().toIso8601String(),
              'last_modified_by': profile.id,
            })
            .eq('checklist_id', checklistId);
      } else {
        final result = await _db
            .from('checklists')
            .insert(payload)
            .select('id')
            .single();
        checklistId = result['id'] as String;
      }

      final itemsPayload = _itens.asMap().entries.map((e) {
        final idx = e.key;
        final item = e.value;
        return {
          'checklist_id': checklistId,
          'order_index': idx,
          'description': item.descricaoCtrl.text.trim(),
          'nr32_reference': item.referenciaCtrl.text.trim().isEmpty
              ? null
              : item.referenciaCtrl.text.trim(),
          'criticality': item.critico ? 'critical' : 'normal',
          'requires_photo': item.requiresPhoto,
          'status': 'active',
          'last_modified_by': profile.id,
          'last_modified_at': DateTime.now().toIso8601String(),
        };
      }).toList();

      await _db.from('checklist_items').insert(itemsPayload);

      await AuditService.log(
        userId: profile.id,
        hospitalId: profile.hospitalId,
        action: _isEdit ? 'editar_checklist' : 'criar_checklist',
        entityType: 'checklist',
        entityId: checklistId,
        details: {
          'title': payload['title'],
          'sector_id': _setorSelecionado!.id,
        },
      );

      if (mounted) {
        _showSnack(_isEdit ? 'Checklist atualizado.' : 'Checklist criado.');
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) _showSnack('Erro ao salvar checklist.', error: true);
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
          appBar: AppBar(
              title:
                  Text(_isEdit ? 'Editar Checklist' : 'Novo Checklist')),
          body: const Center(child: CircularProgressIndicator()));
    }

    final fmt = DateFormat('dd/MM/yyyy');

    return Scaffold(
      appBar:
          AppBar(title: Text(_isEdit ? 'Editar Checklist' : 'Novo Checklist')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppDimensions.screenPadding),
          children: [
            // ── Dados básicos ─────────────────────────────────────────────
            TextFormField(
              controller: _tituloCtrl,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Título *'),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Campo obrigatório'
                  : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<Sector>(
              key: ValueKey(_setorSelecionado),
              decoration: const InputDecoration(labelText: 'Setor *'),
              initialValue: _setorSelecionado,
              items: _setores
                  .map((s) =>
                      DropdownMenuItem(value: s, child: Text(s.name)))
                  .toList(),
              onChanged: _isEdit
                  ? null
                  : (v) => setState(() => _setorSelecionado = v),
              validator: (v) => v == null ? 'Campo obrigatório' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: ValueKey(_frequencia),
              decoration: const InputDecoration(labelText: 'Frequência *'),
              initialValue: _frequencia,
              items: AppConstants.checklistFrequencies
                  .map((f) => DropdownMenuItem(
                      value: f['value']!, child: Text(f['label']!)))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _frequencia = v ?? 'monthly'),
            ),

            // Seletor de dias para frequência customizada
            if (_frequencia == 'custom') ...[
              const SizedBox(height: 12),
              Text('Dias da semana *',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: AppConstants.weekDays.map((d) {
                  final selected = _diasCustom.contains(d['value']!);
                  return FilterChip(
                    label: Text(d['label']!),
                    selected: selected,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _diasCustom.add(d['value']!);
                      } else {
                        _diasCustom.remove(d['value']!);
                      }
                    }),
                    selectedColor: AppColors.primary.withAlpha(40),
                    checkmarkColor: AppColors.primary,
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 16),

            // Período
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(true),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                          labelText: 'Início do período'),
                      child: Text(_periodoInicio != null
                          ? fmt.format(_periodoInicio!)
                          : 'Opcional'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(false),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                          labelText: 'Fim do período'),
                      child: Text(_periodoFim != null
                          ? fmt.format(_periodoFim!)
                          : 'Opcional'),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Itens ─────────────────────────────────────────────────────
            Row(
              children: [
                Text('Itens *',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: _importarTemplate,
                  icon: const Icon(Icons.file_copy_outlined, size: 18),
                  label: const Text('Usar template'),
                ),
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _itens.add(_ChecklistItemForm())),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Item'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (_itens.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
                ),
                child: const Text(
                  'Adicione itens manualmente ou importe de um template.',
                  textAlign: TextAlign.center,
                ),
              ),

            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorder: (oldIdx, newIdx) {
                setState(() {
                  if (newIdx > oldIdx) newIdx--;
                  final item = _itens.removeAt(oldIdx);
                  _itens.insert(newIdx, item);
                });
              },
              children: [
                for (int i = 0; i < _itens.length; i++)
                  _ChecklistItemCard(
                    key: ValueKey(_itens[i].key),
                    index: i,
                    item: _itens[i],
                    onRemove: () => setState(() {
                      _itens[i].dispose();
                      _itens.removeAt(i);
                    }),
                    onChanged: () => setState(() {}),
                  ),
              ],
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
                    : Text(_isEdit ? 'Salvar alterações' : 'Criar Checklist'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _ChecklistItemForm {
  final String key = UniqueKey().toString();
  final TextEditingController descricaoCtrl;
  final TextEditingController referenciaCtrl;
  bool critico;
  bool requiresPhoto;

  _ChecklistItemForm({
    String descricao = '',
    String referencia = '',
    this.critico = false,
    this.requiresPhoto = false,
  })  : descricaoCtrl = TextEditingController(text: descricao),
        referenciaCtrl = TextEditingController(text: referencia);

  factory _ChecklistItemForm.fromJson(Map<String, dynamic> json) =>
      _ChecklistItemForm(
        descricao: json['description'] as String,
        referencia: (json['nr32_reference'] as String?) ?? '',
        critico: (json['criticality'] as String) == 'critical',
        requiresPhoto: json['requires_photo'] as bool,
      );

  void dispose() {
    descricaoCtrl.dispose();
    referenciaCtrl.dispose();
  }
}

class _ChecklistItemCard extends StatefulWidget {
  final int index;
  final _ChecklistItemForm item;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _ChecklistItemCard({
    required super.key,
    required this.index,
    required this.item,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  State<_ChecklistItemCard> createState() => _ChecklistItemCardState();
}

class _ChecklistItemCardState extends State<_ChecklistItemCard> {
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ReorderableDragStartListener(
                  index: widget.index,
                  child: const Icon(Icons.drag_handle,
                      color: AppColors.textSecondary),
                ),
                const SizedBox(width: 8),
                Text('Item ${widget.index + 1}',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: AppColors.nonCompliant),
                  onPressed: widget.onRemove,
                ),
              ],
            ),
            TextFormField(
              controller: widget.item.descricaoCtrl,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Descrição *'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: widget.item.referenciaCtrl,
              maxLength: 100,
              decoration: const InputDecoration(
                  labelText: 'Referência NR-32 (opcional)'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: CheckboxListTile(
                    title: const Text('Crítico'),
                    value: widget.item.critico,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (v) {
                      setState(() => widget.item.critico = v ?? false);
                      widget.onChanged();
                    },
                  ),
                ),
                Expanded(
                  child: CheckboxListTile(
                    title: const Text('Exige foto'),
                    value: widget.item.requiresPhoto,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (v) {
                      setState(
                          () => widget.item.requiresPhoto = v ?? false);
                      widget.onChanged();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
