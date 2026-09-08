import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'audit_service.dart';

/// Regra de arquivamento de checklist (bloco 1) em UM lugar só.
///
/// Arquivado é REVERSÍVEL e NÃO é delete: a linha continua na tabela, as
/// inspeções já respondidas continuam existindo e acessíveis pelo filtro
/// "Arquivados". O que muda é que o checklist:
///   • some das listas de trabalho;
///   • não pode receber tarefa nova;
///   • NÃO entra em nenhum indicador, gráfico ou taxa de conformidade.
///
/// Os dashboards não podem replicar esse filtro cada um do seu jeito — é
/// exatamente assim que um indicador passa a divergir de outro. Todos usam
/// [archivedChecklistIds] / [inspectionIdsDeArquivados] daqui.
class ArchiveService {
  ArchiveService._();

  static SupabaseClient get _db => Supabase.instance.client;

  /// IDs dos checklists arquivados do hospital. Lista vazia = nada a excluir.
  ///
  /// Sempre filtra hospital_id (regra de ouro). Em caso de erro devolve lista
  /// vazia: um indicador levemente otimista é melhor que uma tela quebrada,
  /// e a RLS continua sendo a segurança real.
  static Future<List<String>> archivedChecklistIds(String hospitalId) async {
    try {
      final rows = await _db
          .from('checklists')
          .select('id')
          .eq('hospital_id', hospitalId)
          .not('archived_at', 'is', null);
      return (rows as List).map((e) => e['id'] as String).toList();
    } catch (e) {
      debugPrint('[ArchiveService] archivedChecklistIds: $e');
      return const [];
    }
  }

  /// IDs das inspeções que pertencem a checklists arquivados.
  ///
  /// Necessário porque a tabela `reports` (cache de conformidade) guarda
  /// apenas inspection_id — não tem checklist_id. Para tirar um checklist
  /// arquivado do donut e da taxa é preciso passar por `inspections`.
  static Future<List<String>> inspectionIdsDeArquivados(
    String hospitalId, {
    List<String>? sectorIds,
  }) async {
    final archived = await archivedChecklistIds(hospitalId);
    if (archived.isEmpty) return const [];

    try {
      var q = _db
          .from('inspections')
          .select('id')
          .eq('hospital_id', hospitalId)
          .inFilter('checklist_id', archived);
      if (sectorIds != null) {
        q = q.inFilter('sector_id', sectorIds);
      }
      final rows = await q;
      return (rows as List).map((e) => e['id'] as String).toList();
    } catch (e) {
      debugPrint('[ArchiveService] inspectionIdsDeArquivados: $e');
      return const [];
    }
  }

  /// Arquiva ou desarquiva. [archive] false = desarquivar (reversível).
  ///
  /// O escopo do Supervisor é garantido pela RLS: a policy
  /// `checklists_supervisor_update` só permite UPDATE em checklist de setor
  /// onde ele é owner ou tem sector_access.can_edit. Front-end é só UX.
  static Future<String?> setArchived({
    required String checklistId,
    required bool archive,
    required String userId,
    String? hospitalId,
    required String title,
  }) async {
    try {
      await _db.from('checklists').update({
        'archived_at': archive ? DateTime.now().toUtc().toIso8601String() : null,
        'archived_by': archive ? userId : null,
      }).eq('id', checklistId);

      await AuditService.log(
        userId: userId,
        hospitalId: hospitalId,
        action: archive ? 'arquivar_checklist' : 'desarquivar_checklist',
        entityType: 'checklist',
        entityId: checklistId,
        details: {'title': title},
      );
      return null;
    } on PostgrestException catch (e) {
      debugPrint('[ArchiveService] setArchived: ${e.message}');
      // 42703 = coluna inexistente → migration ainda não executada.
      if (e.code == '42703' || e.message.contains('archived_at')) {
        return 'Recurso indisponível: execute migration_archive_checklist.sql '
            'no SQL Editor do Supabase.';
      }
      return 'Sem permissão para arquivar este checklist.';
    } catch (e) {
      debugPrint('[ArchiveService] setArchived: $e');
      return 'Erro ao arquivar. Verifique sua conexão.';
    }
  }
}
