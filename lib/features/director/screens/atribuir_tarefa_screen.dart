import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/checklist.dart';
import '../../../core/models/profile.dart';
import '../../../core/models/sector.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/utils/task_series_utils.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../widgets/app_filter_chip.dart';

class AtribuirTarefaScreen extends StatefulWidget {
  /// Setor pré-selecionado — usado quando a tela é aberta a partir da aba
  /// "Tarefas" de um setor. Sendo informado, o campo de setor NÃO aparece:
  /// a navegação já definiu o setor e repetir a escolha só permitia sair do
  /// contexto por engano.
  final String? initialSectorId;

  const AtribuirTarefaScreen({super.key, this.initialSectorId});

  @override
  State<AtribuirTarefaScreen> createState() => _AtribuirTarefaScreenState();
}

class _AtribuirTarefaScreenState extends State<AtribuirTarefaScreen> {
  final _db = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();

  bool _loading = false;
  bool _loadingData = true;

  List<Sector> _setores = [];
  List<Checklist> _checklists = [];
  List<Profile> _inspetores = [];

  Sector? _setorSel;
  Checklist? _checklistSel;
  final Set<String> _inspetoresSel = {};

  // ── Recorrência ─────────────────────────────────────────────────────────
  /// false = tarefa única (comportamento de sempre), true = série.
  bool _recorrente = false;
  DateTime? _prazo; // tarefa única
  DateTime? _inicio; // série
  DateTime? _fim; // série
  String _frequencia = 'weekly';

  /// A primeira ocorrência cai na data inicial (padrão) ou pula para a
  /// próxima data da frequência. Começar hoje é o comportamento esperado
  /// na maioria dos casos, então é o padrão.
  bool _comecarHoje = true;
  final Set<String> _diasPersonalizados = {};

  String? _hospitalId;

  /// O setor veio da navegação? Então não se escolhe setor aqui.
  bool get _setorFixo => widget.initialSectorId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadingData = true);
    final profile = context.read<AuthProvider>().profile;
    _hospitalId = profile?.hospitalId;
    if (_hospitalId == null) {
      if (mounted) setState(() => _loadingData = false);
      return;
    }

    try {
      // Com setor fixo, basta o setor do contexto — não a lista inteira.
      final setoresQuery = _db
          .from('sectors')
          .select()
          .eq('hospital_id', _hospitalId!)
          .eq('status', 'active');

      final setoresData = _setorFixo
          ? await setoresQuery.eq('id', widget.initialSectorId!)
          : await setoresQuery.order('name', ascending: true);

      if (!mounted) return;
      setState(() {
        _setores = setoresData.map(Sector.fromJson).toList();
        _loadingData = false;
      });

      if (_setorFixo && _setores.isNotEmpty) {
        await _onSetorChanged(_setores.first);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  Future<void> _onSetorChanged(Sector? setor) async {
    setState(() {
      _setorSel = setor;
      _checklistSel = null;
      _checklists = [];
      _inspetores = [];
      _inspetoresSel.clear();
    });
    if (setor == null) return;

    try {
      final clData = await _db
          .from('checklists')
          .select()
          .eq('sector_id', setor.id)
          .eq('status', 'active')
          .order('title', ascending: true);

      // Inspetores vinculados ao setor via inspector_sectors
      final inspLinks = await _db
          .from('inspector_sectors')
          .select('inspector_id')
          .eq('sector_id', setor.id)
          .eq('status', 'active');

      List<Profile> insp = [];
      if (inspLinks.isNotEmpty) {
        final ids = inspLinks.map((e) => e['inspector_id'] as String).toList();
        final inspData = await _db
            .from('profiles')
            .select()
            .inFilter('id', ids)
            .eq('status', 'active');
        insp = inspData.map(Profile.fromJson).toList();
      }

      if (mounted) {
        setState(() {
          // Arquivado não gera tarefa nova (bloco 1).
          _checklists = clData
              .map(Checklist.fromJson)
              // Excluido nao recebe tarefa nova.
              .where((c) => !c.isDeleted)
              .toList();
          _inspetores = insp;
        });
      }
    } catch (_) {}
  }

  /// Datas que serão criadas com a configuração atual.
  List<DateTime> get _datasPrevistas {
    if (!_recorrente) return _prazo != null ? [_prazo!] : const [];
    if (_inicio == null || _fim == null) return const [];
    final todas = TaskSeriesUtils.gerarDatas(
      inicio: _inicio!,
      fim: _fim!,
      frequencia: _frequencia,
      customDays: _diasPersonalizados.toList(),
    );
    // "Próxima data": descarta a primeira ocorrência, que é a data inicial.
    if (!_comecarHoje && todas.length > 1) return todas.sublist(1);
    return todas;
  }

  bool get _excedeuLimite {
    if (!_recorrente || _inicio == null || _fim == null) return false;
    return TaskSeriesUtils.excedeuLimite(
      inicio: _inicio!,
      fim: _fim!,
      frequencia: _frequencia,
      customDays: _diasPersonalizados.toList(),
    );
  }

  Future<void> _atribuir() async {
    if (!_formKey.currentState!.validate()) return;
    if (_setorSel == null) {
      _showSnack('Setor não identificado.', error: true);
      return;
    }
    if (_checklistSel == null) {
      _showSnack('Selecione um checklist.', error: true);
      return;
    }
    if (_inspetoresSel.isEmpty) {
      _showSnack('Selecione ao menos um Inspetor.', error: true);
      return;
    }

    final datas = _datasPrevistas;
    if (datas.isEmpty) {
      _showSnack(
        _recorrente
            ? 'Nenhuma data no período escolhido. Revise as datas e a frequência.'
            : 'Defina o prazo.',
        error: true,
      );
      return;
    }

    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    final profile = auth.profile!;

    try {
      // Uma série por Inspetor: cada um tem a própria sequência "1 de N".
      final linhas = <Map<String, dynamic>>[];
      for (final inspId in _inspetoresSel) {
        final seriesId = _recorrente ? _uuid.v4() : null;
        for (var i = 0; i < datas.length; i++) {
          linhas.add({
            'checklist_id': _checklistSel!.id,
            'sector_id': _setorSel!.id,
            'hospital_id': _hospitalId,
            'inspector_id': inspId,
            'assigned_by': profile.id,
            'due_date': datas[i].toIso8601String().substring(0, 10),
            'status': 'pending',
            if (seriesId != null) ...{
              'series_id': seriesId,
              'series_index': i + 1,
              'series_total': datas.length,
            },
          });
        }
      }

      final results = await _db.from('tasks').insert(linhas).select('id');

      // audit_log: uma entrada por série (ou por tarefa avulsa). Registrar
      // 60 linhas idênticas por Inspetor só polui a trilha.
      if (_recorrente) {
        await AuditService.log(
          userId: profile.id,
          hospitalId: _hospitalId,
          action: 'atribuir_serie_tarefas',
          entityType: 'task',
          entityId: (results.first)['id'] as String,
          details: {
            'checklist_id': _checklistSel!.id,
            'checklist_title': _checklistSel!.title,
            'sector_id': _setorSel!.id,
            'frequencia': _frequencia,
            'ocorrencias': datas.length,
            'inspetores': _inspetoresSel.length,
            'inicio': datas.first.toIso8601String().substring(0, 10),
            'fim': datas.last.toIso8601String().substring(0, 10),
          },
        );
      } else {
        for (final r in results) {
          await AuditService.log(
            userId: profile.id,
            hospitalId: _hospitalId,
            action: 'atribuir_tarefa',
            entityType: 'task',
            entityId: r['id'] as String,
            details: {
              'checklist_id': _checklistSel!.id,
              'checklist_title': _checklistSel!.title,
              'sector_id': _setorSel!.id,
              'due_date': datas.first.toIso8601String().substring(0, 10),
            },
          );
        }
      }

      if (mounted) {
        _showSnack(_recorrente
            ? '${linhas.length} tarefa(s) criada(s): '
                '${datas.length} datas × ${_inspetoresSel.length} Inspetor(es).'
            : '${_inspetoresSel.length} tarefa(s) atribuída(s) com sucesso.');
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('[AtribuirTarefa] erro: $e');
      if (mounted) {
        // Coluna inexistente = migration de série não executada.
        // Coluna inexistente indica migration pendente. O usuário não
        // tem o que fazer com o nome do arquivo .sql — isso vai para o
        // log; a tela diz o que ele PODE fazer (D2).
        final semSerie = e.toString().contains('series_id');
        if (semSerie) {
          debugPrint('[AtribuirTarefa] migration_task_series.sql pendente');
        }
        _showSnack(
          semSerie
              ? 'Tarefa recorrente indisponível no momento. Atribua uma '
                  'tarefa avulsa ou procure o administrador.'
              : 'Não foi possível atribuir as tarefas. Tente novamente.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.nonCompliant : AppColors.compliant,
    ));
  }

  Future<void> _pickData({
    required DateTime? atual,
    required DateTime primeiro,
    required ValueChanged<DateTime> onPick,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: atual ?? primeiro,
      firstDate: primeiro,
      lastDate: DateTime(2030),
    );
    if (picked != null && mounted) onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingData) {
      return Scaffold(
          appBar: AppBar(title: const Text('Atribuir Tarefa')),
          body: const Center(child: CircularProgressIndicator()));
    }

    final fmt = DateFormat('dd/MM/yyyy', 'pt_BR');
    final amanha = DateTime.now().add(const Duration(days: 1));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Atribuir Tarefa'),
        // Setor vindo da navegação vira subtítulo, não campo editável.
        bottom: _setorFixo && _setorSel != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.domain_outlined,
                            size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 5),
                        Text(
                          _setorSel!.name,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : null,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppDimensions.screenPadding),
          children: [
            // Campo de setor SÓ quando a navegação não definiu o setor.
            if (!_setorFixo) ...[
              DropdownButtonFormField<Sector>(
                key: ValueKey(_setorSel),
                decoration: const InputDecoration(labelText: 'Setor *'),
                initialValue: _setorSel,
                items: _setores
                    .map((s) => DropdownMenuItem(value: s, child: Text(s.name)))
                    .toList(),
                onChanged: _onSetorChanged,
                validator: (v) => v == null ? 'Selecione um setor' : null,
              ),
              const SizedBox(height: 16),
            ],

            if (_setorSel != null) ...[
              DropdownButtonFormField<Checklist>(
                key: ValueKey(_checklistSel),
                decoration: const InputDecoration(labelText: 'Checklist *'),
                initialValue: _checklistSel,
                items: _checklists
                    // Só o título: a frequência do checklist saiu da
                    // interface — quem define frequência é esta tela.
                    .map((c) => DropdownMenuItem(
                        value: c, child: Text(c.title)))
                    .toList(),
                onChanged: (v) => setState(() => _checklistSel = v),
                validator: (v) => v == null ? 'Selecione um checklist' : null,
              ),
              const SizedBox(height: 16),

              // Seleção de Inspetores
              Text('Inspetores *',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              if (_inspetores.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius:
                        BorderRadius.circular(AppDimensions.radiusCard),
                  ),
                  child: const Text(
                    'Nenhum Inspetor vinculado a este setor.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              else
                ...(_inspetores.map((insp) => CheckboxListTile(
                      title: Text(insp.fullName),
                      subtitle: Text(insp.email),
                      value: _inspetoresSel.contains(insp.id),
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _inspetoresSel.add(insp.id);
                          } else {
                            _inspetoresSel.remove(insp.id);
                          }
                        });
                      },
                    ))),
              const SizedBox(height: 8),

              // ── Repetir ────────────────────────────────────────────────
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Repetir'),
                subtitle: Text(
                  _recorrente
                      ? 'Uma tarefa é criada para cada data do período.'
                      : 'Uma tarefa única, com um só prazo.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                value: _recorrente,
                onChanged: (v) => setState(() => _recorrente = v),
              ),
              const SizedBox(height: 8),

              if (!_recorrente)
                InkWell(
                  onTap: () => _pickData(
                    atual: _prazo,
                    primeiro: DateTime.now(),
                    onPick: (d) => setState(() => _prazo = d),
                  ),
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Prazo *'),
                    child: Text(
                      _prazo != null ? fmt.format(_prazo!) : 'Selecionar data',
                      style: TextStyle(
                        color: _prazo != null
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _pickData(
                          atual: _inicio,
                          primeiro: DateTime.now(),
                          onPick: (d) => setState(() {
                            _inicio = d;
                            if (_fim != null && _fim!.isBefore(d)) _fim = null;
                          }),
                        ),
                        child: InputDecorator(
                          decoration:
                              const InputDecoration(labelText: 'Início *'),
                          child: Text(
                            _inicio != null
                                ? fmt.format(_inicio!)
                                : 'Selecionar',
                            style: TextStyle(
                              color: _inicio != null
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () => _pickData(
                          atual: _fim,
                          primeiro: _inicio ?? amanha,
                          onPick: (d) => setState(() => _fim = d),
                        ),
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Fim *'),
                          child: Text(
                            _fim != null ? fmt.format(_fim!) : 'Selecionar',
                            style: TextStyle(
                              color: _fim != null
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  decoration:
                      const InputDecoration(labelText: 'Frequência *'),
                  initialValue: _frequencia,
                  items: AppConstants.checklistFrequencies
                      .map((f) => DropdownMenuItem(
                          value: f['value']!, child: Text(f['label']!)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _frequencia = v ?? 'weekly'),
                ),

                const SizedBox(height: 14),
                // A decisão real do Diretor aqui é se o Inspetor consegue
                // responder ainda hoje.
                Text('Primeira ocorrência',
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 6),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Hoje')),
                    ButtonSegment(
                      value: false,
                      label: Text('Na próxima data da frequência'),
                    ),
                  ],
                  selected: {_comecarHoje},
                  showSelectedIcon: false,
                  onSelectionChanged: (sel) =>
                      setState(() => _comecarHoje = sel.first),
                ),
                const SizedBox(height: 6),
                Text(
                  _comecarHoje
                      ? 'A tarefa aparece imediatamente para o Inspetor.'
                      : 'A primeira tarefa só aparece na próxima data da '
                          'frequência escolhida.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),

                if (_frequencia == 'custom') ...[
                  const SizedBox(height: 12),
                  Text('Dias da semana *',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: AppConstants.weekDays.map((d) {
                      final v = d['value']!;
                      final sel = _diasPersonalizados.contains(v);
                      return AppFilterChip(
                        label: d['label']!,
                        selected: sel,
                        onSelected: (on) => setState(() {
                          if (on) {
                            _diasPersonalizados.add(v);
                          } else {
                            _diasPersonalizados.remove(v);
                          }
                        }),
                      );
                    }).toList(),
                  ),
                ],

                const SizedBox(height: 14),
                _buildPreviaSerie(fmt),
              ],

              const SizedBox(height: 28),

              SizedBox(
                height: AppDimensions.buttonHeight,
                child: ElevatedButton(
                  onPressed: _loading ? null : _atribuir,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(_recorrente
                          ? 'Criar ${_datasPrevistas.length} tarefa(s)'
                          : 'Atribuir Tarefa(s)'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Prévia da série: quantas datas, primeira e última, e o aviso de corte.
  Widget _buildPreviaSerie(DateFormat fmt) {
    final datas = _datasPrevistas;

    if (datas.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
        ),
        child: Text(
          _frequencia == 'custom' && _diasPersonalizados.isEmpty
              ? 'Selecione ao menos um dia da semana.'
              : 'Informe início e fim para ver as datas geradas.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary50,
        borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
        border: Border.all(color: AppColors.primary100, width: 0.5),
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
                '${datas.length} ocorrência(s) por Inspetor',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.primary, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'De ${fmt.format(datas.first)} até ${fmt.format(datas.last)}.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_inspetoresSel.length > 1)
            Text(
              'Total: ${datas.length * _inspetoresSel.length} tarefas '
              '(${_inspetoresSel.length} Inspetores).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (_excedeuLimite) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 15, color: AppColors.pending),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'O período gera mais de ${TaskSeriesUtils.maxOcorrencias} '
                    'ocorrências. Serão criadas as '
                    '${TaskSeriesUtils.maxOcorrencias} primeiras. Para incluir '
                    'todas, encurte o período ou espace a frequência.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.pending),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
