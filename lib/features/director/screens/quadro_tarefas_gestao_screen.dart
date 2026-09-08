import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/checklist.dart';
import '../../../core/models/profile.dart';
import '../../../core/models/sector.dart';
import '../../../core/models/task.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/skeleton_loader.dart';
import '../../../widgets/status_badge.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/services/audit_service.dart';
import '../../../widgets/confirm_dialog.dart';

class QuadroTarefasGestaoScreen extends StatefulWidget {
  const QuadroTarefasGestaoScreen({super.key});

  @override
  State<QuadroTarefasGestaoScreen> createState() =>
      _QuadroTarefasGestaoScreenState();
}

class _QuadroTarefasGestaoScreenState
    extends State<QuadroTarefasGestaoScreen> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  List<_TaskView> _tasks = [];
  List<_TaskView> _filtered = [];
  List<Sector> _setores = [];
  List<Profile> _inspetores = [];

  String? _filterSector;
  String? _filterInspector;
  String? _filterStatus;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final hospitalId =
        context.read<AuthProvider>().profile?.hospitalId;
    if (hospitalId == null) {
      // Perfil ainda nao carregado: encerra o loading para
      // a tela nao ficar presa no skeleton indefinidamente.
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final tasksData = await _db
          .from('tasks')
          .select()
          .eq('hospital_id', hospitalId)
          // Tarefa cancelada (serie interrompida) sai das listas.
          .neq('status', 'cancelled')
          .order('due_date', ascending: true);

      final setoresData = await _db
          .from('sectors')
          .select()
          .eq('hospital_id', hospitalId)
          .eq('status', 'active')
          .order('name', ascending: true);

      final inspData = await _db
          .from('profiles')
          .select()
          .eq('hospital_id', hospitalId)
          .eq('role', 'inspector')
          .order('full_name', ascending: true);

      // Busca checklists e inspetores para enriquecimento
      final checklistIds = tasksData
          .map((t) => t['checklist_id'] as String)
          .toSet()
          .toList();
      Map<String, Checklist> checklistMap = {};
      if (checklistIds.isNotEmpty) {
        final clData = await _db
            .from('checklists')
            .select()
            .inFilter('id', checklistIds);
        for (final c in clData) {
          final cl = Checklist.fromJson(c);
          checklistMap[cl.id] = cl;
        }
      }

      final inspMap = <String, Profile>{};
      for (final i in inspData) {
        final p = Profile.fromJson(i);
        inspMap[p.id] = p;
      }

      final sectorMap = <String, Sector>{};
      for (final s in setoresData) {
        final sec = Sector.fromJson(s);
        sectorMap[sec.id] = sec;
      }

      final tasks = tasksData
          .map((t) {
            final task = Task.fromJson(t);
            return _TaskView(
              task: task,
              checklist: checklistMap[task.checklistId],
              inspector: inspMap[task.inspectorId],
              sector: sectorMap[task.sectorId],
            );
          })
          // Tarefa de checklist arquivado sai do quadro de gestao (bloco 1).
          // O registro continua no banco e no historico.
          .where((tv) => !(tv.checklist?.isArchived ?? false))
          .toList();

      if (mounted) {
        setState(() {
          _tasks = tasks;
          _setores = setoresData.map(Sector.fromJson).toList();
          _inspetores = inspData.map(Profile.fromJson).toList();
          _loading = false;
          _applyFilters();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilters() {
    setState(() {
      _filtered = _tasks.where((tv) {
        if (_filterSector != null && tv.task.sectorId != _filterSector) {
          return false;
        }
        if (_filterInspector != null &&
            tv.task.inspectorId != _filterInspector) {
          return false;
        }
        if (_filterStatus != null) {
          if (_filterStatus == 'overdue') {
            return tv.task.isOverdue;
          }
          return tv.task.status == _filterStatus;
        }
        return true;
      }).toList();
    });
  }

  /// Cancela a série: só as ocorrências FUTURAS ainda não respondidas.
  ///
  /// Soft delete — as linhas continuam na tabela com status 'cancelled'.
  /// O que já foi enviado ou validado permanece intacto, e a ocorrência de
  /// hoje também: cancelar não pode apagar trabalho do dia corrente.
  Future<void> _cancelarSerie(_TaskView tv) async {
    final seriesId = tv.task.seriesId;
    if (seriesId == null) return;

    // Lido antes de qualquer await: depois o context pode nao valer mais.
    final profile = context.read<AuthProvider>().profile!;

    final hoje = DateTime.now();
    final corte = DateTime(hoje.year, hoje.month, hoje.day)
        .toIso8601String()
        .substring(0, 10);

    // Quantas seriam afetadas — o Diretor confirma sabendo o número.
    int futuras;
    try {
      final rows = await _db
          .from('tasks')
          .select('id')
          .eq('series_id', seriesId)
          .inFilter('status', ['pending', 'in_progress']).gt('due_date', corte);
      futuras = (rows as List).length;
    } catch (e) {
      debugPrint('[QuadroGestao] _cancelarSerie contagem: $e');
      if (mounted) {
        showActionFeedback(
            context, 'Erro ao consultar a série. Tente novamente.',
            error: true);
      }
      return;
    }

    if (!mounted) return;

    if (futuras == 0) {
      showActionFeedback(
        context,
        'Não há ocorrências futuras pendentes nesta série para cancelar.',
      );
      return;
    }

    final ok = await confirmAction(
      context,
      title: 'Cancelar série?',
      message: '$futuras ocorrência(s) futura(s) ainda não respondida(s) '
          'serão canceladas.\n\nAs já enviadas ou validadas, e a de hoje, '
          'não são afetadas. Nada é apagado — as tarefas ficam registradas '
          'como canceladas.',
      confirmLabel: 'Cancelar série',
      cancelLabel: 'Manter',
      icon: Icons.event_busy_outlined,
    );
    if (!ok || !mounted) return;

    try {
      await _db
          .from('tasks')
          .update({'status': 'cancelled'})
          .eq('series_id', seriesId)
          .inFilter('status', ['pending', 'in_progress']).gt('due_date', corte);

      await AuditService.log(
        userId: profile.id,
        hospitalId: profile.hospitalId,
        action: 'cancelar_serie_tarefas',
        entityType: 'task',
        entityId: tv.task.id,
        details: {
          'series_id': seriesId,
          'canceladas': futuras,
          'a_partir_de': corte,
        },
      );

      if (mounted) {
        showActionFeedback(
            context, '$futuras ocorrência(s) futura(s) cancelada(s).');
        _load();
      }
    } catch (e) {
      debugPrint('[QuadroGestao] _cancelarSerie: $e');
      if (mounted) {
        showActionFeedback(context, 'Erro ao cancelar a série.', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quadro de Tarefas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterSheet,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Atribuir tarefa',
            onPressed: () async {
              await context.push(AppRoutes.atribuirTarefa);
              _load();
            },
          ),
        ],
      ),
      body: _loading
          ? const SkeletonList(itemHeight: 96)
          : RefreshIndicator(
              onRefresh: _load,
              child: _filtered.isEmpty
                  ? EmptyState(
                      icon: Icons.view_kanban_outlined,
                      title: 'Nenhuma tarefa encontrada',
                      subtitle:
                          'Ajuste os filtros ou atribua uma nova tarefa a um Inspetor.',
                      actionLabel: 'Atribuir tarefa',
                      onAction: () async {
                        await context.push(AppRoutes.atribuirTarefa);
                        _load();
                      },
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(
                          AppDimensions.screenPadding),
                      itemCount: _filtered.length,
                      itemBuilder: (ctx, i) {
                        final tv = _filtered[i];
                        final task = tv.task;
                        return Card(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(
                                AppDimensions.radiusCard),
                            onTap: task.status == 'submitted' ||
                                    task.status == 'validated'
                                ? () async {
                                    // Busca inspection ID para esta task
                                    final insp = await _db
                                        .from('inspections')
                                        .select('id')
                                        .eq('task_id', task.id)
                                        .order('created_at',
                                            ascending: false)
                                        .limit(1);
                                    if (insp.isNotEmpty && context.mounted) {
                                      context.push(
                                          AppRoutes.relatorioIndividual(
                                              insp.first['id'] as String));
                                    }
                                  }
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          tv.checklist?.title ??
                                              'Checklist removido',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                      ),
                                      StatusBadge(
                                        status: task.isOverdue
                                            ? 'overdue'
                                            : task.status,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Text(
                                        task.displayCode,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: AppColors.textSecondary,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures()
                                              ],
                                            ),
                                      ),
                                      // Posição na série recorrente.
                                      if (task.seriesLabel != null) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 1),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary50,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                  Icons
                                                      .event_repeat_outlined,
                                                  size: 10,
                                                  color: AppColors.primary),
                                              const SizedBox(width: 3),
                                              Text(
                                                task.seriesLabel!,
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  fontWeight:
                                                      FontWeight.w600,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Spacer(),
                                        // Cancela SÓ as ocorrências futuras
                                        // ainda não respondidas.
                                        TextButton.icon(
                                          onPressed: () =>
                                              _cancelarSerie(tv),
                                          style: TextButton.styleFrom(
                                            foregroundColor:
                                                AppColors.textSecondary,
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 6),
                                            minimumSize: Size.zero,
                                            tapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                            textStyle: const TextStyle(
                                                fontSize: 11),
                                          ),
                                          icon: const Icon(
                                              Icons.event_busy_outlined,
                                              size: 14),
                                          label: const Text('Cancelar série'),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${tv.sector?.name ?? '—'}  •  ${tv.inspector?.fullName ?? '—'}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(Icons.calendar_today_outlined,
                                          size: 14,
                                          color: task.isOverdue
                                              ? AppColors.nonCompliant
                                              : AppColors.textSecondary),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Prazo: ${fmt.format(task.dueDate)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: task.isOverdue
                                                  ? AppColors.nonCompliant
                                                  : null,
                                              fontWeight: task.isOverdue
                                                  ? FontWeight.w600
                                                  : null,
                                            ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Filtros', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                key: ValueKey(_filterSector),
                decoration: const InputDecoration(labelText: 'Setor'),
                initialValue: _filterSector,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todos')),
                  ..._setores.map((s) =>
                      DropdownMenuItem(value: s.id, child: Text(s.name))),
                ],
                onChanged: (v) => setLocal(() => _filterSector = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: ValueKey(_filterInspector),
                decoration: const InputDecoration(labelText: 'Inspetor'),
                initialValue: _filterInspector,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todos')),
                  ..._inspetores.map((p) => DropdownMenuItem(
                      value: p.id, child: Text(p.fullName))),
                ],
                onChanged: (v) => setLocal(() => _filterInspector = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: ValueKey(_filterStatus),
                decoration: const InputDecoration(labelText: 'Status'),
                initialValue: _filterStatus,
                items: const [
                  DropdownMenuItem(value: null, child: Text('Todos')),
                  DropdownMenuItem(value: 'pending', child: Text('Pendente')),
                  DropdownMenuItem(
                      value: 'in_progress', child: Text('Em andamento')),
                  DropdownMenuItem(value: 'submitted', child: Text('Enviado')),
                  DropdownMenuItem(
                      value: 'validated', child: Text('Validado')),
                  DropdownMenuItem(value: 'overdue', child: Text('Atrasado')),
                ],
                onChanged: (v) => setLocal(() => _filterStatus = v),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _applyFilters();
                },
                child: const Text('Aplicar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskView {
  final Task task;
  final Checklist? checklist;
  final Profile? inspector;
  final Sector? sector;
  _TaskView(
      {required this.task, this.checklist, this.inspector, this.sector});
}
