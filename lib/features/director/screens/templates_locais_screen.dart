import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/checklist_template.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/skeleton_loader.dart';

class TemplatesLocaisScreen extends StatefulWidget {
  const TemplatesLocaisScreen({super.key});

  @override
  State<TemplatesLocaisScreen> createState() => _TemplatesLocaisScreenState();
}

class _TemplatesLocaisScreenState extends State<TemplatesLocaisScreen> {
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
    final hospitalId = context.read<AuthProvider>().profile?.hospitalId;
    if (hospitalId == null) {
      // Perfil ainda nao carregado: encerra o loading para
      // a tela nao ficar presa no skeleton indefinidamente.
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final data = await _db
          .from('checklist_templates')
          .select()
          .eq('scope', 'local')
          .eq('hospital_id', hospitalId)
          .order('title', ascending: true);

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
      appBar: AppBar(title: const Text('Templates Locais')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push(AppRoutes.novoTemplateLocal);
          _load();
        },
        label: const Text('Novo template'),
        icon: const Icon(Icons.add),
      ),
      body: _loading
          ? const SkeletonList(itemHeight: 76)
          : RefreshIndicator(
              onRefresh: _load,
              child: _templates.isEmpty
                  ? const EmptyState(
                      icon: Icons.description_outlined,
                      title: 'Nenhum template local',
                      subtitle:
                          'Crie um template para reaproveitar os mesmos '
                          'itens em vários checklists deste hospital.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        AppDimensions.screenPadding,
                        AppDimensions.screenPadding,
                        AppDimensions.screenPadding,
                        // Folga para o botao flutuante nao cobrir o
                        // ultimo item da lista.
                        96,
                      ),
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
                                ? Text(
                                    t.nr32Category!,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  )
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!t.isActive)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.textDisabled.withAlpha(
                                        30,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'Inativo',
                                      style: TextStyle(
                                        color: AppColors.textDisabled,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.chevron_right,
                                  color: AppColors.textSecondary,
                                ),
                              ],
                            ),
                            onTap: () async {
                              await context.push(
                                AppRoutes.editarTemplateLocal(t.id),
                              );
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
