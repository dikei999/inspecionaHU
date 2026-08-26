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
          .order('due_date');

      final setoresData = await _db
          .from('sectors')
          .select()
          .eq('hospital_id', hospitalId)
          .eq('status', 'active')
          .order('name');

      final inspData = await _db
          .from('profiles')
          .select()
          .eq('hospital_id', hospitalId)
          .eq('role', 'inspector')
          .order('full_name');

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

      final tasks = tasksData.map((t) {
        final task = Task.fromJson(t);
        return _TaskView(
          task: task,
          checklist: checklistMap[task.checklistId],
          inspector: inspMap[task.inspectorId],
          sector: sectorMap[task.sectorId],
        );
      }).toList();

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
