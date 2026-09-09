import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/checklist.dart';
import '../../../core/models/profile.dart';
import '../../../core/models/task.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/skeleton_loader.dart';
import '../../../widgets/status_badge.dart';

/// Detalhes de UMA tarefa, somente leitura — para Supervisor e Diretor.
///
/// Item 2 (revisão): na aba Tarefas do setor, tocar numa tarefa levava
/// Supervisor e Diretor para a tela de RESPOSTA do checklist — que é do
/// Inspetor, e dá "erro ao responder checklist" porque a política do banco
/// só deixa quem é inspector_id daquela tarefa gravar em
/// inspection_responses (regra 6.7). O mesmo defeito existia tanto na
/// tarefa avulsa quanto numa ocorrência de série.
///
/// Esta tela substitui esse destino: mostra checklist, inspetor, quem
/// atribuiu, prazo, posição na série, situação, e — quando já houver
/// envio — o relatório, com atalho para abri-lo. Nenhuma ação de
/// responder.
class TarefaDetalhesScreen extends StatefulWidget {
  final String taskId;

  const TarefaDetalhesScreen({super.key, required this.taskId});

  @override
  State<TarefaDetalhesScreen> createState() => _TarefaDetalhesScreenState();
}

class _TarefaDetalhesScreenState extends State<TarefaDetalhesScreen> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  String? _erro;

  Task? _task;
  Checklist? _checklist;
  String _sectorName = '—';
  Profile? _inspector;
  Profile? _assignedBy;
  String? _inspectionId;
  String? _inspectionStatus;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _erro = null;
    });

    try {
      final taskData = await _db
          .from('tasks')
          .select()
          .eq('id', widget.taskId)
          .single();
      final task = Task.fromJson(taskData);

      final clData = await _db
          .from('checklists')
          .select()
          .eq('id', task.checklistId)
          .maybeSingle();
      final checklist =
          clData != null ? Checklist.fromJson(clData) : null;

      final sectorData = await _db
          .from('sectors')
          .select('name')
          .eq('id', task.sectorId)
          .maybeSingle();

      final peopleIds = {task.inspectorId, task.assignedBy}.toList();
      final peopleData =
          await _db.from('profiles').select().inFilter('id', peopleIds);
      final peopleMap = <String, Profile>{
        for (final p in peopleData) Profile.fromJson(p).id:
            Profile.fromJson(p),
      };

      // Relatório: existe quando já houve envio (submitted/validated).
      String? inspectionId;
      if (task.status == 'submitted' || task.status == 'validated') {
        final insp = await _db
            .from('inspections')
            .select('id, overall_status')
            .eq('task_id', task.id)
            .order('created_at', ascending: false)
            .limit(1);
        if (insp.isNotEmpty) {
          inspectionId = insp.first['id'] as String;
          _inspectionStatus = insp.first['overall_status'] as String?;
        }
      }

      if (!mounted) return;
      setState(() {
        _task = task;
        _checklist = checklist;
        _sectorName = sectorData?['name'] as String? ?? '—';
        _inspector = peopleMap[task.inspectorId];
        _assignedBy = peopleMap[task.assignedBy];
        _inspectionId = inspectionId;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[TarefaDetalhes] carregar: $e');
      if (mounted) {
        setState(() {
          _erro = 'Não foi possível carregar a tarefa. Tente novamente.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalhes da tarefa')),
      body: _loading
          ? const SkeletonList(itemHeight: 72)
          : _erro != null
              ? EmptyState(
                  icon: Icons.error_outline,
                  title: 'Erro ao carregar',
                  subtitle: _erro!,
                  actionLabel: 'Tentar novamente',
                  onAction: _load,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _cabecalho(),
                      const SizedBox(height: 16),
                      _secaoInfo(),
                      const SizedBox(height: 16),
                      if (_inspectionId != null) _secaoRelatorio(),
                    ],
                  ),
                ),
    );
  }

  Widget _cabecalho() {
    final task = _task!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _checklist?.title ?? 'Checklist removido',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                StatusBadge(
                  status: task.isOverdue ? 'overdue' : task.status,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              task.displayCode,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              _sectorName,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _secaoInfo() {
    final task = _task!;
    final ehSerie = task.seriesId != null && (task.seriesTotal ?? 1) > 1;

    return Card(
      child: Column(
        children: [
          _linha(
            icone: Icons.person_outline,
            rotulo: 'Inspetor responsável',
            valor: _inspector?.fullName ?? '—',
          ),
          const Divider(height: 1),
          _linha(
            icone: Icons.assignment_ind_outlined,
            rotulo: 'Atribuída por',
            valor: _assignedBy?.fullName ?? '—',
          ),
          const Divider(height: 1),
          _linha(
            icone: Icons.event_available_outlined,
            rotulo: 'Data de atribuição',
            valor: AppDateUtils.formatDate(task.createdAt),
          ),
          const Divider(height: 1),
          _linha(
            icone: Icons.event_outlined,
            rotulo: 'Prazo',
            valor: AppDateUtils.formatDate(task.dueDate),
            destaque: task.isOverdue,
          ),
          if (ehSerie) ...[
            const Divider(height: 1),
            _linha(
              icone: Icons.repeat,
              rotulo: 'Posição na série',
              valor: '${task.seriesIndex ?? '—'} de ${task.seriesTotal}',
            ),
          ],
          const Divider(height: 1),
          _linha(
            icone: Icons.flag_outlined,
            rotulo: 'Situação atual',
            valor: _situacaoLabel(task),
          ),
        ],
      ),
    );
  }

  String _situacaoLabel(Task task) {
    if (task.isOverdue) return 'Atrasada';
    switch (task.status) {
      case 'pending':
        return 'Pendente';
      case 'in_progress':
        return 'Em andamento';
      case 'submitted':
        return 'Enviada';
      case 'validated':
        return 'Validada';
      case 'cancelled':
        return 'Cancelada';
      default:
        return task.status;
    }
  }

  Widget _linha({
    required IconData icone,
    required String rotulo,
    required String valor,
    bool destaque = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icone, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              rotulo,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Text(
            valor,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color:
                      destaque ? AppColors.nonCompliant : AppColors.textPrimary,
                ),
          ),
        ],
      ),
    );
  }

  Widget _secaoRelatorio() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.description_outlined,
            color: AppColors.primary),
        title: const Text('Relatório desta inspeção'),
        subtitle: Text(
          _inspectionStatus == 'validated'
              ? 'Validado'
              : 'Enviado, aguardando validação',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () =>
            context.push(AppRoutes.relatorioIndividual(_inspectionId!)),
      ),
    );
  }
}
