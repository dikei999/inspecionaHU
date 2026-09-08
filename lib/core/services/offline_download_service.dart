import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'offline_store.dart';

/// Baixa uma tarefa inteira para uso offline (6.2).
///
/// O pacote guarda a tarefa, o checklist e TODOS os itens com o que o
/// Inspetor precisa em campo: texto, referência da NR-32, criticidade e
/// exigência de foto. É o suficiente para responder o checklist inteiro
/// sem rede.
///
/// Não muda nada do fluxo online (6.6): baixar é uma leitura a mais, feita
/// só quando o Inspetor pede.
class OfflineDownloadService {
  OfflineDownloadService._();

  static SupabaseClient get _db => Supabase.instance.client;

  /// Baixa e persiste o pacote da tarefa. Retorna null em caso de sucesso
  /// ou a mensagem de erro para a UI.
  static Future<String?> downloadTask(String taskId) async {
    try {
      final task =
          await _db.from('tasks').select().eq('id', taskId).maybeSingle();
      if (task == null) return 'Tarefa não encontrada.';

      final checklistId = task['checklist_id'] as String;

      final checklist = await _db
          .from('checklists')
          .select()
          .eq('id', checklistId)
          .maybeSingle();
      if (checklist == null) return 'Checklist não encontrado.';

      // Mesma ordenação da tela de resposta — ascending explícito, porque
      // o .order() do postgrest-dart é DESCENDENTE por padrão.
      final itens = await _db
          .from('checklist_items')
          .select()
          .eq('checklist_id', checklistId)
          .eq('status', 'active')
          .order('order_index', ascending: true)
          .order('id', ascending: true);

      final setor = await _db
          .from('sectors')
          .select('id, name')
          .eq('id', task['sector_id'] as String)
          .maybeSingle();

      // Inspeção em rascunho e respostas já dadas, quando existirem. É o
      // que permite reabrir o checklist sem rede exatamente onde parou.
      final inspecao = await _db
          .from('inspections')
          .select()
          .eq('task_id', taskId)
          .eq('overall_status', 'draft')
          .maybeSingle();

      List<dynamic> respostas = const [];
      if (inspecao != null) {
        respostas = await _db
            .from('inspection_responses')
            .select()
            .eq('inspection_id', inspecao['id'] as String);
      }

      await OfflineStore.saveTaskBundle(taskId, {
        'task_id': taskId,
        'downloaded_at': DateTime.now().toIso8601String(),
        'task': task,
        'checklist': checklist,
        'items': itens,
        'inspection': inspecao,
        'responses': respostas,
        'sector_name': setor?['name'],
        'item_count': (itens as List).length,
      });

      return null;
    } on PostgrestException catch (e) {
      debugPrint('[OfflineDownload] $e');
      return 'Não foi possível baixar: ${e.message}';
    } catch (e) {
      debugPrint('[OfflineDownload] $e');
      return 'Não foi possível baixar. Verifique sua conexão.';
    }
  }

  static Future<List<Map<String, dynamic>>> listarBaixadas() =>
      OfflineStore.listTaskBundles();

  static Future<bool> estaBaixada(String taskId) async =>
      (await OfflineStore.loadTaskBundle(taskId)) != null;

  static Future<void> remover(String taskId) =>
      OfflineStore.deleteTaskBundle(taskId);
}
