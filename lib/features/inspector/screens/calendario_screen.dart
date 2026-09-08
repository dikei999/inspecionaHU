import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../core/constants/app_colors.dart';
import '../../../core/models/task.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../widgets/skeleton_loader.dart';
import '../../auth/providers/auth_provider.dart';

class CalendarioScreen extends StatefulWidget {
  const CalendarioScreen({super.key});

  @override
  State<CalendarioScreen> createState() => _CalendarioScreenState();
}

class _CalendarioScreenState extends State<CalendarioScreen> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  List<Task> _tasks = [];
  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDay;

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
          .select('*, checklists(archived_at)')
          .eq('inspector_id', uid)
          .order('due_date', ascending: true);

      if (mounted) {
        setState(() {
          _tasks = (data as List)
              // Checklist arquivado nao aparece no calendario (bloco 1).
              .where((e) =>
                  ((e as Map<String, dynamic>)['checklists']
                      as Map<String, dynamic>?)?['archived_at'] ==
                  null)
              .map((e) => Task.fromJson(e as Map<String, dynamic>))
              .toList();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[Calendario] erro: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<Task> _tasksForDay(DateTime day) {
    return _tasks.where((t) {
      return t.dueDate.year == day.year &&
          t.dueDate.month == day.month &&
          t.dueDate.day == day.day;
    }).toList();
  }

  List<Color> _dayDots(DateTime day) {
    final tasks = _tasksForDay(day);
    if (tasks.isEmpty) return [];
    final now = DateTime.now();
    final colors = <Color>{};
    for (final t in tasks) {
      if (t.dueDate.isBefore(now) &&
          t.status != 'submitted' &&
          t.status != 'validated') {
        colors.add(AppColors.statusOverdue);
      } else if (t.status == 'pending') {
        colors.add(AppColors.statusPending);
      } else if (t.status == 'in_progress') {
        colors.add(AppColors.statusInProgress);
      } else if (t.status == 'submitted') {
        colors.add(AppColors.statusSubmitted);
      } else if (t.status == 'validated') {
        colors.add(AppColors.statusValidated);
      }
    }
    return colors.take(3).toList();
  }

  // ── Mês anterior / próximo ─────────────────────────────────────────────────

  void _prevMonth() => setState(() {
        _focusedMonth =
            DateTime(_focusedMonth.year, _focusedMonth.month - 1);
        _selectedDay = null;
      });

  void _nextMonth() => setState(() {
        _focusedMonth =
            DateTime(_focusedMonth.year, _focusedMonth.month + 1);
        _selectedDay = null;
      });

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final selectedTasks =
        _selectedDay != null ? _tasksForDay(_selectedDay!) : <Task>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendário'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
            onPressed: () => context.read<AuthProvider>().signOut(),
          ),
        ],
      ),
      body: _loading
          ? const SkeletonList(itemCount: 4, itemHeight: 120)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Cabeçalho do mês ───────────────────────────────
                  _buildMonthHeader(context),
                  const SizedBox(height: 12),

                  // ── Grade do calendário ────────────────────────────
                  _buildCalendarGrid(context),
                  const SizedBox(height: 16),

                  // ── Legenda ────────────────────────────────────────
                  _buildLegend(context),
                  const SizedBox(height: 20),

                  // ── Tarefas do dia selecionado ─────────────────────
                  if (_selectedDay != null) ...[
                    Row(
                      children: [
                        Text(
                          AppDateUtils.formatDate(_selectedDay!),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${selectedTasks.length} tarefa${selectedTasks.length != 1 ? 's' : ''}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (selectedTasks.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.border, width: 0.5),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.event_available_outlined,
                                color: AppColors.textSecondary, size: 20),
                            const SizedBox(width: 10),
                            Text(
                              'Nenhuma tarefa neste dia.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      )
                    else
                      ...selectedTasks.map(
                          (t) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _DayTaskCard(task: t),
                              )),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildMonthHeader(BuildContext context) {
    final monthName = AppDateUtils.formatMonthYear(_focusedMonth);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _prevMonth,
            color: AppColors.primary,
          ),
          Text(
            monthName[0].toUpperCase() + monthName.substring(1),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _nextMonth,
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid(BuildContext context) {
    final firstDay =
        DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    // weekday: 1=Mon ... 7=Sun; queremos que Dom (7) apareça como 0
    int startWeekday = firstDay.weekday % 7; // Dom=0, Seg=1 ... Sab=6
    final daysInMonth =
        DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final today = DateTime.now();

    final dayLabels = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5),
        boxShadow: AppShadows.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Cabeçalho dos dias da semana
            Row(
              children: dayLabels
                  .map((d) => Expanded(
                        child: Text(
                          d,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),

            // Grade dos dias
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 1.0,
              ),
              itemCount: startWeekday + daysInMonth,
              itemBuilder: (ctx, index) {
                // Células vazias antes do dia 1
                if (index < startWeekday) {
                  return const SizedBox.shrink();
                }

                final dayNum = index - startWeekday + 1;
                final day = DateTime(
                    _focusedMonth.year, _focusedMonth.month, dayNum);
                final isToday = day.year == today.year &&
                    day.month == today.month &&
                    day.day == today.day;
                final isSelected = _selectedDay != null &&
                    _selectedDay!.year == day.year &&
                    _selectedDay!.month == day.month &&
                    _selectedDay!.day == day.day;
                final dots = _dayDots(day);

                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedDay =
                        isSelected ? null : day;
                  }),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : isToday
                              ? AppColors.primary.withValues(alpha: 0.08)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: isToday && !isSelected
                          ? Border.all(
                              color: AppColors.primary, width: 1.0)
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$dayNum',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isToday || isSelected
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: isSelected
                                ? Colors.white
                                : isToday
                                    ? AppColors.primary
                                    : AppColors.textPrimary,
                          ),
                        ),
                        if (dots.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: dots
                                .map((c) => Container(
                                      width: 4,
                                      height: 4,
                                      margin: const EdgeInsets.symmetric(
                                          horizontal: 1),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Colors.white
                                                .withValues(alpha: 0.85)
                                            : c,
                                        shape: BoxShape.circle,
                                      ),
                                    ))
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: const [
        _LegendItem(color: AppColors.statusPending, label: 'Pendente'),
        _LegendItem(color: AppColors.statusInProgress, label: 'Em andamento'),
        _LegendItem(color: AppColors.statusSubmitted, label: 'Enviada'),
        _LegendItem(color: AppColors.statusValidated, label: 'Validada'),
        _LegendItem(color: AppColors.statusOverdue, label: 'Atrasada'),
      ],
    );
  }
}

// ── Legenda ────────────────────────────────────────────────────────────────────

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

// ── Card de tarefa no dia selecionado ──────────────────────────────────────────

class _DayTaskCard extends StatelessWidget {
  final Task task;
  const _DayTaskCard({required this.task});

  Color get _statusColor {
    final now = DateTime.now();
    if (task.dueDate.isBefore(now) &&
        task.status != 'submitted' &&
        task.status != 'validated') {
      return AppColors.statusOverdue;
    }
    switch (task.status) {
      case 'in_progress':
        return AppColors.statusInProgress;
      case 'submitted':
        return AppColors.statusSubmitted;
      case 'validated':
        return AppColors.statusValidated;
      default:
        return AppColors.statusPending;
    }
  }

  String get _statusLabel {
    final now = DateTime.now();
    if (task.dueDate.isBefore(now) &&
        task.status != 'submitted' &&
        task.status != 'validated') {
      return 'Atrasada';
    }
    switch (task.status) {
      case 'pending':
        return 'Pendente';
      case 'in_progress':
        return 'Em andamento';
      case 'submitted':
        return 'Enviada';
      case 'validated':
        return 'Validada';
      default:
        return task.status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _statusColor.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: _statusColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tarefa ${task.displayCode}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.schedule_outlined,
                        size: 12, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      'Prazo: ${AppDateUtils.formatDate(task.dueDate)}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _statusLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
