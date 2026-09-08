import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/task.dart';
import '../../../widgets/status_badge.dart';
import '../../auth/providers/auth_provider.dart';

class CalendarioInstitucionalScreen extends StatefulWidget {
  const CalendarioInstitucionalScreen({super.key});

  @override
  State<CalendarioInstitucionalScreen> createState() =>
      _CalendarioInstitucionalScreenState();
}

class _CalendarioInstitucionalScreenState
    extends State<CalendarioInstitucionalScreen> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  DateTime _focusedMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );
  DateTime? _selectedDay;
  Map<String, List<Task>> _tasksByDay = {};

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

    final firstDay = _focusedMonth;
    final lastDay = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);

    try {
      final data = await _db
          .from('tasks')
          .select('*, checklists(archived_at)')
          .eq('hospital_id', hospitalId)
          .gte('due_date', firstDay.toIso8601String().substring(0, 10))
          .lte('due_date', lastDay.toIso8601String().substring(0, 10));

      final map = <String, List<Task>>{};
      for (final t in data) {
        // Checklist arquivado nao aparece no calendario (bloco 1).
        if ((t['checklists'] as Map<String, dynamic>?)?['archived_at'] !=
            null) {
          continue;
        }
        final task = Task.fromJson(t);
        final key = task.dueDate.toIso8601String().substring(0, 10);
        map.putIfAbsent(key, () => []).add(task);
      }

      if (mounted) {
        setState(() {
          _tasksByDay = map;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _prevMonth() {
    setState(() {
      _focusedMonth =
          DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1);
      _selectedDay = null;
    });
    _load();
  }

  void _nextMonth() {
    setState(() {
      _focusedMonth =
          DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1);
      _selectedDay = null;
    });
    _load();
  }

  /// Cor da barra lateral do card de tarefa (status individual).
  Color _statusColor(Task task) {
    if (task.isOverdue) return AppColors.statusOverdue;
    switch (task.status) {
      case 'validated':
        return AppColors.statusValidated;
      case 'submitted':
        return AppColors.statusSubmitted;
      case 'in_progress':
        return AppColors.statusInProgress;
      default:
        return AppColors.statusPending;
    }
  }

  Color _dayColor(List<Task> tasks) {
    if (tasks.any((t) => t.isOverdue)) return AppColors.statusOverdue;
    if (tasks.any((t) => t.status == 'validated')) return AppColors.statusValidated;
    if (tasks.any((t) => t.status == 'submitted')) return AppColors.statusSubmitted;
    if (tasks.any((t) => t.status == 'in_progress')) return AppColors.statusInProgress;
    return AppColors.statusPending;
  }

  @override
  Widget build(BuildContext context) {
    final monthFmt = DateFormat('MMMM yyyy', 'pt_BR');
    final today = DateTime.now();
    final daysInMonth = DateUtils.getDaysInMonth(
        _focusedMonth.year, _focusedMonth.month);
    final firstWeekday = _focusedMonth.weekday % 7; // 0=Sun, 6=Sat

    final selectedKey =
        _selectedDay?.toIso8601String().substring(0, 10);
    final selectedTasks =
        selectedKey != null ? (_tasksByDay[selectedKey] ?? []) : [];

    return Scaffold(
      appBar: AppBar(title: const Text('Calendário Institucional')),
      body: Column(
        children: [
          // ── Navegação de mês ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            child: Row(
              children: [
                IconButton(
                    onPressed: _prevMonth,
                    icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: Text(
                    monthFmt.format(_focusedMonth),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                    onPressed: _nextMonth,
                    icon: const Icon(Icons.chevron_right)),
              ],
            ),
          ),

          // ── Cabeçalho dias da semana ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb']
                  .map((d) => Expanded(
                        child: Text(
                          d,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),

          // ── Grade do calendário ────────────────────────────────────────
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: 1,
                ),
                itemCount: firstWeekday + daysInMonth,
                itemBuilder: (ctx, idx) {
                  if (idx < firstWeekday) return const SizedBox();
                  final day = idx - firstWeekday + 1;
                  final date = DateTime(
                      _focusedMonth.year, _focusedMonth.month, day);
                  final key = date.toIso8601String().substring(0, 10);
                  final tasks = _tasksByDay[key] ?? [];
                  final isToday = DateUtils.isSameDay(date, today);
                  final isSelected = _selectedDay != null &&
                      DateUtils.isSameDay(date, _selectedDay!);
                  final dotColor =
                      tasks.isNotEmpty ? _dayColor(tasks) : null;

                  return GestureDetector(
                    onTap: () => setState(() => _selectedDay =
                        isSelected ? null : date),
                    child: Container(
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary
                            : isToday
                                ? AppColors.primary.withAlpha(30)
                                : null,
                        borderRadius: BorderRadius.circular(8),
                        border: isToday && !isSelected
                            ? Border.all(
                                color: AppColors.primary, width: 1)
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$day',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : AppColors.textPrimary,
                            ),
                          ),
                          if (dotColor != null)
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.white : dotColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          // ── Legenda ────────────────────────────────────────────────────
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 12,
              children: [
                _Legend(color: AppColors.statusPending, label: 'Pendente'),
                _Legend(
                    color: AppColors.statusInProgress, label: 'Em andamento'),
                _Legend(
                    color: AppColors.statusSubmitted, label: 'Enviado'),
                _Legend(
                    color: AppColors.statusValidated, label: 'Validado'),
                _Legend(color: AppColors.statusOverdue, label: 'Atrasado'),
              ],
            ),
          ),

          const Divider(),

          // ── Tarefas do dia selecionado ─────────────────────────────────
          Expanded(
            child: selectedTasks.isEmpty
                ? Center(
                    child: Text(
                      _selectedDay == null
                          ? 'Toque em um dia para ver as tarefas.'
                          : 'Sem tarefas neste dia.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(
                        AppDimensions.screenPadding),
                    itemCount: selectedTasks.length,
                    itemBuilder: (ctx, i) {
                      final task = selectedTasks[i];
                      return Card(
                        child: ListTile(
                          leading: Container(
                            width: 4,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _statusColor(task),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          title: Text('Tarefa ${task.displayCode}',
                              style:
                                  Theme.of(context).textTheme.titleMedium),
                          subtitle: StatusBadge(
                            status: task.isOverdue ? 'overdue' : task.status,
                            compact: true,
                          ),
                          trailing: task.status == 'submitted' ||
                                  task.status == 'validated'
                              ? IconButton(
                                  icon: const Icon(Icons.open_in_new,
                                      color: AppColors.primary),
                                  onPressed: () async {
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
                                  },
                                )
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;

  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
