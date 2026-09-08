import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'offline_store.dart';

/// Resultado de uma rodada de sincronização, para a UI mostrar o que houve
/// em vez de só "sincronizado" (6.4).
class SyncResult {
  final int enviadas;
  final int falharam;
  final int restantes;

  const SyncResult({
    this.enviadas = 0,
    this.falharam = 0,
    this.restantes = 0,
  });

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
  static bool _syncing = false;

  /// Notifica a UI (faixa de status) sobre conexão e tamanho da fila.
  static final ValueNotifier<bool> online = ValueNotifier(true);
  static final ValueNotifier<int> pendingCount = ValueNotifier(0);

  /// Última rodada concluída — a faixa usa para dar o retorno do envio.
  static final ValueNotifier<SyncResult?> lastResult = ValueNotifier(null);

  static Stream<List<ConnectivityResult>> get connectivityStream =>
      _connectivity.onConnectivityChanged;

  static Future<bool> get isOnline async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      // Sem resposta do plugin, assume online: é o comportamento que
      // preserva o fluxo normal do app.
      return true;
    }
  }

  /// Liga o monitor de conexão e sincroniza ao reconectar.
  /// Idempotente: chamar duas vezes não cria dois listeners.
  static Future<void> start() async {
    online.value = await isOnline;
    pendingCount.value = await OfflineStore.queueLength();

    _sub ??= connectivityStream.listen((results) async {
      final agora = results.any((r) => r != ConnectivityResult.none);
      final antes = online.value;
      online.value = agora;
      if (agora && !antes) {
        await syncPending();
      }
    });
  }

  static Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    lastResult.value = null;
    pendingCount.value = 0;
  }

  static Future<void> refreshPendingCount() async {
    pendingCount.value = await OfflineStore.queueLength();
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

    var enviadas = 0;
    var falharam = 0;

    try {
      final fila = await OfflineStore.loadQueue();
      for (final op in fila) {
        final opId = op['_op_id'] as String;
        try {
          final payload = Map<String, dynamic>.from(
            op['payload'] as Map<dynamic, dynamic>,
          );

          // 1. Foto pendente: sobe primeiro e vira signed URL.
          final localPath = op['photo_local_path'] as String?;
          final storagePath = op['photo_storage_path'] as String?;
          if (localPath != null && storagePath != null) {
            final file = File(localPath);
            if (await file.exists()) {
              await _db.storage.from('inspection-photos').upload(
                    storagePath,
                    file,
                    fileOptions: const FileOptions(upsert: true),
                  );
              final signed = await _db.storage
                  .from('inspection-photos')
                  .createSignedUrl(storagePath, 3600);
              payload['photo_url'] = signed;
            }
          }

          // 2. Resposta: upsert idempotente, o mesmo do fluxo online.
          await _db.from('inspection_responses').upsert(
                payload,
                onConflict: 'inspection_id,checklist_item_id',
              );

          await OfflineStore.dequeue(opId);
          if (localPath != null) {
            await OfflineStore.deletePhoto(localPath);
          }
          enviadas++;
        } catch (e) {
          debugPrint('[OfflineSync] falha na op $opId: $e');
          falharam++;
          // Permanece na fila para a próxima tentativa. A foto NÃO é
          // apagada: perder a evidência é pior que reenviar.
        }
      }
    } finally {
      _syncing = false;
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
