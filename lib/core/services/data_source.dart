import 'package:flutter/foundation.dart';

import '../models/checklist_item.dart';
import '../models/inspection.dart';
import '../models/inspection_response.dart';
import '../models/task.dart';
import 'offline_store.dart';
import 'offline_sync_service.dart';

/// Origem do dado — regra ÚNICA para todo o fluxo do Inspetor.
///
/// O problema que isto resolve: cada tela decidia sozinha se buscava na
/// rede, e todas buscavam sempre. Sem conexão a consulta falhava e a tela
/// mostrava "Erro ao carregar tarefas". Quatro rodadas de correção pontual
/// não resolveram porque o defeito não era de uma tela, era de arquitetura.
///
/// A regra agora é uma só:
///   • OFFLINE  → lê do armazenamento local e NÃO dispara chamada de rede.
///                Não é tentar e cair no cache: é não tentar.
///   • ONLINE   → lê da rede e atualiza o cache.
///
/// Nenhuma tela consulta conectividade por conta própria; todas perguntam
/// [estaOffline] e chamam os métodos daqui.
class DataSource {
  DataSource._();

  /// Fonte da verdade sobre o modo de operação.
  ///
  /// Combina o sinal de conectividade com o modo offline do AuthProvider:
  /// quem entrou pelo botão "Continuar offline" opera offline mesmo que o
  /// connectivity_plus acuse Wi-Fi (roteador sem internet, por exemplo).
  static bool _forcadoOffline = false;

  /// Marcado pelo AuthProvider quando a sessão é a do modo offline.
  static void definirModoOffline(bool valor) => _forcadoOffline = valor;

  static bool get estaOffline =>
      _forcadoOffline || !OfflineSyncService.online.value;

  // ══════════════════════════════════════════════════════════════════════
  // Tarefas do Inspetor
  // ══════════════════════════════════════════════════════════════════════

  /// Tarefas do Inspetor a partir dos pacotes baixados.
  ///
  /// Offline, a única verdade disponível é o que foi baixado — por isso o
  /// painel mostra exatamente isso, e um estado vazio quando não há nada.
  static Future<List<TarefaLocal>> tarefasLocais() async {
    try {
      final bundles = await OfflineStore.listTaskBundles();
      final out = <TarefaLocal>[];
      for (final b in bundles) {
        final taskJson = b['task'];
        if (taskJson is! Map) continue;
        try {
          out.add(TarefaLocal(
            task: Task.fromJson(Map<String, dynamic>.from(taskJson)),
            checklistTitle:
                (b['checklist'] as Map?)?['title'] as String? ?? 'Checklist',
            sectorName: b['sector_name'] as String? ?? 'Setor',
          ));
        } catch (e) {
          debugPrint('[DataSource] pacote inválido ignorado: $e');
        }
      }
      out.sort((a, b) => a.task.dueDate.compareTo(b.task.dueDate));
      return out;
    } catch (e) {
      debugPrint('[DataSource] tarefasLocais: $e');
      return const [];
    }
  }

  /// Ocorrências de uma série, a partir dos pacotes baixados.
  static Future<List<TarefaLocal>> serieLocal(String seriesId) async {
    final todas = await tarefasLocais();
    return todas.where((t) => t.task.seriesId == seriesId).toList();
  }

  // ══════════════════════════════════════════════════════════════════════
  // Conteúdo de uma tarefa (checklist + itens + inspeção + respostas)
  // ══════════════════════════════════════════════════════════════════════

  /// Pacote completo de uma tarefa baixada. Null quando não há pacote.
  static Future<PacoteTarefa?> pacoteDaTarefa(String taskId) async {
    try {
      final b = await OfflineStore.loadTaskBundle(taskId);
      if (b == null) return null;

      final inspecaoJson = b['inspection'];
      // Um item malformado no pacote não pode derrubar a inspeção inteira:
      // offline não há como rebaixar. O item problemático é ignorado e o
      // resto do checklist continua respondível.
      final itens = <ChecklistItem>[];
      for (final e in (b['items'] as List? ?? const [])) {
        try {
          itens.add(ChecklistItem.fromJson(Map<String, dynamic>.from(e as Map)));
        } catch (err) {
          debugPrint('[DataSource] item ignorado no pacote: $err');
        }
      }

      return PacoteTarefa(
        task: Task.fromJson(Map<String, dynamic>.from(b['task'] as Map)),
        checklistTitle:
            (b['checklist'] as Map?)?['title'] as String? ?? 'Checklist',
        itens: itens,
        // Sem inspeção no pacote a tarefa não pode ser respondida offline:
        // a linha de `inspections` nasce no servidor.
        inspecao: inspecaoJson is Map
            ? Inspection.fromJson(Map<String, dynamic>.from(inspecaoJson))
            : null,
        respostas: _respostasSeguras(b['responses']),
      );
    } catch (e) {
      debugPrint('[DataSource] pacoteDaTarefa: $e');
      return null;
    }
  }

  static List<InspectionResponse> _respostasSeguras(Object? raw) {
    final out = <InspectionResponse>[];
    for (final e in (raw as List? ?? const [])) {
      try {
        out.add(
            InspectionResponse.fromJson(Map<String, dynamic>.from(e as Map)));
      } catch (err) {
        debugPrint('[DataSource] resposta ignorada no pacote: $err');
      }
    }
    return out;
  }

  /// A tarefa pode ser respondida offline? Só se tiver pacote COM inspeção.
  static Future<bool> podeResponderOffline(String taskId) async {
    final p = await pacoteDaTarefa(taskId);
    return p?.inspecao != null;
  }
}

/// Tarefa vinda do armazenamento local, com o que a lista precisa exibir.
class TarefaLocal {
  final Task task;
  final String checklistTitle;
  final String sectorName;

  const TarefaLocal({
    required this.task,
    required this.checklistTitle,
    required this.sectorName,
  });
}

/// Conteúdo completo de uma tarefa baixada.
class PacoteTarefa {
  final Task task;
  final String checklistTitle;
  final List<ChecklistItem> itens;

  /// Null quando a tarefa nunca foi aberta com rede — nesse caso ela não
  /// pode ser respondida offline.
  final Inspection? inspecao;

  final List<InspectionResponse> respostas;

  const PacoteTarefa({
    required this.task,
    required this.checklistTitle,
    required this.itens,
    required this.inspecao,
    required this.respostas,
  });
}
