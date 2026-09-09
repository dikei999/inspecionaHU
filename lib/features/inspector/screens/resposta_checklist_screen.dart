import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/models/checklist.dart';
import '../../../core/models/checklist_item.dart';
import '../../../core/models/inspection.dart';
import '../../../core/models/task.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../core/utils/compliance_utils.dart';
import '../../../widgets/nr32_clause_chip.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../core/services/data_source.dart';
import '../../../core/services/offline_download_service.dart';
import '../../../core/services/offline_store.dart';
import '../../../core/services/offline_sync_service.dart';

/// Estado de persistência de uma resposta individual.
/// Situação do salvamento de um item.
///
/// `savedLocal` é salvo DE VERDADE — gravado na fila em disco, sobrevive a
/// fechar o app — apenas ainda não enviado ao servidor por falta de rede.
/// Distingui-lo de `error` é o que impede o app de chamar de "não salva" uma
/// resposta que está guardada (A1).
enum SaveState { idle, saving, saved, savedLocal, error }

/// Estado local de uma resposta de item ainda não submetida.
class _ItemState {
  String? status; // 'C' | 'NC' | 'NA' | null
  String observation;
  String? photoLocalPath;

  /// Foto salva no aparelho aguardando upload, e o destino dela no Storage
  /// (6.3). Enquanto não subir, a operação fica na fila com esses dois.
  String? pendingPhotoPath;
  String? pendingPhotoStoragePath; // path local antes do upload
  String? photoUrl; // URL após upload no Storage
  DateTime? photoCapturedAt;
  int? photoSizeKb;
  bool uploading;
  SaveState saveState;

  _ItemState({
    this.status,
    this.observation = '',
    this.photoUrl,
    this.photoCapturedAt,
    this.photoSizeKb,
  }) : photoLocalPath = null,
       uploading = false,
       saveState = SaveState.idle;
}

class RespostaChecklistScreen extends StatefulWidget {
  final String taskId;

  const RespostaChecklistScreen({super.key, required this.taskId});

  @override
  State<RespostaChecklistScreen> createState() =>
      _RespostaChecklistScreenState();
}

class _RespostaChecklistScreenState extends State<RespostaChecklistScreen> {
  final _db = Supabase.instance.client;
  final _uuid = const Uuid();
  final _scrollCtrl = ScrollController();
  final List<GlobalKey> _itemKeys = [];

  // ── Estado de carregamento ─────────────────────────────────────────────────
  bool _loadingInit = true;
  bool _submitting = false;
  String? _initError;

  // ── Dados carregados ───────────────────────────────────────────────────────
  Task? _task;
  Checklist? _checklist;
  List<ChecklistItem> _items = [];
  Inspection? _inspection;
  // checklistItemId -> _ItemState
  final Map<String, _ItemState> _responses = {};

  // ── Auto-save resiliente ──────────────────────────────────────────────────
  // Debounce para observação (evita um upsert por tecla digitada)
  final Map<String, Timer> _debounceTimers = {};
  static const _maxSaveAttempts = 3;

  // ── Conectividade ──────────────────────────────────────────────────────────
  //
  // Causa raiz do item 1 (auditoria set/2026): esta tela tinha o PRÓPRIO
  // listener de Connectivity().onConnectivityChanged, independente do
  // OfflineSyncService global, com o próprio bool _isOnline começando
  // como `true` até a checagem assíncrona resolver. Duas fontes de
  // verdade — cada uma podia dizer algo diferente da outra, e a
  // inicialização otimista (`true`) abria uma janela real: responder um
  // item nesse intervalo tentava o caminho ONLINE sem rede de fato.
  //
  // Agora não há estado próprio: a tela observa OfflineSyncService.online,
  // que já faz prova de vida real (não só a interface) e é a MESMA fonte
  // que a faixa global usa. Uma verdade só.
  bool get _isOnline => OfflineSyncService.online.value;

  /// Quantas respostas DESTA inspeção estão gravadas na fila em disco
  /// aguardando rede. É informação, não pendência: gravar na fila JÁ é
  /// salvar. Serve para o rodapé dizer quantas serão enviadas depois.
  int _naFilaLocal = 0;

  @override
  void initState() {
    super.initState();
    _init();
    _watchConnectivity();
  }

  @override
  void dispose() {
    OfflineSyncService.online.removeListener(_onOnlineChanged);
    for (final t in _debounceTimers.values) {
      t.cancel();
    }
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Inicialização ──────────────────────────────────────────────────────────

  Future<void> _init() async {
    setState(() {
      _loadingInit = true;
      _initError = null;
    });

    // OFFLINE: abre direto pelo pacote baixado, sem tocar na rede.
    // Antes a tela tentava as cinco consultas, falhava e só então caía no
    // pacote — o que gastava o timeout e podia deixar a tela em erro.
    if (DataSource.estaOffline) {
      final abriu = await _initFromOfflineBundle();
      if (abriu) return;
      if (mounted) {
        setState(() {
          _initError = 'Esta tarefa não foi baixada para uso offline. '
              'Conecte-se à internet para abri-la.';
          _loadingInit = false;
        });
      }
      return;
    }

    try {
      // 1. Buscar a task
      final taskData = await _db
          .from('tasks')
          .select()
          .eq('id', widget.taskId)
          .single();
      _task = Task.fromJson(taskData);

      // 2. Buscar o checklist
      final clData = await _db
          .from('checklists')
          .select()
          .eq('id', _task!.checklistId)
          .single();
      _checklist = Checklist.fromJson(clData);

      // 3. Buscar itens do checklist
      final itemsData = await _db
          .from('checklist_items')
          .select()
          .eq('checklist_id', _task!.checklistId)
          .eq('status', 'active')
          .order('order_index', ascending: true)
          .order('id', ascending: true);
      _items = (itemsData as List)
          .map((e) => ChecklistItem.fromJson(e as Map<String, dynamic>))
          .toList();

      // Inicializa chaves de scroll para cada item
      _itemKeys.clear();
      for (var _ in _items) {
        _itemKeys.add(GlobalKey());
      }

      // 4. Verificar se já existe inspeção draft para esta task
      final existingInsp = await _db
          .from('inspections')
          .select()
          .eq('task_id', widget.taskId)
          .eq('overall_status', 'draft')
          .maybeSingle();

      if (existingInsp != null) {
        _inspection = Inspection.fromJson(existingInsp);
        await _loadExistingResponses();
      } else {
        await _createInspection();
      }

      // Se sobrou algo na fila desta inspeção (envio que falhou antes), ele
      // é mais recente que o servidor e prevalece.
      await _aplicarRespostasDaFila();

      // 5. Marcar task como in_progress se estava pending
      if (_task!.status == 'pending') {
        await _db
            .from('tasks')
            .update({'status': 'in_progress'})
            .eq('id', widget.taskId);
      }

      // Inicializa _ItemState para itens sem resposta
      for (final item in _items) {
        _responses.putIfAbsent(item.id, () => _ItemState());
      }

      // Pacote offline atualizado: se o Inspetor perder a rede no meio da
      // inspeção, esta mesma tela reabre a partir daqui (6.2). Só faz
      // sentido online, que é onde este trecho roda.
      await OfflineDownloadService.downloadTask(widget.taskId);

      if (mounted) setState(() => _loadingInit = false);
    } catch (e) {
      debugPrint('[RespostaChecklist] _init erro: $e');
      // Sem rede: tenta abrir pelo pacote baixado antes de desistir (6.2).
      final abriu = await _initFromOfflineBundle();
      if (abriu) return;
      if (mounted) {
        setState(() {
          _initError = 'Não foi possível abrir o checklist. '
              'Verifique a conexão e tente novamente.';
          _loadingInit = false;
        });
      }
    }
  }

  /// Abre a inspeção a partir do pacote baixado, quando o servidor não
  /// responde (6.2). Só funciona para tarefa que já foi aberta ao menos uma
  /// vez com rede: a linha de `inspections` é criada no servidor, e criar
  /// uma inspeção nova offline mudaria o fluxo online — fora do escopo
  /// que o 6.6 autoriza.
  Future<bool> _initFromOfflineBundle() async {
    try {
      final bundle = await OfflineStore.loadTaskBundle(widget.taskId);
      if (bundle == null) return false;

      final inspecaoJson = bundle['inspection'] as Map<String, dynamic>?;
      if (inspecaoJson == null) return false;

      _task = Task.fromJson(
          Map<String, dynamic>.from(bundle['task'] as Map<dynamic, dynamic>));
      _checklist = Checklist.fromJson(Map<String, dynamic>.from(
          bundle['checklist'] as Map<dynamic, dynamic>));
      _items = (bundle['items'] as List)
          .map((e) =>
              ChecklistItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      _inspection = Inspection.fromJson(Map<String, dynamic>.from(inspecaoJson));

      _itemKeys.clear();
      for (var _ in _items) {
        _itemKeys.add(GlobalKey());
      }

      // Respostas já gravadas no pacote + o que estiver na fila local.
      final respostas = (bundle['responses'] as List?) ?? const [];
      for (final r in respostas) {
        final m = Map<String, dynamic>.from(r as Map);
        _responses[m['checklist_item_id'] as String] = _ItemState(
          status: m['status'] as String?,
          observation: (m['observation'] as String?) ?? '',
          photoUrl: m['photo_url'] as String?,
          photoCapturedAt: m['photo_captured_at'] != null
              ? DateTime.tryParse(m['photo_captured_at'] as String)
              : null,
          photoSizeKb: m['photo_size_kb'] as int?,
        )..saveState = SaveState.saved;
      }
      // A fila local SOBREPÕE o pacote: é o que foi respondido em campo,
      // depois do download. Sem isto o checklist reabria em branco e parecia
      // ter perdido a resposta (A1).
      await _aplicarRespostasDaFila();

      for (final item in _items) {
        _responses.putIfAbsent(item.id, () => _ItemState());
      }

      if (mounted) {
        setState(() {
          _loadingInit = false;
          _initError = null;
        });
      }
      return true;
    } catch (e) {
      debugPrint('[RespostaChecklist] _initFromOfflineBundle: $e');
      return false;
    }
  }

  Future<void> _createInspection() async {
    final profile = context.read<AuthProvider>().profile!;
    final now = DateTime.now().toIso8601String();

    final result = await _db
        .from('inspections')
        .insert({
          'task_id': _task!.id,
          'checklist_id': _task!.checklistId,
          'sector_id': _task!.sectorId,
          'hospital_id': _task!.hospitalId,
          'inspector_id': profile.id,
          'overall_status': 'draft',
          'started_at': now,
          'created_at': now,
        })
        .select()
        .single();

    _inspection = Inspection.fromJson(result);
  }

  Future<void> _loadExistingResponses() async {
    final data = await _db
        .from('inspection_responses')
        .select()
        .eq('inspection_id', _inspection!.id);

    for (final r in data as List) {
      final itemId = r['checklist_item_id'] as String;
      _responses[itemId] = _ItemState(
        status: r['status'] as String?,
        observation: (r['observation'] as String?) ?? '',
        photoUrl: r['photo_url'] as String?,
        photoCapturedAt: r['photo_captured_at'] != null
            ? DateTime.parse(r['photo_captured_at'] as String)
            : null,
        photoSizeKb: r['photo_size_kb'] as int?,
      )..saveState = SaveState.saved;
    }
  }

  /// Aplica sobre `_responses` o que está na fila em disco desta inspeção.
  ///
  /// Vale para os dois caminhos de abertura: offline (sobre o pacote
  /// baixado) e online (sobre o que veio do servidor, caso um envio anterior
  /// tenha falhado). A fila é sempre a versão mais recente — last-write-wins,
  /// como o projeto define.
  Future<void> _aplicarRespostasDaFila() async {
    if (_inspection == null) return;
    final fila = await OfflineStore.queuedResponses(_inspection!.id);
    if (fila.isEmpty) {
      _naFilaLocal = 0;
      return;
    }

    for (final op in fila) {
      final itemId = op['checklist_item_id'] as String?;
      if (itemId == null) continue;
      final payload = Map<String, dynamic>.from(
        (op['payload'] as Map?) ?? const {},
      );
      final estado = _ItemState(
        status: payload['status'] as String?,
        observation: (payload['observation'] as String?) ?? '',
        photoUrl: payload['photo_url'] as String?,
        photoCapturedAt: payload['photo_captured_at'] != null
            ? DateTime.tryParse(payload['photo_captured_at'] as String)
            : null,
        photoSizeKb: payload['photo_size_kb'] as int?,
      )..saveState = SaveState.savedLocal;

      // Foto que ainda não subiu: mostra o arquivo local, senão o item
      // reabriria sem a evidência que o Inspetor tirou.
      final localPath = op['photo_local_path'] as String?;
      if (localPath != null) {
        estado.photoLocalPath = localPath;
        estado.pendingPhotoPath = localPath;
        estado.pendingPhotoStoragePath = op['photo_storage_path'] as String?;
      }

      _responses[itemId] = estado;
    }
    _naFilaLocal = fila.length;
  }

  // ── Conectividade ──────────────────────────────────────────────────────────

  bool _foiOnlineDaUltimaVez = true;

  /// Observa a MESMA fonte que a faixa global usa — OfflineSyncService,
  /// que confirma conexão real (não só a interface) e já dispara sua
  /// própria drenagem (transição + heartbeat periódico, item 1 da
  /// auditoria). Esta tela só reage à mudança para atualizar os itens
  /// que ela mesma enfileirou; não duplica a decisão de sincronizar.
  void _watchConnectivity() {
    _foiOnlineDaUltimaVez = OfflineSyncService.online.value;
    OfflineSyncService.online.addListener(_onOnlineChanged);
  }

  void _onOnlineChanged() {
    if (!mounted) return;
    final agora = OfflineSyncService.online.value;
    final voltou = agora && !_foiOnlineDaUltimaVez;
    _foiOnlineDaUltimaVez = agora;
    setState(() {}); // reflete o novo _isOnline (getter) na tela

    if (voltou) {
      // O OfflineSyncService global já está sincronizando (ou vai
      // terminar em instantes); aqui só refletimos o resultado nos itens
      // desta tela quando ele terminar.
      _sincronizarFilaLocal();
    }
  }

  /// Reflete nos itens desta tela o que a sincronização (global, disparada
  /// pelo OfflineSyncService) já drenou da fila.
  ///
  /// NÃO chama syncPending() de novo: o serviço global já está sincronizando
  /// nesse exato momento (foi o próprio evento online dele que acionou este
  /// listener). Chamar de novo aqui esbarraria no guard `if (_syncing)
  /// return` e voltaria vazio sempre — a tela ficaria achando que nada foi
  /// enviado mesmo quando o envio aconteceu.
  Future<void> _sincronizarFilaLocal() async {
    if (_inspection == null) return;

    // Espera o serviço global terminar a rodada em curso, com um teto —
    // nunca trava a tela indefinidamente se algo external cancelar o sync.
    var esperas = 0;
    while (OfflineSyncService.syncing.value && esperas < 100) {
      await Future.delayed(const Duration(milliseconds: 200));
      esperas++;
      if (!mounted) return;
    }
    if (!mounted) return;

    await _atualizarContagemLocal();
    if (!mounted) return;

    // Não presume: relê a fila e marca como enviado só o item que REALMENTE
    // saiu dela. O que falhou continua sinalizado.
    final aindaNaFila = (await OfflineStore.queuedResponses(_inspection!.id))
        .map((op) => op['checklist_item_id'] as String)
        .toSet();
    if (!mounted) return;

    var algumEnviado = false;
    setState(() {
      for (final entry in _responses.entries) {
        final st = entry.value;
        if (st.saveState != SaveState.savedLocal &&
            st.saveState != SaveState.error) {
          continue;
        }
        if (!aindaNaFila.contains(entry.key)) {
          st.saveState = SaveState.saved;
          algumEnviado = true;
        }
      }
    });
    if (algumEnviado && mounted) {
      showActionFeedback(context, 'Respostas enviadas ao servidor.');
    }
  }

  // ── Auto-save resiliente (retry com backoff exponencial) ──────────────────

  /// Agenda o salvamento da observação com debounce (600ms sem digitar).
  void _scheduleObservationSave(String itemId) {
    _debounceTimers[itemId]?.cancel();
    _debounceTimers[itemId] = Timer(
      const Duration(milliseconds: 600),
      () => _saveResponse(itemId),
    );
  }

  Future<void> _saveResponse(String itemId) async {
    if (_inspection == null) return;
    final state = _responses[itemId];
    if (state == null) return;

    setState(() => state.saveState = SaveState.saving);

    final payload = {
      'inspection_id': _inspection!.id,
      'checklist_item_id': itemId,
      'status': state.status,
      'observation': state.observation.trim().isEmpty
          ? null
          : state.observation.trim(),
      'photo_url': state.photoUrl,
      'photo_captured_at': state.photoCapturedAt?.toIso8601String(),
      'photo_size_kb': state.photoSizeKb,
      'answered_at': DateTime.now().toIso8601String(),
    };

    if (!_isOnline) {
      // Sem rede: gravar na fila em disco É salvar (A1). O arquivo tem id
      // determinístico por (inspeção, item), sobrevive a fechar o app e é
      // enviado pelo OfflineSyncService quando a conexão voltar. Não existe
      // aqui uma segunda fila em memória: ela duplicava a de disco e, ao
      // sincronizar, drenava uma sem baixar a outra.
      await OfflineSyncService.enqueueResponse(
        inspectionId: _inspection!.id,
        checklistItemId: itemId,
        payload: payload,
        photoLocalPath: state.pendingPhotoPath,
        photoStoragePath: state.pendingPhotoStoragePath,
      );
      await _atualizarContagemLocal();
      if (mounted) setState(() => state.saveState = SaveState.savedLocal);
      return;
    }

    // Retry com backoff: 3 tentativas (0.8s, 1.6s entre elas)
    for (var attempt = 1; attempt <= _maxSaveAttempts; attempt++) {
      try {
        await _db
            .from('inspection_responses')
            .upsert(payload, onConflict: 'inspection_id,checklist_item_id');
        if (mounted) setState(() => state.saveState = SaveState.saved);
        return;
      } catch (e) {
        debugPrint(
          '[RespostaChecklist] _saveResponse tentativa $attempt falhou: $e',
        );
        if (attempt < _maxSaveAttempts) {
          await Future.delayed(
            Duration(milliseconds: 800 * (1 << (attempt - 1))),
          );
          if (!mounted) return;
        }
      }
    }

    // Todas as tentativas falharam com rede disponível: enfileira em disco
    // do mesmo jeito, então a resposta não se perde nem fechando o app. O
    // item fica marcado como erro porque, COM rede, falhar é anormal e o
    // Inspetor deve poder tentar de novo na hora.
    await OfflineSyncService.enqueueResponse(
      inspectionId: _inspection!.id,
      checklistItemId: itemId,
      payload: payload,
      photoLocalPath: state.pendingPhotoPath,
      photoStoragePath: state.pendingPhotoStoragePath,
    );
    await _atualizarContagemLocal();
    if (mounted) setState(() => state.saveState = SaveState.error);
  }

  /// Repete manualmente o salvamento de um item com erro.
  void _retrySave(String itemId) => _saveResponse(itemId);

  /// Recontagem do que está na fila em disco para ESTA inspeção.
  Future<void> _atualizarContagemLocal() async {
    if (_inspection == null) return;
    final n = await OfflineStore.queueLengthForInspection(_inspection!.id);
    if (mounted) setState(() => _naFilaLocal = n);
  }

  // ── Saida com pendencia (bloco 4) ─────────────────────────────────────────

  /// Há risco REAL de perder resposta ao sair agora?
  ///
  /// Só há risco enquanto um salvamento está em voo (`saving`), porque essa
  /// gravação ainda não chegou nem ao servidor nem ao disco. O que já está
  /// na fila local — offline ou depois de falha — está guardado no aparelho
  /// e é enviado depois, então NÃO é perda e não gera alarme (A1).
  bool get _temRiscoDePerda => _savingCount > 0;

  /// Confirma a saída apenas quando existe alteração de fato não gravada.
  /// Retorna true para sair.
  Future<bool> _confirmarSaida() async {
    if (!_temRiscoDePerda) return true;

    return confirmAction(
      context,
      title: 'Aguardar o salvamento?',
      message: '$_savingCount resposta(s) estão sendo gravadas neste '
          'momento. Saindo agora, elas podem não ser registradas.',
      confirmLabel: 'Sair mesmo assim',
      cancelLabel: 'Aguardar',
      icon: Icons.warning_amber_rounded,
      destructive: true,
    );
  }

  /// Mensagem de saída tranquila: confirma que ficou guardado no aparelho.
  void _avisarGuardadoLocalmente() {
    if (_naFilaLocal == 0) return;
    final plural = _naFilaLocal == 1 ? 'resposta salva' : 'respostas salvas';
    showActionFeedback(
      context,
      '$_naFilaLocal $plural neste aparelho. Serão enviadas quando houver '
      'conexão.',
    );
  }

  // ── Status global de salvamento (para a barra de progresso) ────────────────

  int get _savingCount =>
      _responses.values.where((s) => s.saveState == SaveState.saving).length;
  int get _errorCount =>
      _responses.values.where((s) => s.saveState == SaveState.error).length;

  // ── Foto ───────────────────────────────────────────────────────────────────

  Future<void> _takePhoto(String itemId) async {
    final state = _responses[itemId];
    if (state == null || _inspection == null) return;

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera, // SOMENTE câmera — galeria bloqueada
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;

      setState(() => state.uploading = true);

      // Comprimir
      final dir = await getTemporaryDirectory();
      final targetPath = '${dir.path}/${_uuid.v4()}.jpg';

      final compressed = await FlutterImageCompress.compressAndGetFile(
        picked.path,
        targetPath,
        minWidth: 1280,
        minHeight: 1280,
        quality: 75,
        format: CompressFormat.jpeg,
      );

      if (compressed == null) {
        if (mounted) {
          setState(() => state.uploading = false);
          _showPhotoError(
            'Não foi possível processar a foto. Tente novamente.',
          );
        }
        return;
      }
      if (!mounted) return;

      final compressedFile = File(compressed.path);
      final sizeKb = (await compressedFile.length() / 1024).round();
      final capturedAt = DateTime.now();

      // Atualiza thumbnail local imediatamente
      setState(() {
        state.photoLocalPath = compressedFile.path;
        state.photoCapturedAt = capturedAt;
        state.photoSizeKb = sizeKb;
      });

      // Upload para Storage
      final fileName = '${_uuid.v4()}.jpg';
      final storagePath = '${_task!.hospitalId}/${_inspection!.id}/$fileName';

      // Foto NUNCA é descartada por falta de rede (6.3): antes de tentar
      // subir, sai do diretório temporário (que o sistema pode limpar) e
      // vai para a pasta do app, junto do destino no Storage.
      final persisted =
          await OfflineStore.persistPhoto(compressedFile, fileName);
      if (mounted) {
        setState(() {
          state.pendingPhotoPath = persisted;
          state.pendingPhotoStoragePath = storagePath;
          if (persisted != null) state.photoLocalPath = persisted;
        });
      }

      if (!_isOnline) {
        // Sem rede: a foto fica no aparelho e sobe junto da resposta
        // quando a conexão voltar. Nada de erro vermelho aqui.
        if (mounted) setState(() => state.uploading = false);
        await _saveResponse(itemId);
        return;
      }

      await _db.storage
          .from('inspection-photos')
          .upload(storagePath, compressedFile);

      // Gerar signed URL válida por 1h
      final signedUrl = await _db.storage
          .from('inspection-photos')
          .createSignedUrl(storagePath, 3600);

      if (!mounted) return;
      setState(() {
        state.photoUrl = signedUrl;
        state.uploading = false;
        // Subiu: não há mais foto pendente para a fila.
        state.pendingPhotoPath = null;
        state.pendingPhotoStoragePath = null;
      });
      if (persisted != null) {
        await OfflineStore.deletePhoto(persisted);
      }

      await _saveResponse(itemId);
    } catch (e) {
      debugPrint('[RespostaChecklist] _takePhoto erro: $e');
      if (mounted) {
        // O thumbnail local é limpo junto: mantê-lo faria o Inspetor
        // acreditar que a foto foi gravada quando o upload falhou, e a
        // foto sumiria depois no relatório e no PDF.
        // A foto continua no aparelho e na fila (6.3): limpar aqui era o
        // comportamento antigo, de quando não havia onde guardá-la.
        final enfileirada = state.pendingPhotoPath != null;
        setState(() {
          state.uploading = false;
          if (state.photoUrl == null && !enfileirada) {
            state.photoLocalPath = null;
            state.photoCapturedAt = null;
            state.photoSizeKb = null;
          }
        });
        if (enfileirada) {
          await _saveResponse(itemId);
          _showPhotoError(
            'Sem conexão para enviar a foto agora. Ela ficou salva neste '
            'aparelho e sobe sozinha quando a internet voltar.',
          );
        } else {
          _showPhotoError(
            'A foto NÃO foi salva. Verifique a conexão e tire novamente.',
          );
        }
      }
    }
  }

  /// Aviso de falha de foto — persistente e com ação de dispensar, para não
  /// passar despercebido enquanto o Inspetor preenche o checklist.
  void _showPhotoError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: AppColors.nonCompliant,
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
  }

  // ── Validação e envio ──────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_inspection == null) return;

    // Finalizar fecha a inspeção e grava o relatório no servidor — não tem
    // equivalente local. Offline, avisa em vez de falhar: as respostas já
    // estão salvas no aparelho e sobem sozinhas ao reconectar.
    if (DataSource.estaOffline) {
      showActionFeedback(
        context,
        'Sem conexão para finalizar. As respostas estão salvas neste '
        'aparelho e o envio acontece quando a internet voltar.',
      );
      return;
    }

    // Valida que todos os itens foram respondidos
    for (int i = 0; i < _items.length; i++) {
      final item = _items[i];
      final state = _responses[item.id];
      if (state?.status == null) {
        _scrollToItem(i);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Item ${i + 1} não foi respondido. Responda todos os itens antes de enviar.',
            ),
            backgroundColor: AppColors.nonCompliant,
          ),
        );
        return;
      }
      if (state!.status == 'NC') {
        if (state.observation.trim().isEmpty) {
          _scrollToItem(i);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Item ${i + 1} (NC): ${AppStrings.errorNcRequiresObservation}',
              ),
              backgroundColor: AppColors.nonCompliant,
            ),
          );
          return;
        }
        if (item.requiresPhoto && state.photoUrl == null) {
          _scrollToItem(i);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Item ${i + 1} (NC): ${AppStrings.errorNcRequiresPhoto}',
              ),
              backgroundColor: AppColors.nonCompliant,
            ),
          );
          return;
        }
      }
    }

    // Confirmação
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar e enviar?'),
        content: const Text(
          'Após o envio, a inspeção não poderá ser editada. Deseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _submitting = true);

    try {
      final now = DateTime.now().toIso8601String();
      final profile = context.read<AuthProvider>().profile!;

      // Calcular métricas
      int compliant = 0, nonCompliant = 0, notApplicable = 0;
      for (final item in _items) {
        final s = _responses[item.id]?.status;
        if (s == 'C') compliant++;
        if (s == 'NC') nonCompliant++;
        if (s == 'NA') notApplicable++;
      }
      final total = _items.length;
      // Fonte UNICA de calculo: ComplianceUtils. Antes esta linha dividia
      // por _items.length, ou seja, contava os NA no denominador — um
      // relatorio com 5 C, 0 NC e 5 NA era gravado como 50%%, enquanto o
      // donut do painel mostrava 100%% para o mesmo dado (C3). Item que
      // nao se aplica nao e conformidade nem falha.
      final rate = ComplianceUtils.taxa(
        compliant: compliant,
        nonCompliant: nonCompliant,
      );

      // UPDATE inspection
      await _db
          .from('inspections')
          .update({
            'overall_status': 'submitted',
            'submitted_at': now,
            'finished_at': now,
          })
          .eq('id', _inspection!.id);

      // UPDATE task
      await _db
          .from('tasks')
          .update({'status': 'submitted'})
          .eq('id', widget.taskId);

      // INSERT / UPSERT report
      await _db.from('reports').upsert({
        'inspection_id': _inspection!.id,
        'sector_id': _task!.sectorId,
        'hospital_id': _task!.hospitalId,
        'total_items': total,
        'compliant': compliant,
        'non_compliant': nonCompliant,
        'not_applicable': notApplicable,
        'compliance_rate': rate,
        'generated_at': now,
      }, onConflict: 'inspection_id');

      // Audit log
      await AuditService.log(
        userId: profile.id,
        hospitalId: _task!.hospitalId,
        action: 'inspection.submitted',
        entityType: 'inspection',
        entityId: _inspection!.id,
        details: {
          'total': total,
          'compliant': compliant,
          'non_compliant': nonCompliant,
          'compliance_rate': rate.toStringAsFixed(1),
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Inspeção enviada com sucesso!'),
            backgroundColor: AppColors.compliant,
          ),
        );
        Navigator.of(context).pop(true); // volta para quadro de tarefas
      }
    } catch (e) {
      debugPrint('[RespostaChecklist] _submit erro: $e');
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Não foi possível enviar a inspeção. '
                'Suas respostas continuam salvas.'),
            backgroundColor: AppColors.nonCompliant,
          ),
        );
      }
    }
  }

  void _scrollToItem(int index) {
    final key = _itemKeys[index];
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.1,
      );
    }
  }

  // ── Progresso ──────────────────────────────────────────────────────────────

  int get _answeredCount =>
      _responses.values.where((s) => s.status != null).length;

  bool get _allAnswered => _answeredCount == _items.length;

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loadingInit) {
      return Scaffold(
        appBar: AppBar(title: const Text('Responder Checklist')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_initError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Responder Checklist')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppColors.nonCompliant,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  _initError!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _init,
                  child: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isLocked = _inspection?.isLocked ?? false;

    // Sair com resposta ainda nao gravada no servidor pede confirmacao
    // (bloco 4). PopScope cobre o gesto de voltar do sistema; o botao
    // "Salvar e sair" passa pela mesma checagem.
    return PopScope(
      canPop: !_temRiscoDePerda,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmarSaida() && mounted) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_checklist?.title ?? 'Checklist'),
          actions: [
            TextButton(
              onPressed: () async {
                if (await _confirmarSaida() && context.mounted) {
                  // Offline, sair é normal: avisa que ficou guardado em vez
                  // de alarmar (A1).
                  _avisarGuardadoLocalmente();
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Salvar e sair'),
            ),
          ],
        ),
        body: Column(
          children: [
            // ── Banner offline ────────────────────────────────────────────
            if (!_isOnline)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                color: AppColors.pending100,
                child: Row(
                  children: [
                    const Icon(
                      Icons.wifi_off,
                      color: AppColors.pending,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Sem conexão — respostas serão sincronizadas ao reconectar',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.pending,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Banner validado (bloqueado) ───────────────────────────────
            if (isLocked)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                color: AppColors.compliant100,
                child: Row(
                  children: [
                    const Icon(
                      Icons.verified,
                      color: AppColors.compliant,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Inspeção validada — somente leitura',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.compliant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

            // ── Barra de progresso rica ───────────────────────────────────
            _ProgressBar(
              answered: _answeredCount,
              total: _items.length,
              compliant: _responses.values.where((s) => s.status == 'C').length,
              nonCompliant: _responses.values
                  .where((s) => s.status == 'NC')
                  .length,
              notApplicable: _responses.values
                  .where((s) => s.status == 'NA')
                  .length,
              savingCount: _savingCount,
              errorCount: _errorCount,
            ),

            // ── Itens do checklist ────────────────────────────────────────
            Expanded(
              child: ListView.separated(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                itemCount: _items.length,
                separatorBuilder: (_, i) => const SizedBox(height: 12),
                itemBuilder: (ctx, i) {
                  final item = _items[i];
                  final state = _responses.putIfAbsent(
                    item.id,
                    () => _ItemState(),
                  );
                  return _ChecklistItemCard(
                    key: _itemKeys[i],
                    item: item,
                    index: i,
                    state: state,
                    locked: isLocked,
                    onStatusChanged: (s) {
                      setState(() {
                        state.status = s;
                        // Ao sair de NC, limpa a observação (que era obrigatória
                        // por causa da NC). O Inspetor ainda pode digitar uma
                        // observação opcional em C/NA. A foto é mantida.
                        if (s != 'NC') {
                          state.observation = '';
                        }
                      });
                      _saveResponse(item.id);
                    },
                    onObservationChanged: (obs) {
                      state.observation = obs;
                      _scheduleObservationSave(item.id);
                    },
                    onTakePhoto: () => _takePhoto(item.id),
                    onRetrySave: () => _retrySave(item.id),
                  );
                },
              ),
            ),
          ],
        ),

        // ── Botão finalizar ───────────────────────────────────────────────
        bottomNavigationBar: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(
              top: BorderSide(color: AppColors.border, width: 0.5),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Progresso textual
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$_answeredCount de ${_items.length} respondidos',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    _allAnswered
                        ? 'Pronto para enviar'
                        : 'Responda todos os itens',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _allAnswered
                          ? AppColors.compliant
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: (_allAnswered && !isLocked && !_submitting)
                      ? _submit
                      : null,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Finalizar e enviar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Barra de progresso rica ────────────────────────────────────────────────────

class _ProgressBar extends StatelessWidget {
  final int answered;
  final int total;
  final int compliant;
  final int nonCompliant;
  final int notApplicable;
  final int savingCount;
  final int errorCount;

  const _ProgressBar({
    required this.answered,
    required this.total,
    required this.compliant,
    required this.nonCompliant,
    required this.notApplicable,
    required this.savingCount,
    required this.errorCount,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total > 0 ? answered / total : 0.0;

    // Status global do auto-save
    final Widget saveStatus;
    if (savingCount > 0) {
      saveStatus = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
          const SizedBox(width: 5),
          Text(
            'Salvando…',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.primary),
          ),
        ],
      );
    } else if (errorCount > 0) {
      saveStatus = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 12,
            color: AppColors.nonCompliant,
          ),
          const SizedBox(width: 4),
          Text(
            '$errorCount não salvo(s)',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.nonCompliant),
          ),
        ],
      );
    } else if (answered > 0) {
      saveStatus = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_done_outlined,
            size: 12,
            color: AppColors.compliant,
          ),
          const SizedBox(width: 4),
          Text(
            'Tudo salvo',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.compliant),
          ),
        ],
      );
    } else {
      saveStatus = const SizedBox.shrink();
    }

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    'Progresso',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(width: 8),
                  saveStatus,
                ],
              ),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 7,
                backgroundColor: AppColors.border,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.primary,
                ),
              ),
            ),
          ),
          if (answered > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                _CountPill(
                  label: 'C',
                  count: compliant,
                  color: AppColors.compliant,
                ),
                const SizedBox(width: 6),
                _CountPill(
                  label: 'NC',
                  count: nonCompliant,
                  color: AppColors.nonCompliant,
                ),
                const SizedBox(width: 6),
                _CountPill(
                  label: 'NA',
                  count: notApplicable,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _CountPill({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Text(
        '$label · $count',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ── Card de item do checklist ───────────────────────────────────────────────────

class _ChecklistItemCard extends StatefulWidget {
  final ChecklistItem item;
  final int index;
  final _ItemState state;
  final bool locked;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<String> onObservationChanged;
  final VoidCallback onTakePhoto;
  final VoidCallback onRetrySave;

  const _ChecklistItemCard({
    super.key,
    required this.item,
    required this.index,
    required this.state,
    required this.locked,
    required this.onStatusChanged,
    required this.onObservationChanged,
    required this.onTakePhoto,
    required this.onRetrySave,
  });

  @override
  State<_ChecklistItemCard> createState() => _ChecklistItemCardState();
}

class _ChecklistItemCardState extends State<_ChecklistItemCard> {
  late final TextEditingController _obsCtrl;

  @override
  void initState() {
    super.initState();
    _obsCtrl = TextEditingController(text: widget.state.observation);
  }

  @override
  void didUpdateWidget(covariant _ChecklistItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // O pai limpa state.observation ao sair de NC — reflete no controller
    // para o texto antigo não continuar visível no campo.
    if (_obsCtrl.text != widget.state.observation) {
      _obsCtrl.text = widget.state.observation;
    }
  }

  @override
  void dispose() {
    _obsCtrl.dispose();
    super.dispose();
  }

  bool get _isCriticalNc =>
      widget.item.isCritical && widget.state.status == 'NC';

  Color get _cardBorderColor {
    if (_isCriticalNc) return AppColors.nonCompliant;
    if (widget.state.status == 'NC') {
      return AppColors.nonCompliant.withValues(alpha: 0.5);
    }
    if (widget.state.status == 'C') {
      return AppColors.compliant.withValues(alpha: 0.35);
    }
    return AppColors.border;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final state = widget.state;
    final isNC = state.status == 'NC';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        // NC crítica: destaque visual forte (fundo tintado + borda cheia)
        color: _isCriticalNc ? AppColors.nonCompliant50 : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _cardBorderColor,
          width: _isCriticalNc ? 1.5 : 0.8,
        ),
        boxShadow: AppShadows.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Faixa NC crítica ────────────────────────────────────────
            if (_isCriticalNc) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.nonCompliant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.report_gmailerrorred,
                      color: Colors.white,
                      size: 15,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'NÃO CONFORMIDADE CRÍTICA',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── Cabeçalho ───────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Número do item
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${widget.index + 1}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Badge crítico
                          if (item.isCritical) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.nonCompliant100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'CRÍTICO',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.nonCompliant,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          // Chip NR-32 — tocável quando a cláusula existe
                          // no mapa (abre bottom sheet com o texto da norma)
                          if (item.nr32Reference != null)
                            Nr32ClauseChip(
                              reference: item.nr32Reference!,
                              isCritical: item.isCritical,
                            ),
                        ],
                      ),
                      if (item.isCritical || item.nr32Reference != null)
                        const SizedBox(height: 6),
                      Text(
                        item.description,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                // Indicador de salvamento por item
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _SaveIndicator(
                    saveState: state.saveState,
                    onRetry: widget.onRetrySave,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Botões C / NC / NA ───────────────────────────────────────
            if (!widget.locked)
              Row(
                children: [
                  _StatusButton(
                    label: 'C',
                    sublabel: 'Conforme',
                    icon: Icons.check_circle_outline,
                    selected: state.status == 'C',
                    color: AppColors.compliant,
                    onTap: () => widget.onStatusChanged('C'),
                  ),
                  const SizedBox(width: 8),
                  _StatusButton(
                    label: 'NC',
                    sublabel: 'Não Conforme',
                    icon: Icons.cancel_outlined,
                    selected: state.status == 'NC',
                    color: AppColors.nonCompliant,
                    onTap: () => widget.onStatusChanged('NC'),
                  ),
                  const SizedBox(width: 8),
                  _StatusButton(
                    label: 'NA',
                    sublabel: 'Não se aplica',
                    icon: Icons.remove_circle_outline,
                    selected: state.status == 'NA',
                    color: AppColors.textSecondary,
                    onTap: () => widget.onStatusChanged('NA'),
                  ),
                ],
              )
            else
              // Modo leitura
              _ReadonlyStatus(status: state.status),

            // ── Observação (sempre visível; obrigatória apenas se NC) ────
            if (!widget.locked ||
                (widget.locked && state.observation.isNotEmpty)) ...[
              const SizedBox(height: 12),
              if (!widget.locked)
                TextField(
                  controller: _obsCtrl,
                  maxLines: 3,
                  // Teto de tamanho: era o único texto livre do app sem
                  // limite, e é o mais usado (uma observação por NC, com
                  // salvamento automático). 1000 caracteres cobrem com folga
                  // a descrição de uma não conformidade (B6 da auditoria).
                  maxLength: 1000,
                  onChanged: widget.onObservationChanged,
                  decoration: InputDecoration(
                    counterText: '',
                    labelText: isNC
                        ? 'Observação (obrigatória)'
                        : 'Observação (opcional)',
                    hintText: AppStrings.observationHint,
                    prefixIcon: const Icon(Icons.edit_note_outlined),
                    errorText: isNC && state.observation.trim().isEmpty
                        ? 'Observação obrigatória para itens NC'
                        : null,
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: Text(
                    state.observation,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
            ],

            // ── Foto (sempre visível para C/NC/NA) ────────────────────────
            if (!widget.locked ||
                state.photoUrl != null ||
                state.photoLocalPath != null) ...[
              const SizedBox(height: 12),
              _PhotoSection(
                state: state,
                requiresPhoto: item.requiresPhoto,
                locked: widget.locked,
                onTakePhoto: widget.onTakePhoto,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Indicador de salvamento por item ──────────────────────────────────────────

class _SaveIndicator extends StatelessWidget {
  final SaveState saveState;
  final VoidCallback onRetry;

  const _SaveIndicator({required this.saveState, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    switch (saveState) {
      case SaveState.saving:
        return const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 1.5),
        );
      case SaveState.saved:
        return const Icon(
          Icons.cloud_done_outlined,
          size: 16,
          color: AppColors.compliant,
        );
      case SaveState.savedLocal:
        // Salvo no aparelho, aguardando rede. Ícone de "guardado", não de
        // problema: offline isto é o estado normal e correto (A1).
        return const Tooltip(
          message: 'Salva neste aparelho — será enviada quando houver conexão',
          child: Icon(
            Icons.save_outlined,
            size: 16,
            color: AppColors.pending,
          ),
        );
      case SaveState.error:
        return GestureDetector(
          onTap: onRetry,
          child: Tooltip(
            message: 'Falha ao salvar — toque para tentar novamente',
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.nonCompliant100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.sync_problem,
                size: 14,
                color: AppColors.nonCompliant,
              ),
            ),
          ),
        );
      case SaveState.idle:
        return const SizedBox(width: 14);
    }
  }
}

// ── Botão de status C/NC/NA ────────────────────────────────────────────────────

class _StatusButton extends StatelessWidget {
  final String label;
  final String sublabel;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _StatusButton({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? color : color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? color : color.withValues(alpha: 0.2),
              width: selected ? 1.5 : 0.8,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: selected ? Colors.white : color),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sublabel,
                style: TextStyle(
                  fontSize: 10,
                  color: selected
                      ? Colors.white.withValues(alpha: 0.85)
                      : color.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Status leitura ─────────────────────────────────────────────────────────────

class _ReadonlyStatus extends StatelessWidget {
  final String? status;
  const _ReadonlyStatus({this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case 'C':
        color = AppColors.compliant;
        label = 'Conforme';
        break;
      case 'NC':
        color = AppColors.nonCompliant;
        label = 'Não Conforme';
        break;
      case 'NA':
        color = AppColors.textSecondary;
        label = 'Não se aplica';
        break;
      default:
        color = AppColors.textDisabled;
        label = 'Não respondido';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            status == 'C'
                ? Icons.check_circle_outlined
                : status == 'NC'
                ? Icons.cancel_outlined
                : Icons.remove_circle_outline,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Seção de foto ──────────────────────────────────────────────────────────────

class _PhotoSection extends StatelessWidget {
  final _ItemState state;
  final bool requiresPhoto;
  final bool locked;
  final VoidCallback onTakePhoto;

  const _PhotoSection({
    required this.state,
    required this.requiresPhoto,
    required this.locked,
    required this.onTakePhoto,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = state.photoUrl != null || state.photoLocalPath != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.camera_alt_outlined,
              size: 16,
              color: requiresPhoto
                  ? AppColors.nonCompliant
                  : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              requiresPhoto ? 'Foto obrigatória' : 'Foto',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: requiresPhoto
                    ? AppColors.nonCompliant
                    : AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (requiresPhoto && !hasPhoto)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(
                  Icons.error_outline,
                  size: 14,
                  color: AppColors.nonCompliant,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        if (state.uploading)
          Container(
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(strokeWidth: 2),
                  SizedBox(height: 8),
                  Text('Enviando foto...', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          )
        else if (hasPhoto)
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: state.photoLocalPath != null
                    ? Image.file(
                        File(state.photoLocalPath!),
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      )
                    : Image.network(
                        state.photoUrl!,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, e, st) => Container(
                          height: 160,
                          color: AppColors.background,
                          child: const Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: AppColors.textDisabled,
                            ),
                          ),
                        ),
                      ),
              ),
              if (!locked)
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: onTakePhoto,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              if (state.photoCapturedAt != null)
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      AppDateUtils.formatDateTime(state.photoCapturedAt!),
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
            ],
          )
        else if (!locked)
          GestureDetector(
            onTap: onTakePhoto,
            child: Container(
              height: 84,
              decoration: BoxDecoration(
                color: requiresPhoto
                    ? AppColors.nonCompliant50
                    : AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: requiresPhoto
                      ? AppColors.nonCompliant.withValues(alpha: 0.4)
                      : AppColors.border,
                  width: requiresPhoto ? 1.0 : 0.5,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.camera_alt_outlined,
                      color: requiresPhoto
                          ? AppColors.nonCompliant
                          : AppColors.textSecondary,
                      size: 24,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tirar foto',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: requiresPhoto
                            ? AppColors.nonCompliant
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
