import 'package:connectivity_plus/connectivity_plus.dart';

/// Gerencia o armazenamento offline e a sincronização com o Supabase.
///
/// Estratégia: last-write-wins.
/// Cada resposta de item é salva localmente (Drift/SQLite) imediatamente.
/// Ao recuperar conexão, os rascunhos pendentes são sincronizados.
///
/// todo(Fase 6): Implementar o banco Drift com as tabelas locais:
///   - local_inspection_responses
///   - local_inspections (rascunhos)
class OfflineSyncService {
  OfflineSyncService._();

  static final Connectivity _connectivity = Connectivity();

  static Stream<List<ConnectivityResult>> get connectivityStream =>
      _connectivity.onConnectivityChanged;

  static Future<bool> get isOnline async {
    final result = await _connectivity.checkConnectivity();
    return result.any((r) => r != ConnectivityResult.none);
  }

  /// Inicia o listener de reconexão e dispara a sync automática.
  static void startAutoSync() {
    connectivityStream.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) {
        syncPendingResponses();
      }
    });
  }

  /// Sincroniza respostas pendentes locais com o Supabase.
  /// todo (Fase 6): Implementar lógica real de sync via Drift.
  static Future<void> syncPendingResponses() async {
    // 1. Busca rascunhos locais não sincronizados
    // 2. Para cada resposta, faz upsert no Supabase
    // 3. Marca como sincronizado localmente
    // 4. Se checklist foi alterado durante offline, notifica o Inspetor
  }

  /// Salva uma resposta localmente antes de sincronizar.
  /// todo (Fase 6): Implementar via Drift.
  static Future<void> saveResponseLocally({
    required String inspectionId,
    required String checklistItemId,
    required String? status,
    String? observation,
    String? photoUrl,
  }) async {
    // Persiste no SQLite local
  }
}
