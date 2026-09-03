import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/services/audit_service.dart';
import '../../auth/providers/auth_provider.dart';

/// Tela compartilhada para criar/editar templates globais (super_admin)
/// e templates locais (director). Controle via [scope] e [templateId].
class FormTemplateScreen extends StatefulWidget {
  final String scope; // 'global' | 'local'
  final String? templateId; // null = criar novo

  const FormTemplateScreen({
    super.key,
    required this.scope,
    this.templateId,
  });

  @override
  State<FormTemplateScreen> createState() => _FormTemplateScreenState();
}

class _FormTemplateScreenState extends State<FormTemplateScreen> {
  final _db = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _tituloCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _categoria;

  bool _loading = false;
  bool _loadingTemplate = false;
  bool _isEdit = false;
  String? _existingStatus;

  final List<_ItemForm> _itens = [];

  @override
  void initState() {
    super.initState();
    _isEdit = widget.templateId != null;
    if (_isEdit) _loadTemplate();
  }

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _descCtrl.dispose();
    for (final item in _itens) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _loadTemplate() async {
    setState(() => _loadingTemplate = true);
    try {
      final tmpl = await _db
          .from('checklist_templates')
          .select()
          .eq('id', widget.templateId!)
          .single();

      final items = await _db
          .from('checklist_template_items')
          .select()
          .eq('template_id', widget.templateId!)
          .order('order_index', ascending: true);

      if (mounted) {
        _tituloCtrl.text = tmpl['title'] as String;
        _descCtrl.text = (tmpl['description'] as String?) ?? '';
        _existingStatus = tmpl['status'] as String;
        setState(() {
          _categoria = tmpl['nr32_category'] as String?;
          _itens.clear();
          for (final item in items) {
            _itens.add(_ItemForm.fromJson(item));
          }
          _loadingTemplate = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingTemplate = false);
        _showSnack('Erro ao carregar template.', error: true);
      }
    }
  }

  void _addItem() {
    setState(() => _itens.add(_ItemForm()));
  }

  void _removeItem(int index) {
    setState(() {
      _itens[index].dispose();
      _itens.removeAt(index);
    });
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_itens.isEmpty) {
      _showSnack('Adicione ao menos um item ao template.', error: true);
      return;
    }
    // Validate items
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
        'title': _tituloCtrl.text.trim(),
        'description':
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'nr32_category': _categoria,
        'scope': widget.scope,
        'hospital_id': widget.scope == 'local' ? profile.hospitalId : null,
        'created_by': profile.id,
        'status': 'active',
      };

      String templateId;

      if (_isEdit) {
        await _db
            .from('checklist_templates')
            .update({
              'title': payload['title'],
              'description': payload['description'],
              'nr32_category': payload['nr32_category'],
            })
            .eq('id', widget.templateId!);
        templateId = widget.templateId!;

        // Recria os itens (apaga e reinsere)
        await _db
            .from('checklist_template_items')
            .delete()
            .eq('template_id', templateId);
      } else {
        final result = await _db
            .from('checklist_templates')
            .insert(payload)
            .select('id')
            .single();
        templateId = result['id'] as String;
      }

      // Insere os itens
      final itemsPayload = _itens.asMap().entries.map((e) {
        final idx = e.key;
        final item = e.value;
        return {
          'template_id': templateId,
          'order_index': idx,
          'description': item.descricaoCtrl.text.trim(),
          'nr32_reference': item.referenciaCtrl.text.trim().isEmpty
              ? null
              : item.referenciaCtrl.text.trim(),
          'criticality': item.critico ? 'critical' : 'normal',
          'requires_photo': item.requiresPhoto,
        };
      }).toList();

      await _db.from('checklist_template_items').insert(itemsPayload);

      await AuditService.log(
        userId: profile.id,
        hospitalId: profile.hospitalId,
        action: _isEdit ? 'editar_template' : 'criar_template',
        entityType: 'checklist_template',
        entityId: templateId,
        details: {'title': payload['title'], 'scope': widget.scope},
      );

      if (mounted) {
        _showSnack(_isEdit ? 'Template atualizado.' : 'Template criado.');
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) _showSnack('Erro ao salvar template.', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _desativar() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desativar template?'),
        content: const Text(
            'O template ficará indisponível para novos checklists. Os checklists existentes não são afetados.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.nonCompliant),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desativar'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final auth = context.read<AuthProvider>();
    final newStatus =
        _existingStatus == 'active' ? 'inactive' : 'active';

    try {
      await _db
          .from('checklist_templates')
          .update({'status': newStatus})
          .eq('id', widget.templateId!);

      await AuditService.log(
        userId: auth.profile!.id,
        hospitalId: auth.profile!.hospitalId,
        action: '${newStatus == 'inactive' ? 'desativar' : 'reativar'}_template',
        entityType: 'checklist_template',
        entityId: widget.templateId!,
      );

      if (mounted) {
        _showSnack(
            newStatus == 'inactive' ? 'Template desativado.' : 'Template reativado.');
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) _showSnack('Erro ao alterar status.', error: true);
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
    final title = _isEdit
        ? 'Editar Template'
        : widget.scope == 'global'
            ? 'Novo Template Global'
            : 'Novo Template Local';

    if (_loadingTemplate) {
      return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: const Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (_isEdit)
            IconButton(
              icon: Icon(
                _existingStatus == 'active'
                    ? Icons.block
                    : Icons.check_circle_outline,
                color: _existingStatus == 'active'
                    ? AppColors.nonCompliant
                    : AppColors.compliant,
              ),
              tooltip: _existingStatus == 'active' ? 'Desativar' : 'Reativar',
              onPressed: _desativar,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppDimensions.screenPadding),
          children: [
            // ── Dados do template ──────────────────────────────────────
            TextFormField(
              controller: _tituloCtrl,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Título *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Campo obrigatório' : null,
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
              decoration:
                  const InputDecoration(labelText: 'Categoria NR-32 (opcional)'),
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
            const SizedBox(height: 24),

            // ── Itens ──────────────────────────────────────────────────
            Row(
              children: [
                Text('Itens do template',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addItem,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Adicionar item'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (_itens.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius:
                      BorderRadius.circular(AppDimensions.radiusCard),
                ),
                child: const Text(
                  'Nenhum item adicionado. Use o botão acima.',
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
                  _ItemCard(
                    key: ValueKey(_itens[i].key),
                    index: i,
                    item: _itens[i],
                    onRemove: () => _removeItem(i),
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
                    : Text(_isEdit ? 'Salvar alterações' : 'Criar template'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ── Modelo interno de item ────────────────────────────────────────────────────

class _ItemForm {
  final String key = UniqueKey().toString();
  final TextEditingController descricaoCtrl;
  final TextEditingController referenciaCtrl;
  bool critico;
  bool requiresPhoto;

  _ItemForm({
    String descricao = '',
    String referencia = '',
    this.critico = false,
    this.requiresPhoto = false,
  })  : descricaoCtrl = TextEditingController(text: descricao),
        referenciaCtrl = TextEditingController(text: referencia);

  factory _ItemForm.fromJson(Map<String, dynamic> json) => _ItemForm(
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

// ── Widget de card de item ────────────────────────────────────────────────────

class _ItemCard extends StatefulWidget {
  final int index;
  final _ItemForm item;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _ItemCard({
    required super.key,
    required this.index,
    required this.item,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
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
                  tooltip: 'Remover item',
                ),
              ],
            ),
            const SizedBox(height: 8),
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
                  labelText: 'Referência NR-32 (opcional)',
                  hintText: 'ex: NR-32.3.1.2'),
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
                      setState(() => widget.item.requiresPhoto = v ?? false);
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
