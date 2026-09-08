import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/archive_service.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/sector.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../widgets/charts.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/skeleton_loader.dart';
import '../../../widgets/stat_card.dart';
import '../../../widgets/status_badge.dart';
import '../../auth/providers/auth_provider.dart';

/// Relatórios & Análises — um dos 4 cards principais do dashboard.
/// Diretor vê o hospital inteiro; Supervisor vê apenas os setores dos quais
/// é owner ou onde tem sector_access.
class RelatoriosAnalisesScreen extends StatefulWidget {
  const RelatoriosAnalisesScreen({super.key});

  @override
  State<RelatoriosAnalisesScreen> createState() =>
      _RelatoriosAnalisesScreenState();
}

class _RelatoriosAnalisesScreenState extends State<RelatoriosAnalisesScreen> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  bool _isSupervisor = false;

  double _conformidade = 0;
  int _totalCompliant = 0;
  int _totalNonCompliant = 0;
  int _totalNotApplicable = 0;
  int _totalInspecoes = 0;
  int _ncsAbertas = 0;

  List<_RecentInspection> _recentes = [];

  // ── Filtros da lista de relatórios (bloco 3) ────────────────────────────
  List<Sector> _setoresDisponiveis = [];
  String? _filtroSetorId;
  String? _filtroStatus;
  String _busca = '';
  final _buscaCtrl = TextEditingController();

  /// Filtro "Arquivados": false = relatórios ativos (padrão), true = só os
  /// arquivados. Arquivado é reversível e não sai do banco.
  bool _verArquivados = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  /// Relatórios após setor + status + busca por nome (bloco 3).
  List<_RecentInspection> get _relatoriosFiltrados {
    final q = _busca.trim().toLowerCase();
    return _recentes.where((r) {
      if (_filtroSetorId != null && r.sectorId != _filtroSetorId) return false;
      if (_filtroStatus != null && r.status != _filtroStatus) return false;
      if (q.isEmpty) return true;
      return r.sectorName.toLowerCase().contains(q) ||
          r.checklistTitle.toLowerCase().contains(q);
    }).toList();
  }

  /// Agrupa por dia, preservando a ordem (mais recente primeiro).
  /// Sem isso a aba é uma coluna longa sem ponto de referência.
  List<MapEntry<DateTime, List<_RecentInspection>>> get _agrupadosPorData {
    final grupos = <DateTime, List<_RecentInspection>>{};
    for (final r in _relatoriosFiltrados) {
      final d = r.submittedAt;
      final chave = d == null
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime(d.year, d.month, d.day);
      grupos.putIfAbsent(chave, () => []).add(r);
    }
    final entradas = grupos.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return entradas;
  }

  /// Cabeçalho de seção: Hoje / Ontem / data por extenso.
  String _rotuloData(DateTime d) {
    if (d.millisecondsSinceEpoch == 0) return 'Sem data de envio';
    final hoje = DateTime.now();
    final dHoje = DateTime(hoje.year, hoje.month, hoje.day);
    final diff = dHoje.difference(d).inDays;
    if (diff == 0) return 'Hoje';
    if (diff == 1) return 'Ontem';
    return AppDateUtils.formatDate(d);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = context.read<AuthProvider>().profile;
    if (profile?.hospitalId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final hospitalId = profile!.hospitalId!;
    _isSupervisor = profile.role == 'supervisor';

    try {
      // Supervisor: restringe aos setores que ele gerencia.
      List<String>? sectorIds;
      if (_isSupervisor) {
        sectorIds = await _sectorIdsDoSupervisor(hospitalId, profile.id);
        if (sectorIds.isEmpty) {
          if (mounted) {
            setState(() {
              _conformidade = 0;
              _totalCompliant = 0;
              _totalNonCompliant = 0;
              _totalNotApplicable = 0;
              _totalInspecoes = 0;
              _ncsAbertas = 0;
              _recentes = [];
              _loading = false;
            });
          }
          return;
        }
      }

      // Relatórios arquivados ficam FORA de todo indicador e só aparecem
      // no filtro "Arquivados" da lista abaixo.
      final archivedInspections = await ArchiveService.archivedInspectionIds(
          hospitalId,
          sectorIds: sectorIds);

      // ── Conformidade agregada (tabela reports = cache calculado) ───────
      var reportsQuery = _db
          .from('reports')
          .select('compliance_rate, compliant, non_compliant, not_applicable, '
              'inspection_id')
          .eq('hospital_id', hospitalId);
      if (sectorIds != null) {
        reportsQuery = reportsQuery.inFilter('sector_id', sectorIds);
      }
      if (archivedInspections.isNotEmpty) {
        reportsQuery =
            reportsQuery.not('inspection_id', 'in', archivedInspections);
      }
      final reports = await reportsQuery;

      double conf = 0;
      int sumC = 0, sumNc = 0, sumNa = 0;
      if (reports.isNotEmpty) {
        final sum = reports.fold<double>(
            0, (acc, r) => acc + (r['compliance_rate'] as num).toDouble());
        conf = sum / reports.length;
        for (final r in reports) {
          sumC += (r['compliant'] as num? ?? 0).toInt();
          sumNc += (r['non_compliant'] as num? ?? 0).toInt();
          sumNa += (r['not_applicable'] as num? ?? 0).toInt();
        }
      }

      // ── NCs em inspeções ainda não validadas ──────────────────────────
      var openQuery = _db
          .from('inspections')
          .select('id')
          .eq('hospital_id', hospitalId)
          .neq('overall_status', 'validated');
      if (sectorIds != null) {
        openQuery = openQuery.inFilter('sector_id', sectorIds);
      }
      if (archivedInspections.isNotEmpty) {
        openQuery = openQuery.not('id', 'in', archivedInspections);
      }
      final openInspections = await openQuery;

      int ncCount = 0;
      if (openInspections.isNotEmpty) {
        final ids = openInspections.map((e) => e['id'] as String).toList();
        final ncs = await _db
            .from('inspection_responses')
            .select('id')
            .inFilter('inspection_id', ids)
            .eq('status', 'NC');
        ncCount = ncs.length;
      }

      // ── Inspeções concluídas mais recentes ────────────────────────────
      var recentQuery = _db
          .from('inspections')
          .select('id, sector_id, checklist_id, submitted_at, '
              'overall_status, archived_at')
          .eq('hospital_id', hospitalId)
          .inFilter('overall_status', ['submitted', 'validated']);
      if (sectorIds != null) {
        recentQuery = recentQuery.inFilter('sector_id', sectorIds);
      }
      // A lista respeita o filtro: por padrão esconde os arquivados;
      // em "Arquivados", mostra SÓ eles.
      if (_verArquivados) {
        recentQuery = recentQuery.not('archived_at', 'is', null);
      } else {
        recentQuery = recentQuery.isFilter('archived_at', null);
      }
      final recentRows =
          await recentQuery.order('submitted_at', ascending: false).limit(100);

      final recentList = (recentRows as List).cast<Map<String, dynamic>>();
      final recentSectorIds =
          recentList.map((e) => e['sector_id'] as String).toSet().toList();

      final sectorMap = <String, Sector>{};
      if (recentSectorIds.isNotEmpty) {
        final rows =
            await _db.from('sectors').select().inFilter('id', recentSectorIds);
        for (final r in rows) {
          final s = Sector.fromJson(r);
          sectorMap[s.id] = s;
        }
      }

      // ── Métricas por relatório (bloco 3) ──────────────────────────────
      // Cada card mostra taxa de conformidade, nº de NCs e se tem foto.
      final recentIds = recentList.map((e) => e['id'] as String).toList();
      final metricas = <String, _ReportMetrics>{};
      if (recentIds.isNotEmpty) {
        final reportRows = await _db
            .from('reports')
            .select('inspection_id, compliance_rate, non_compliant')
            .inFilter('inspection_id', recentIds);
        for (final r in reportRows) {
          metricas[r['inspection_id'] as String] = _ReportMetrics(
            complianceRate: (r['compliance_rate'] as num?)?.toDouble(),
            nonCompliant: (r['non_compliant'] as num? ?? 0).toInt(),
          );
        }

        // Fotos: uma única varredura, só a coluna necessária.
        final fotoRows = await _db
            .from('inspection_responses')
            .select('inspection_id, photo_url')
            .inFilter('inspection_id', recentIds)
            .not('photo_url', 'is', null);
        for (final f in fotoRows) {
          final id = f['inspection_id'] as String;
          final atual = metricas[id];
          metricas[id] = _ReportMetrics(
            complianceRate: atual?.complianceRate,
            nonCompliant: atual?.nonCompliant ?? 0,
            temFoto: true,
          );
        }
      }

      // Títulos de checklist: usados pela busca por nome.
      final checklistIds = recentList
          .map((e) => e['checklist_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final checklistTitulos = <String, String>{};
      if (checklistIds.isNotEmpty) {
        final rows = await _db
            .from('checklists')
            .select('id, title')
            .inFilter('id', checklistIds);
        for (final c in rows) {
          checklistTitulos[c['id'] as String] = c['title'] as String;
        }
      }

      if (mounted) {
        setState(() {
          _conformidade = conf;
          _totalCompliant = sumC;
          _totalNonCompliant = sumNc;
          _totalNotApplicable = sumNa;
          _totalInspecoes = reports.length;
          _ncsAbertas = ncCount;
          _recentes = recentList.map((e) {
            final id = e['id'] as String;
            final m = metricas[id];
            return _RecentInspection(
              id: id,
              status: e['overall_status'] as String,
              sectorId: e['sector_id'] as String,
              sectorName: sectorMap[e['sector_id']]?.name ?? '—',
              checklistTitle:
                  checklistTitulos[e['checklist_id'] as String?] ?? 'Checklist',
              submittedAt: AppDateUtils.parseDate(e['submitted_at'] as String?),
              complianceRate: m?.complianceRate,
              nonCompliant: m?.nonCompliant ?? 0,
              temFoto: m?.temFoto ?? false,
              arquivado: e['archived_at'] != null,
            );
          }).toList();
          _setoresDisponiveis = sectorMap.values.toList()
            ..sort((a, b) => a.name.compareTo(b.name));
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[RelatoriosAnalises] erro: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Setores visíveis ao Supervisor: onde é owner + onde tem sector_access.
  Future<List<String>> _sectorIdsDoSupervisor(
      String hospitalId, String supervisorId) async {
    final ids = <String>{};

    final owned = await _db
        .from('sectors')
        .select('id')
        .eq('hospital_id', hospitalId)
        .eq('owner_supervisor_id', supervisorId);
    for (final r in owned) {
      ids.add(r['id'] as String);
    }

    final shared = await _db
        .from('sector_access')
        .select('sector_id')
        .eq('supervisor_id', supervisorId);
    for (final r in shared) {
      ids.add(r['sector_id'] as String);
    }

    return ids.toList();
  }

  /// Arquiva ou desarquiva um relatório (item 2).
  ///
  /// Diretor e Supervisor podem; o escopo do Supervisor vem da RLS de
  /// `inspections`, que já limita o UPDATE aos setores dele.
  Future<void> _toggleArquivar(_RecentInspection r) async {
    final profile = context.read<AuthProvider>().profile;
    if (profile == null) return;
    final arquivar = !r.arquivado;

    if (arquivar) {
      final ok = await confirmAction(
        context,
        title: 'Arquivar relatório?',
        message: 'O relatório de ${r.sectorName} sai da taxa de '
            'conformidade, dos gráficos e de todos os indicadores.\n\n'
            'Ele continua salvo e acessível pelo filtro "Arquivados", e '
            'você pode desarquivar quando quiser. Nada é apagado.',
        confirmLabel: 'Arquivar',
        icon: Icons.inventory_2_outlined,
      );
      if (!ok || !mounted) return;
    }

    final erro = await ArchiveService.setInspectionArchived(
      inspectionId: r.id,
      archive: arquivar,
      userId: profile.id,
      hospitalId: profile.hospitalId,
      descricao: '${r.sectorName} · ${r.checklistTitle}',
    );

    if (!mounted) return;
    if (erro != null) {
      showActionFeedback(context, erro, error: true);
      return;
    }
    showActionFeedback(
        context,
        arquivar
            ? 'Relatório arquivado. Fora dos indicadores.'
            : 'Relatório desarquivado. De volta aos indicadores.');
    _load();
  }

  /// Barra de filtros: busca por nome, setor e status (bloco 3).
  Widget _buildFiltros() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
                value: false,
                label: Text('Ativos'),
                icon: Icon(Icons.insights_outlined, size: 18)),
            ButtonSegment(
                value: true,
                label: Text('Arquivados'),
                icon: Icon(Icons.inventory_2_outlined, size: 18)),
          ],
          selected: {_verArquivados},
          showSelectedIcon: false,
          onSelectionChanged: (sel) {
            setState(() => _verArquivados = sel.first);
            _load();
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _buscaCtrl,
          onChanged: (v) => setState(() => _busca = v),
          decoration: InputDecoration(
            hintText: 'Buscar por setor ou checklist',
            prefixIcon: const Icon(Icons.search, size: 20),
            isDense: true,
            suffixIcon: _busca.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    tooltip: 'Limpar busca',
                    onPressed: () {
                      _buscaCtrl.clear();
                      setState(() => _busca = '');
                    },
                  ),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              DropdownButton<String?>(
                value: _filtroSetorId,
                hint: const Text('Todos os setores'),
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(12),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Todos os setores')),
                  ..._setoresDisponiveis.map((s) => DropdownMenuItem<String?>(
                        value: s.id,
                        child: Text(s.name),
                      )),
                ],
                onChanged: (v) => setState(() => _filtroSetorId = v),
              ),
              const SizedBox(width: 16),
              DropdownButton<String?>(
                value: _filtroStatus,
                hint: const Text('Todos os status'),
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(12),
                items: const [
                  DropdownMenuItem<String?>(
                      value: null, child: Text('Todos os status')),
                  DropdownMenuItem<String?>(
                      value: 'submitted', child: Text('Enviado')),
                  DropdownMenuItem<String?>(
                      value: 'validated', child: Text('Validado')),
                ],
                onChanged: (v) => setState(() => _filtroStatus = v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Card do relatorio: taxa de conformidade, numero de NCs e se tem foto.
  Widget _buildReportCard(_RecentInspection r) {
    final rate = r.complianceRate;
    final rateColor = rate == null
        ? AppColors.textDisabled
        : rate >= 80
            ? AppColors.compliant
            : rate >= 60
                ? AppColors.pending
                : AppColors.nonCompliant;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(AppRoutes.relatorioIndividual(r.id)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.sectorName,
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          r.checklistTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(status: r.status, compact: true),
                  // Arquivar/desarquivar o relatório.
                  IconButton(
                    icon: Icon(
                      r.arquivado
                          ? Icons.unarchive_outlined
                          : Icons.inventory_2_outlined,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    tooltip: r.arquivado
                        ? 'Desarquivar — volta aos indicadores'
                        : 'Arquivar — sai dos indicadores',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _toggleArquivar(r),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.donut_small_outlined, size: 15, color: rateColor),
                  const SizedBox(width: 4),
                  Text(
                    rate != null ? '${rate.toStringAsFixed(1)}%' : '—',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: rateColor, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 14),
                  Icon(Icons.warning_amber_rounded,
                      size: 15,
                      color: r.nonCompliant > 0
                          ? AppColors.nonCompliant
                          : AppColors.textDisabled),
                  const SizedBox(width: 4),
                  Text(
                    '${r.nonCompliant} NC',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: r.nonCompliant > 0
                              ? AppColors.nonCompliant
                              : AppColors.textSecondary,
                          fontWeight: r.nonCompliant > 0
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                  ),
                  const SizedBox(width: 14),
                  Icon(
                    r.temFoto
                        ? Icons.photo_camera_outlined
                        : Icons.no_photography_outlined,
                    size: 15,
                    color:
                        r.temFoto ? AppColors.primary : AppColors.textDisabled,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    r.temFoto ? 'Com foto' : 'Sem foto',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: r.temFoto
                            ? AppColors.textSecondary
                            : AppColors.textDisabled),
                  ),
                  const Spacer(),
                  if (r.submittedAt != null)
                    Text(
                      AppDateUtils.formatTime(r.submittedAt!),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.textDisabled),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatórios & Análises'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Calendário',
            onPressed: () => context.push(AppRoutes.calendarioInstitucional),
          ),
          IconButton(
            icon: const Icon(Icons.view_kanban_outlined),
            tooltip: 'Quadro de tarefas',
            onPressed: () => context.push(AppRoutes.quadroTarefasGestao),
          ),
        ],
      ),
      body: _loading
          ? const SkeletonDashboard()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(AppDimensions.screenPadding),
                children: [
                  if (_isSupervisor)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Dados restritos aos seus setores.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ),

                  Row(
                    children: [
                      Expanded(
                        child: StatCard(
                          label: 'Conformidade',
                          value: '${_conformidade.toStringAsFixed(1)}%',
                          icon: Icons.verified_outlined,
                          color: _conformidade >= 80
                              ? AppColors.compliant
                              : _conformidade >= 60
                                  ? AppColors.pending
                                  : AppColors.nonCompliant,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatCard(
                          label: 'Inspeções',
                          value: _totalInspecoes.toString(),
                          icon: Icons.assignment_turned_in_outlined,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  StatCard(
                    label: 'NCs abertas',
                    value: _ncsAbertas.toString(),
                    icon: Icons.warning_amber_outlined,
                    color: _ncsAbertas > 0
                        ? AppColors.nonCompliant
                        : AppColors.compliant,
                  ),
                  const SizedBox(height: 16),

                  // Gráfico "Inspeções na semana" removido — sem substituto
                  // por enquanto. Mantido apenas o donut de conformidade.
                  ChartCard(
                    title: 'Conformidade geral',
                    subtitle: 'Itens respondidos em todas as inspeções',
                    child: ComplianceDonut(
                      compliant: _totalCompliant,
                      nonCompliant: _totalNonCompliant,
                      notApplicable: _totalNotApplicable,
                    ),
                  ),

                  const SizedBox(height: 24),
                  Text('Inspeções recentes',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),

                  if (_recentes.isEmpty && !_verArquivados)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: EmptyState(
                        icon: Icons.insights_outlined,
                        title: 'Nenhuma inspeção concluída',
                        subtitle:
                            'Os relatórios aparecem aqui assim que os Inspetores enviarem as inspeções.',
                      ),
                    )
                  else if (_recentes.isEmpty && _verArquivados)
                    Column(
                      children: [
                        _buildFiltros(),
                        const Padding(
                          padding: EdgeInsets.only(top: 24),
                          child: EmptyState(
                            icon: Icons.inventory_2_outlined,
                            title: 'Nenhum relatório arquivado',
                            subtitle:
                                'Relatórios arquivados ficam aqui, fora dos '
                                'indicadores, e voltam a contar assim que '
                                'forem desarquivados.',
                          ),
                        ),
                      ],
                    )
                  else ...[
                    _buildFiltros(),
                    const SizedBox(height: 12),
                    if (_relatoriosFiltrados.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: EmptyState(
                          icon: Icons.filter_alt_off_outlined,
                          title: 'Nenhum relatório neste filtro',
                          subtitle:
                              'Ajuste o setor, o status ou a busca para ver '
                              'outros relatórios.',
                        ),
                      )
                    else
                      // Agrupado por data: cada dia ganha cabeçalho próprio,
                      // em vez de uma coluna longa sem referência (bloco 3).
                      ..._agrupadosPorData.expand((grupo) => [
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(4, 16, 4, 8),
                              child: Row(
                                children: [
                                  Text(
                                    _rotuloData(grupo.key),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                            color: AppColors.textSecondary),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${grupo.value.length}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                            color: AppColors.textDisabled),
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                      child: Divider(
                                          height: 1,
                                          color: AppColors.border)),
                                ],
                              ),
                            ),
                            ...grupo.value.map(_buildReportCard),
                          ]),
                  ],
                ],
              ),
            ),
    );
  }
}

class _RecentInspection {
  final String id;
  final String status;
  final String sectorId;
  final String sectorName;
  final String checklistTitle;
  final DateTime? submittedAt;
  final double? complianceRate;
  final int nonCompliant;
  final bool temFoto;
  final bool arquivado;

  _RecentInspection({
    required this.id,
    required this.status,
    required this.sectorId,
    required this.sectorName,
    required this.checklistTitle,
    required this.submittedAt,
    this.complianceRate,
    this.nonCompliant = 0,
    this.temFoto = false,
    this.arquivado = false,
  });
}

/// Métricas de um relatório, exibidas no card da lista (bloco 3).
class _ReportMetrics {
  final double? complianceRate;
  final int nonCompliant;
  final bool temFoto;

  const _ReportMetrics({
    this.complianceRate,
    this.nonCompliant = 0,
    this.temFoto = false,
  });
}
