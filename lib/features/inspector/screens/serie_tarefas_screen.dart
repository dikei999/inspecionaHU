import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/data_source.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/task.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/skeleton_loader.dart';

/// Ocorrências de uma série recorrente.
///
/// No painel a série é UM card; aqui ela se abre, com o status individual de
/// cada ocorrência. É desta tela que o Inspetor responde.
class SerieTarefasScreen extends StatefulWidget {
  final String seriesId;

  const SerieTarefasScreen({super.key, required this.seriesId});

  @override
  State<SerieTarefasScreen> createState() => _SerieTarefasScreenState();
}

class _SerieTarefasScreenState extends State<SerieTarefasScreen> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  List<Task> _tasks = [];
  String _checklistTitle = 'Checklist';
  String _sectorName = '—';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    // Offline: as ocorrências saem dos pacotes baixados.
    if (DataSource.estaOffline) {
      final locais = await DataSource.serieLocal(widget.seriesId);
      if (!mounted) return;
      setState(() {
        _tasks = locais.map((t) => t.task).toList()
          ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
        if (locais.isNotEmpty) {
          _checklistTitle = locais.first.checklistTitle;
          _sectorName = locais.first.sectorName;
        }
        _loading = false;
      });
      return;
    }

    try {
      final rows = await _db
          .from('tasks')
          .select('*, checklists(title), sectors(name)')
          .eq('series_id', widget.seriesId)
          .neq('status', 'cancelled')
          .order('due_date', ascending: true);

      final lista = (rows as List).cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() {
          _tasks = lista.map(Task.fromJson).toList();
          if (lista.isNotEmpty) {
            _checklistTitle =
                (lista.first['checklists'] as Map?)?['title'] as String? ??
                    'Checklist';
            _sectorName =
                (lista.first['sectors'] as Map?)?['name'] as String? ?? '—';
          }
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[SerieTarefas] erro: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _concluidas => _tasks.where((t) => t.isRespondida).length;

  /// Rótulo e cor da situação de cada ocorrência.
  (String, Color, IconData) _situacao(Task t) {
    if (t.isRespondida) {
      return ('Concluída', AppColors.statusValidated, Icons.check_circle);
    }
    if (t.isOverdue) {
      return ('Atrasada', AppColors.statusOverdue, Icons.warning_amber_rounded);
    }
    if (t.isPendenteHoje) {
      return ('Pendente hoje', AppColors.pending, Icons.today_outlined);
    }
    return ('Agendada', AppColors.textSecondary, Icons.event_outlined);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Série de tarefas'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '$_checklistTitle · $_sectorName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const SkeletonList(itemHeight: 76)
          : _tasks.isEmpty
              ? EmptyState(
                  icon: DataSource.estaOffline
                      ? Icons.cloud_off_outlined
                      : Icons.event_repeat_outlined,
                  title: DataSource.estaOffline
                      ? 'Nenhuma ocorrência baixada'
                      : 'Série sem ocorrências',
                  subtitle: DataSource.estaOffline
                      ? 'Sem conexão, aparecem apenas as ocorrências '
                          'baixadas desta série.'
                      : 'As ocorrências desta série foram canceladas ou não '
                          'existem mais.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(
                        AppDimensions.screenPadding),
                    children: [
                      // Progresso da série inteira.
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.primary50,
                          borderRadius: BorderRadius.circular(
                              AppDimensions.radiusCard),
                          border: Border.all(
                              color: AppColors.primary100, width: 0.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.event_repeat_outlined,
                                    size: 16, color: AppColors.primary),
                                const SizedBox(width: 6),
                                Text(
                                  '$_concluidas de ${_tasks.length} '
                                  'concluída(s)',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: _tasks.isEmpty
                                    ? 0
                                    : _concluidas / _tasks.length,
                                minHeight: 6,
                                backgroundColor: AppColors.primary100,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      ..._tasks.map((t) {
                        final (rotulo, cor, icone) = _situacao(t);
                        // Agendada não abre: responder antes da data é o
                        // que gerava a sensação de dívida antecipada.
                        final podeResponder = !t.isAgendada && !t.isRespondida;

                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: cor.withValues(alpha: 0.12),
                              child: Icon(icone, size: 18, color: cor),
                            ),
                            title: Text(
                              'Ocorrência ${t.seriesIndex ?? '—'} '
                              'de ${t.seriesTotal ?? _tasks.length}',
                            ),
                            subtitle: Text(
                              '${AppDateUtils.formatDate(t.dueDate)} · $rotulo',
                              style: TextStyle(color: cor),
                            ),
                            trailing: podeResponder
                                ? const Icon(Icons.chevron_right)
                                : null,
                            enabled: podeResponder,
                            onTap: podeResponder
                                ? () async {
                                    await context.push(
                                        AppRoutes.responderChecklist(t.id));
                                    _load();
                                  }
                                : null,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
    );
  }
}
