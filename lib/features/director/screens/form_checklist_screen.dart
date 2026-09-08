import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/checklist_template.dart';
import '../../../core/models/sector.dart';
import '../../../core/services/audit_service.dart';
import '../../auth/providers/auth_provider.dart';

class FormChecklistScreen extends StatefulWidget {
  final String? checklistId; // null = criar novo

  /// Setor pré-selecionado — usado quando a tela é aberta a partir da aba
  /// "Checklists" de um setor. Ignorado na edição (o setor é imutável lá).
  final String? initialSectorId;

  const FormChecklistScreen({
    super.key,
    this.checklistId,
    this.initialSectorId,
  });

  @override
  State<FormChecklistScreen> createState() => _FormChecklistScreenState();
}

class _FormChecklistScreenState extends State<FormChecklistScreen> {
  final _db = Supabase.instance.client;

  /// O setor veio da navegação (aba "Checklists" de um setor)? Então não se
  /// escolhe setor aqui — repetir a escolha só permitia sair do contexto
  /// por engano. Na edição o setor é imutável e também não vira campo.
  bool get _setorDoContexto => !_isEdit && widget.initialSectorId != null;
  final _formKey = GlobalKey<FormState>();
  final _tituloCtrl = TextEditingController();

  bool _loading = false;
  bool _loadingData = true;
  bool _isEdit = false;

  List<Sector> _setores = [];
  Sector? _setorSelecionado;
  /// Valor gravado em checklists.frequency, que é NOT NULL no schema.
  ///
  /// Prazo e frequência passaram a pertencer à ATRIBUIÇÃO DA TAREFA — o
  /// checklist é só o conjunto de itens. A coluna continua no banco por
  /// compatibilidade com os dados já existentes (nada foi deletado), mas
  /// não é mais exibida nem editada. Como é NOT NULL com CHECK, um valor
  /// fixo válido é gravado para o INSERT não falhar.
  static const _frequenciaPadrao = 'monthly';
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
          .order('name', ascending: true);

      final templatesData = await _db
          .from('checklist_templates')
          .select()
          .eq('status', 'active')
          .or('scope.eq.global,and(scope.eq.local,hospital_id.eq.$_hospitalId)')
          .order('title', ascending: true);

      if (mounted) {
        setState(() {
          _setores = setoresData.map(Sector.fromJson).toList();
          _templates = templatesData.map(ChecklistTemplate.fromJson).toList();
          if (!_isEdit && widget.initialSectorId != null) {
            _setorSelecionado = _setores
                .where((s) => s.id == widget.initialSectorId)
                .firstOrNull;
          }
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
        .order('order_index', ascending: true);

    if (!mounted) return;

    _tituloCtrl.text = data['title'] as String;
    final sectorId = data['sector_id'] as String;
    setState(() {
      _setorSelecionado =
          _setores.where((s) => s.id == sectorId).firstOrNull;
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
          .order('order_index', ascending: true);

      if (!mounted) return;

      if (items.isEmpty) {
        _showSnack(
            'O template "${selected!.title}" não possui itens para importar.',
            error: true);
        return;
      }

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
      _showSnack('${items.length} itens importados de "${selected!.title}".');
    } catch (_) {
      if (mounted) _showSnack('Erro ao importar template.', error: true);
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
    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    final profile = auth.profile!;

    try {
      final payload = {
        'sector_id': _setorSelecionado!.id,
        'hospital_id': _hospitalId,
        'title': _tituloCtrl.text.trim(),
        // NOT NULL no schema: grava o valor fixo e não usa mais na interface.
        'frequency': _frequenciaPadrao,
        'created_by': profile.id,
        'status': 'active',
      };

      String checklistId;

      if (_isEdit) {
        await _db
            .from('checklists')
            // Editar checklist mexe só no título e nos itens. Frequência,
            // período e dias existentes NÃO são sobrescritos: os dados
            // antigos ficam preservados no banco.
            .update({'title': payload['title']})
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


    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar Checklist' : 'Novo Checklist'),
        // Setor definido pela navegação vira subtítulo, não campo editável.
        bottom: (_setorDoContexto || _isEdit) && _setorSelecionado != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.domain_outlined,
                            size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 5),
                        Text(
                          _setorSelecionado!.name,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : null,
      ),
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
            // Só aparece quando a navegação NÃO definiu o setor. Na edição
            // o setor é imutável e já está no cabeçalho, então um dropdown
            // desabilitado seria só ruído.
            if (!_setorDoContexto && !_isEdit) ...[
              DropdownButtonFormField<Sector>(
                key: ValueKey(_setorSelecionado),
                decoration: const InputDecoration(labelText: 'Setor *'),
                initialValue: _setorSelecionado,
                items: _setores
                    .map((s) => DropdownMenuItem(value: s, child: Text(s.name)))
                    .toList(),
                onChanged: (v) => setState(() => _setorSelecionado = v),
                validator: (v) => v == null ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 16),
            ],
            // Prazo e frequência NÃO ficam mais aqui: pertencem à
            // atribuição da tarefa, onde a série recorrente é definida.
            // Definir nos dois lugares gerava conflito — o checklist é
            // apenas o conjunto de itens.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary50,
                borderRadius:
                    BorderRadius.circular(AppDimensions.radiusCard),
                border: Border.all(color: AppColors.primary100, width: 0.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Prazo e frequência são definidos ao atribuir a '
                      'tarefa, não aqui.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.primary),
                    ),
                  ),
                ],
              ),
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

            const SizedBox(height: 16),
          ],
        ),
      ),

      // ── Barra fixa: Adicionar item + Salvar ───────────────────────────
      // Fica sempre acessível, sem precisar rolar até o fim da lista.
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: AppDimensions.buttonHeight,
                child: OutlinedButton.icon(
                  onPressed: _loading
                      ? null
                      : () => setState(() => _itens.add(_ChecklistItemForm())),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Adicionar item'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
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
                      : Text(_isEdit ? 'Salvar' : 'Criar'),
                ),
              ),
            ),
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
