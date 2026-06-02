import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/checklist_template.dart';

class TemplatesGlobaisScreen extends StatefulWidget {
  const TemplatesGlobaisScreen({super.key});

  @override
  State<TemplatesGlobaisScreen> createState() => _TemplatesGlobaisScreenState();
}

class _TemplatesGlobaisScreenState extends State<TemplatesGlobaisScreen> {
  final _db = Supabase.instance.client;
  bool _loading = true;
  List<ChecklistTemplate> _templates = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _db
          .from('checklist_templates')
          .select()
          .eq('scope', 'global')
          .order('title');

      if (mounted) {
        setState(() {
          _templates = data.map(ChecklistTemplate.fromJson).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Templates Globais NR-32')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push(AppRoutes.novoTemplateGlobal);
          _load();
        },
        label: const Text('Novo template'),
        icon: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _templates.isEmpty
                  ? const Center(child: Text('Nenhum template global cadastrado.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(AppDimensions.screenPadding),
                      itemCount: _templates.length,
                      itemBuilder: (ctx, i) {
                        final t = _templates[i];
                        return Card(
                          child: ListTile(
                            leading: Icon(
                              Icons.checklist_outlined,
                              color: t.isActive
                                  ? AppColors.primary
                                  : AppColors.textDisabled,
                            ),
                            title: Text(t.title),
                            subtitle: t.nr32Category != null
                                ? Text(t.nr32Category!,
                                    style: Theme.of(context).textTheme.bodySmall)
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!t.isActive)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.textDisabled.withAlpha(30),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text('Inativo',
                                        style: TextStyle(
                                            color: AppColors.textDisabled,
                                            fontSize: 12)),
                                  ),
                                const SizedBox(width: 4),
                                const Icon(Icons.chevron_right,
                                    color: AppColors.textSecondary),
                              ],
                            ),
                            onTap: () async {
                              await context.push(
                                  AppRoutes.editarTemplateGlobal(t.id));
                              _load();
                            },
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
