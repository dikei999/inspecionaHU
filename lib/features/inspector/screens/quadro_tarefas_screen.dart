import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/task.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../auth/providers/auth_provider.dart';

class QuadroTarefasScreen extends StatefulWidget {
  const QuadroTarefasScreen({super.key});

  @override
  State<QuadroTarefasScreen> createState() => _QuadroTarefasScreenState();
}

class _QuadroTarefasScreenState extends State<QuadroTarefasScreen> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  List<Task> _tasks = [];
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = context.read<AuthProvider>().profile?.id;
    if (uid == null) return;

    try {
      final data = await _db
          .from('tasks')
          .select()
          .eq('inspector_id', uid)
          .inFilter('status', ['pending', 'in_progress'])
          .order('due_date');

      if (mounted) {
        setState(() {
          _tasks = data.map(Task.fromJson).toList();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[QuadroTarefas] erro: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Task> get _filtered {
    return _tasks.where((t) {
      if (_filter == 'overdue') return t.isOverdue;
      if (_filter == 'in_progress') return t.status == 'in_progress';
      if (_filter == 'pending') return t.status == 'pending';
      return true;
    }).toList();
  }

  int get _overdueCount => _tasks.where((t) => t.isOverdue).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Minhas Tarefas'),
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
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Notificações',
            onPressed: () => context.push(AppRoutes.notificacoes),
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Perfil',
            onPressed: () => context.push(AppRoutes.perfil),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
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
                                  .where((t) => t.status == 'in_progress')
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
                                  .where((t) => t.status == 'pending')
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
                        ? _buildEmptyState()
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filtered.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) =>
                                _TaskCard(task: _filtered[i]),
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.task_alt, size: 64, color: AppColors.border),
            const SizedBox(height: 16),
            Text(
              _filter == 'all'
                  ? 'Nenhuma tarefa atribuída'
                  : 'Nenhuma tarefa nesta categoria',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _filter == 'all'
                  ? 'Quando um Supervisor ou Diretor atribuir uma tarefa, ela aparecerá aqui.'
                  : 'Toque em "Todas" para ver todas as tarefas.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
  final Task task;
  const _TaskCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final isOverdue = task.isOverdue;
    final isDueSoon = !isOverdue &&
        AppDateUtils.isDueSoon(task.dueDate);

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

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOverdue
              ? AppColors.nonCompliant.withValues(alpha: 0.4)
              : AppColors.border,
          width: isOverdue ? 1.0 : 0.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Tarefa #${task.id.substring(0, 8)}',
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  isOverdue
                      ? Icons.schedule_outlined
                      : Icons.calendar_today_outlined,
                  size: 14,
                  color: isOverdue
                      ? AppColors.nonCompliant
                      : isDueSoon
                          ? AppColors.pending
                          : AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  AppDateUtils.formatDate(task.dueDate),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isOverdue
                            ? AppColors.nonCompliant
                            : isDueSoon
                                ? AppColors.pending
                                : AppColors.textSecondary,
                        fontWeight:
                            isOverdue ? FontWeight.w600 : FontWeight.w400,
                      ),
                ),
                if (isOverdue) ...[
                  const SizedBox(width: 8),
                  Text(
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
                  Text(
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
    );
  }
}
