import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'offline_store.dart';
import 'supabase_service.dart';

/// Resultado de uma rodada de sincronização, para a UI mostrar o que houve
/// em vez de só "sincronizado" (6.4).
class SyncResult {
  final int enviadas;
  final int falharam;
  final int restantes;

  const SyncResult({this.enviadas = 0, this.falharam = 0, this.restantes = 0});

  bool get temAlgo => enviadas > 0 || falharam > 0;
}

/// Conectividade + fila de envio do modo offline (bloco 6).
///
/// Estratégia last-write-wins, como já definido no projeto: cada resposta é
/// gravada localmente na hora e enviada quando a rede volta. A ordem da fila
/// é a de criação, e a idempotência vem de duas garantias:
///   1. o id da operação é derivado de (inspection_id, checklist_item_id),
///      então reescrever a mesma resposta sobrescreve o arquivo em vez de
///      empilhar uma segunda operação;
///   2. o envio é um upsert com onConflict nessas mesmas duas colunas, o
///      mesmo que o fluxo online já usa — reenviar não duplica linha.
///
/// IMPORTANTE (6.6): este serviço não altera o caminho online. Quem está com
/// rede continua fazendo upsert direto; a fila só entra quando falha.
class OfflineSyncService {
  OfflineSyncService._();

  static final Connectivity _connectivity = Connectivity();
  static SupabaseClient get _db => Supabase.instance.client;

  static StreamSubscription<List<ConnectivityResult>>? _sub;
  static Timer? _heartbeat;
  static bool _syncing = false;

  /// Causa raiz do item 1 (auditoria set/2026): a sincronização dependia
  /// de UM ÚNICO evento — a transição offline→online do stream do
  /// connectivity_plus. Esse stream reporta a INTERFACE de rede (há
  /// Wi-Fi? há dados?), não se a internet está de fato acessível, e no
  /// Android o evento de retomada pode chegar atrasado, duplicado ou
  /// (fora de processo em segundo plano) nunca chegar. Quando isso
  /// falhava, a fila ficava presa para sempre — sem erro, sem aviso,
  /// silenciosamente — e era isso que fazia a resposta "sumir": ela
  /// nunca tinha saído do aparelho.
  ///
  /// A correção não troca connectivity_plus por outra coisa: ela para de
  /// depender de UM sinal só. Três caminhos, redundantes de propósito:
  ///   1. a transição do stream (como antes, mais rápida quando funciona);
  ///   2. um heartbeat periódico que tenta drenar a fila mesmo sem
  ///      nenhuma transição ter disparado;
  ///   3. isOnline faz uma prova de vida HTTP real contra o próprio
  ///      Supabase, não só pergunta ao SO se há interface de rede — Wi-Fi
  ///      sem internet não passa mais por "online".
  static const _intervaloHeartbeat = Duration(seconds: 20);

  /// Notifica a UI (faixa de status) sobre conexão e tamanho da fila.
  static final ValueNotifier<bool> online = ValueNotifier(true);
  static final ValueNotifier<int> pendingCount = ValueNotifier(0);

  /// Última rodada concluída — a faixa usa para dar o retorno do envio.
  static final ValueNotifier<SyncResult?> lastResult = ValueNotifier(null);

  /// true SÓ enquanto uma rodada de envio está de fato em curso.
  ///
  /// A faixa antes dizia "Enviando" sempre que havia fila com rede, mesmo
  /// parada. Ter fila e estar enviando são coisas diferentes (A1).
  static final ValueNotifier<bool> syncing = ValueNotifier(false);

  static Stream<List<ConnectivityResult>> get connectivityStream =>
      _connectivity.onConnectivityChanged;

  /// true = a interface de rede existe (Wi-Fi/dados ligados). NÃO prova
  /// que há internet — Wi-Fi conectado a um roteador sem internet
  /// devolve true aqui. Usado só como sinal rápido para a UI (faixa,
  /// bloqueio de ações); a decisão de SINCRONIZAR usa [isOnline], que
  /// exige prova de vida real.
  static Future<bool> get _temInterfaceDeRede async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      // Sem resposta do plugin, assume que há interface: é o
      // comportamento que preserva o fluxo normal do app.
      return true;
    }
  }

  /// Prova de vida real: só considera "online" quem responde de fato.
  ///
  /// checkConnectivity() do connectivity_plus prova a INTERFACE, não a
  /// internet (documentado no CLAUDE.md: "o connectivity_plus acusa
  /// 'conectado' só por haver Wi-Fi"). Antes syncPending() só disparava
  /// na transição do stream — se a interface reaparecesse sem internet de
  /// fato (ou o SO reportasse tarde), a fila nunca era tentada e nada
  /// avisava o motivo. Uma requisição curta e barata (HEAD no próprio
  /// projeto Supabase) resolve isso: só entra na fila de envio quem
  /// respondeu de verdade.
  static Future<bool> get isOnline async {
    if (!await _temInterfaceDeRede) return false;
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4);
      final req = await client
          .headUrl(Uri.parse('${SupabaseService.supabaseUrl}/auth/v1/health'))
          .timeout(const Duration(seconds: 4));
      final resp = await req.close().timeout(const Duration(seconds: 4));
      await resp.drain<void>();
      client.close(force: true);
      // Qualquer resposta HTTP (mesmo 4xx) prova que o servidor foi
      // alcançado — é só a acessibilidade da rede que interessa aqui.
      return resp.statusCode > 0;
    } catch (e) {
      debugPrint('[OfflineSync] prova de vida falhou: $e');
      return false;
    }
  }

  /// Liga o monitor de conexão e sincroniza ao reconectar.
  /// Idempotente: chamar duas vezes não cria dois listeners nem dois
  /// heartbeats.
  static Future<void> start() async {
    online.value = await isOnline;
    pendingCount.value = await OfflineStore.queueLength();

    // Fila que sobrou de uma sessão anterior sai agora, sem esperar uma
    // transição de conectividade que pode nunca acontecer.
    unawaited(syncIfNeeded());

    _sub ??= connectivityStream.listen((results) async {
      final temInterface = results.any((r) => r != ConnectivityResult.none);
      if (!temInterface) {
        online.value = false;
        return;
      }
      // Interface voltou: NÃO marca online direto — confirma com prova
      // de vida real antes de disparar o envio, e só then atualiza o
      // notifier. Uma interface "voltando" sem internet de fato não
      // dispara nada e não engana a faixa.
      final real = await isOnline;
      final antes = online.value;
      online.value = real;
      if (real && !antes) {
        await syncPending();
      }
    });

    // Rede de segurança: mesmo que o stream nunca emita a transição certa
    // (evento perdido, app em segundo plano, comportamento do fabricante
    // do aparelho), este timer tenta drenar a fila periodicamente. É o
    // que garante que "salvar e sair, reconectar" funciona mesmo se o
    // evento de conectividade falhar — a causa raiz do item 1.
    _heartbeat ??= Timer.periodic(_intervaloHeartbeat, (_) {
      unawaited(syncIfNeeded());
    });
  }

  static Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    lastResult.value = null;
    pendingCount.value = 0;
    syncing.value = false;
  }

  static Future<void> refreshPendingCount() async {
    pendingCount.value = await OfflineStore.queueLength();
  }

  /// Tenta drenar a fila se houver rede real e nada em curso.
  ///
  /// Chamado no start(), pelo heartbeat periódico, e pela faixa. Três
  /// gatilhos independentes para o mesmo efeito — nenhum deles depende
  /// sozinho de um evento que pode não chegar.
  static Future<void> syncIfNeeded() async {
    if (_syncing) return;
    if (pendingCount.value == 0) return;
    final real = await isOnline;
    online.value = real;
    if (!real) return;
    await syncPending();
  }

  // ── Enfileiramento ────────────────────────────────────────────────────────

  /// Id determinístico da operação de resposta. Duas edições do mesmo item
  /// geram o MESMO id, então a fila guarda só a versão mais recente.
  static String responseOpId(String inspectionId, String checklistItemId) =>
      'resp_${inspectionId}_$checklistItemId';

  /// Enfileira uma resposta (com ou sem foto) para envio posterior.
  /// [photoLocalPath] é a foto já persistida na pasta do app — nunca um
  /// arquivo do diretório temporário, que o sistema pode limpar.
  static Future<void> enqueueResponse({
    required String inspectionId,
    required String checklistItemId,
    required Map<String, dynamic> payload,
    String? photoLocalPath,
    String? photoStoragePath,
  }) async {
    final opId = responseOpId(inspectionId, checklistItemId);
    await OfflineStore.enqueue(opId, {
      'type': 'response',
      'queued_at': DateTime.now().toIso8601String(),
      'inspection_id': inspectionId,
      'checklist_item_id': checklistItemId,
      'payload': payload,
      'photo_local_path': photoLocalPath,
      'photo_storage_path': photoStoragePath,
    });
    await refreshPendingCount();
  }

  // ── Envio ─────────────────────────────────────────────────────────────────

  /// Drena a fila em ordem. Foto vai primeiro, depois a resposta que a
  /// referencia — se a foto falhar, a operação fica na fila inteira e é
  /// tentada de novo, nunca gravando a resposta sem a foto.
  static Future<SyncResult> syncPending() async {
    if (_syncing) return const SyncResult();
    _syncing = true;
    syncing.value = true;

    var enviadas = 0;
    var falharam = 0;

    try {
      final fila = await OfflineStore.loadQueue();
      for (final op in fila) {
        final opId = op['_op_id'] as String;
        // Marca em qual etapa a operação está antes de tentar, para o
        // catch abaixo saber o que registrar mesmo sem reexaminar o
        // payload — é a diferença entre "falhou subindo a foto" e
        // "falhou gravando a resposta" na interface (item 1.a/1.b).
        var etapaAtual = 'foto';
        try {
          final payload = Map<String, dynamic>.from(
            op['payload'] as Map<dynamic, dynamic>,
          );

          // 1. Foto pendente: sobe primeiro e vira signed URL.
          //
          // Se o arquivo local não existisse mais (file.exists()
          // devolvendo false por qualquer motivo), o código antes
          // simplesmente pulava o upload em silêncio e seguia para gravar
          // a resposta SEM foto — sem erro, sem falha registrada, contando
          // como sucesso. Era uma via de "foto sumiu" sem nenhum rastro.
          // Agora a ausência do arquivo quando ele era esperado é uma
          // falha explícita da operação: fica na fila, não é enviada sem
          // a foto que a acompanhava.
          final localPath = op['photo_local_path'] as String?;
          final storagePath = op['photo_storage_path'] as String?;
          if (localPath != null && storagePath != null) {
            final file = File(localPath);
            if (!await file.exists()) {
              throw StateError(
                'foto local ausente ($localPath) — mantendo na fila',
              );
            }
            await _db.storage
                .from('inspection-photos')
                .upload(
                  storagePath,
                  file,
                  fileOptions: const FileOptions(upsert: true),
                );
            final signed = await _db.storage
                .from('inspection-photos')
                .createSignedUrl(storagePath, 3600);
            payload['photo_url'] = signed;
          }

          // 2. Resposta: upsert idempotente, o mesmo do fluxo online.
          etapaAtual = 'resposta';
          await _db
              .from('inspection_responses')
              .upsert(payload, onConflict: 'inspection_id,checklist_item_id');

          await OfflineStore.dequeue(opId);
          if (localPath != null) {
            await OfflineStore.deletePhoto(localPath);
          }
          enviadas++;
        } catch (e) {
          debugPrint('[OfflineSync] falha na op $opId ($etapaAtual): $e');
          falharam++;
          // Erro estruturado gravado JUNTO da operação — item 1.a/1.b:
          // sem isto o motivo real morria no debugPrint, ilegível fora
          // do PC. PostgrestException e StorageException carregam
          // código/status próprios; qualquer outra exceção (arquivo
          // ausente, timeout de rede) vira mensagem + tipo Dart.
          if (e is PostgrestException) {
            final detalhes = [
              if (e.details != null) 'details: ${e.details}',
              if (e.hint != null) 'hint: ${e.hint}',
            ].join(' · ');
            await OfflineStore.registrarFalha(
              opId,
              etapa: etapaAtual,
              codigo: e.code,
              mensagem: e.message,
              detalhe: detalhes.isEmpty ? null : detalhes,
            );
          } else if (e is StorageException) {
            await OfflineStore.registrarFalha(
              opId,
              etapa: etapaAtual,
              codigo: e.statusCode,
              mensagem: e.message,
              detalhe: e.error,
            );
          } else {
            await OfflineStore.registrarFalha(
              opId,
              etapa: etapaAtual,
              codigo: e.runtimeType.toString(),
              mensagem: e.toString(),
            );
          }
          // Permanece na fila para a próxima tentativa. A foto NÃO é
          // apagada: perder a evidência é pior que reenviar.
        }
      }
    } finally {
      _syncing = false;
      syncing.value = false;
      await refreshPendingCount();
    }

    final resultado = SyncResult(
      enviadas: enviadas,
      falharam: falharam,
      restantes: pendingCount.value,
    );
    if (resultado.temAlgo) lastResult.value = resultado;
    return resultado;
  }
}
