import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/task.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/notification_bell.dart';
import '../../../widgets/skeleton_loader.dart';
import '../../auth/providers/auth_provider.dart';
import '../../shared/widgets/dashboard_header.dart';

/// Task + dados de exibição (título do checklist e nome do setor).
class _TaskView {
  final Task task;
  final String checklistTitle;
  final String sectorName;
  const _TaskView({
    required this.task,
    required this.checklistTitle,
    required this.sectorName,
  });
}

class QuadroTarefasScreen extends StatefulWidget {
  const QuadroTarefasScreen({super.key});

  @override
  State<QuadroTarefasScreen> createState() => _QuadroTarefasScreenState();
}

class _QuadroTarefasScreenState extends State<QuadroTarefasScreen> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  List<_TaskView> _tasks = [];
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = context.read<AuthProvider>().profile?.id;
    if (uid == null) {
      // Perfil ainda nao carregado: encerra o loading para
      // a tela nao ficar presa no skeleton indefinidamente.
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final data = await _db
          .from('tasks')
          .select('*, checklists(title), sectors(name)')
          .eq('inspector_id', uid)
          .inFilter('status', ['pending', 'in_progress'])
          .order('due_date');

      if (mounted) {
        setState(() {
          _tasks = (data as List).map((e) {
            final map = e as Map<String, dynamic>;
            return _TaskView(
              task: Task.fromJson(map),
              checklistTitle: (map['checklists']
                      as Map<String, dynamic>?)?['title'] as String? ??
                  'Checklist',
              sectorName: (map['sectors'] as Map<String, dynamic>?)?['name']
                      as String? ??
                  'Setor',
            );
          }).toList();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[QuadroTarefas] erro: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Erro ao carregar tarefas. Tente novamente.'),
          backgroundColor: AppColors.nonCompliant,
        ));
      }
    }
  }

  List<_TaskView> get _filtered {
    return _tasks.where((tv) {
      if (_filter == 'overdue') return tv.task.isOverdue;
      if (_filter == 'in_progress') return tv.task.status == 'in_progress';
      if (_filter == 'pending') return tv.task.status == 'pending';
      return true;
    }).toList();
  }

  int get _overdueCount => _tasks.where((tv) => tv.task.isOverdue).length;

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().profile;
    final emAndamento =
        _tasks.where((t) => t.task.status == 'in_progress').length;
    final pendentes = _tasks.where((t) => t.task.status == 'pending').length;

    return Scaffold(
      body: Column(
        children: [
          // ── Header institucional azul ─────────────────────────────
          DashboardHeader(
            greeting: profile?.fullName != null
                ? 'Olá, ${profile!.fullName.split(' ').first}'
                : 'Minhas Tarefas',
            subtitle: 'Minhas tarefas de inspeção',
            actions: [
              IconButton(
                icon: const Icon(Icons.calendar_month_outlined),
                tooltip: 'Calendário',
                onPressed: () => context.push(AppRoutes.inspectorCalendario),
              ),
              IconButton(
                icon: const Icon(Icons.history_outlined),
                tooltip: 'Histórico',
                onPressed: () => context.push(AppRoutes.inspectorHistorico),
              ),
              const NotificationBell(),
              IconButton(
                icon: const Icon(Icons.person_outline),
                tooltip: 'Perfil',
                onPressed: () => context.push(AppRoutes.perfil),
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Sair',
                onPressed: () => context.read<AuthProvider>().signOut(),
              ),
            ],
            child: _loading
                ? null
                : Row(
                    children: [
                      Expanded(
                        child: HeaderMetric(
                          value: pendentes.toString(),
                          label: 'Pendentes',
                        ),
                      ),
                      Expanded(
                        child: HeaderMetric(
                          value: emAndamento.toString(),
                          label: 'Em andamento',
                        ),
                      ),
                      Expanded(
                        child: HeaderMetric(
                          value: _overdueCount.toString(),
                          label: 'Atrasadas',
                        ),
                      ),
                    ],
                  ),
          ),

          // ── Lista de tarefas ──────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const SkeletonList(itemHeight: 96)
                  : Column(
                      children: [
                  // ── Filtros ──────────────────────────────────────────
                  if (_tasks.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _FilterChip(
                              label: 'Todas',
                              count: _tasks.length,
                              selected: _filter == 'all',
                              onTap: () => setState(() => _filter = 'all'),
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: 'Em andamento',
                              count: _tasks
                                  .where((t) => t.task.status == 'in_progress')
                                  .length,
                              selected: _filter == 'in_progress',
                              color: AppColors.primary,
                              onTap: () =>
                                  setState(() => _filter = 'in_progress'),
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: 'Pendentes',
                              count: _tasks
                                  .where((t) => t.task.status == 'pending')
                                  .length,
                              selected: _filter == 'pending',
                              color: AppColors.pending,
                              onTap: () =>
                                  setState(() => _filter = 'pending'),
                            ),
                            if (_overdueCount > 0) ...[
                              const SizedBox(width: 8),
                              _FilterChip(
                                label: 'Atrasadas',
                                count: _overdueCount,
                                selected: _filter == 'overdue',
                                color: AppColors.nonCompliant,
                                onTap: () =>
                                    setState(() => _filter = 'overdue'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                  // ── Lista ou empty state ─────────────────────────────
                  Expanded(
                    child: _filtered.isEmpty
                        ? EmptyState(
                            icon: Icons.task_alt,
                            title: _filter == 'all'
                                ? 'Nenhuma tarefa atribuída'
                                : 'Nenhuma tarefa nesta categoria',
                            subtitle: _filter == 'all'
                                ? 'Quando um Supervisor ou Diretor atribuir uma tarefa, ela aparecerá aqui.'
                                : 'Toque em "Todas" para ver todas as tarefas.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filtered.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 10),
                            itemBuilder: (ctx, i) => _TaskCard(
                              taskView: _filtered[i],
                              onTap: () async {
                                await ctx.push(AppRoutes.responderChecklist(
                                    _filtered[i].task.id));
                                _load(); // recarrega após retornar
                              },
                            ),
                          ),
                  ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    this.color = AppColors.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : AppColors.border,
            width: selected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.3)
                      : color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : color,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final _TaskView taskView;
  final VoidCallback? onTap;
  const _TaskCard({required this.taskView, this.onTap});

  @override
  Widget build(BuildContext context) {
    final task = taskView.task;
    final isOverdue = task.isOverdue;
    final isDueSoon = !isOverdue && AppDateUtils.isDueSoon(task.dueDate);

    Color statusColor;
    String statusLabel;
    if (isOverdue) {
      statusColor = AppColors.nonCompliant;
      statusLabel = 'Atrasada';
    } else if (task.status == 'in_progress') {
      statusColor = AppColors.primary;
      statusLabel = 'Em andamento';
    } else {
      statusColor = AppColors.pending;
      statusLabel = 'Pendente';
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: isOverdue ? AppColors.nonCompliant50 : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isOverdue
                  ? AppColors.nonCompliant.withValues(alpha: 0.4)
                  : AppColors.border,
              width: isOverdue ? 1.0 : 0.5,
            ),
            boxShadow: AppShadows.card,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Barra lateral de status
                Container(
                  width: 4,
                  height: 56,
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              taskView.checklistTitle,
                              style: Theme.of(context).textTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        task.displayCode,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.domain_outlined,
                              size: 13, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              taskView.sectorName,
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            isOverdue
                                ? Icons.schedule_outlined
                                : Icons.calendar_today_outlined,
                            size: 13,
                            color: isOverdue
                                ? AppColors.nonCompliant
                                : isDueSoon
                                    ? AppColors.pending
                                    : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            AppDateUtils.formatDate(task.dueDate),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: isOverdue
                                      ? AppColors.nonCompliant
                                      : isDueSoon
                                          ? AppColors.pending
                                          : AppColors.textSecondary,
                                  fontWeight: isOverdue
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                          ),
                          if (isOverdue) ...[
                            const SizedBox(width: 8),
                            const Text(
                              'ATRASADA',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.nonCompliant,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ] else if (isDueSoon) ...[
                            const SizedBox(width: 8),
                            const Text(
                              'Vence em breve',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.pending,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right,
                    size: 18, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
