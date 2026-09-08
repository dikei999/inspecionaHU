import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'audit_service.dart';

/// Regra central de arquivamento e exclusão — em UM lugar só.
///
/// A divisão é esta, e ela é deliberada:
///
///   ARQUIVAR RELATÓRIO (inspections.archived_at)
///     Quem alimenta gráfico, taxa e indicador é o relatório de inspeção,
///     não o formulário. Arquivar é REVERSÍVEL: a linha continua na tabela,
///     o relatório sai de todos os indicadores e passa a ser visível apenas
///     pelo filtro "Arquivados".
///
///   EXCLUIR CHECKLIST (checklists.deleted_at)
///     Exclusão em SOFT DELETE, como manda a regra do projeto: o checklist
///     sai das listas e não recebe tarefa nova, mas as inspeções já feitas
///     por ele continuam íntegras e legíveis. Excluir um checklist NÃO
///     apaga nem esconde os relatórios que ele gerou.
///
/// Os dashboards não podem replicar esses filtros cada um do seu jeito — é
/// exatamente assim que um indicador passa a divergir de outro.
class ArchiveService {
  ArchiveService._();

  static SupabaseClient get _db => Supabase.instance.client;

  // ══════════════════════════════════════════════════════════════════════
  // Relatórios arquivados — o que sai dos indicadores
  // ══════════════════════════════════════════════════════════════════════

  /// IDs das inspeções arquivadas do hospital, opcionalmente restritas a
  /// alguns setores (escopo do Supervisor).
  ///
  /// Sempre filtra hospital_id (regra de ouro). Em caso de erro devolve
  /// lista vazia: um indicador levemente otimista é melhor que uma tela
  /// quebrada, e a RLS continua sendo a segurança real.
  static Future<List<String>> archivedInspectionIds(
    String hospitalId, {
    List<String>? sectorIds,
  }) async {
    try {
      var q = _db
          .from('inspections')
          .select('id')
          .eq('hospital_id', hospitalId)
          .not('archived_at', 'is', null);
      if (sectorIds != null) {
        q = q.inFilter('sector_id', sectorIds);
      }
      final rows = await q;
      return (rows as List).map((e) => e['id'] as String).toList();
    } catch (e) {
      debugPrint('[ArchiveService] archivedInspectionIds: $e');
      return const [];
    }
  }

  /// Arquiva ou desarquiva um relatório de inspeção.
  ///
  /// Diretor e Supervisor podem; o escopo do Supervisor é garantido pela
  /// RLS de `inspections`, que já limita o UPDATE aos setores dele.
  static Future<String?> setInspectionArchived({
    required String inspectionId,
    required bool archive,
    required String userId,
    String? hospitalId,
    String? descricao,
  }) async {
    try {
      await _db.from('inspections').update({
        'archived_at':
            archive ? DateTime.now().toUtc().toIso8601String() : null,
        'archived_by': archive ? userId : null,
      }).eq('id', inspectionId);

      await AuditService.log(
        userId: userId,
        hospitalId: hospitalId,
        action: archive ? 'arquivar_relatorio' : 'desarquivar_relatorio',
        entityType: 'inspection',
        entityId: inspectionId,
        details: {'descricao': ?descricao},
      );
      return null;
    } on PostgrestException catch (e) {
      debugPrint('[ArchiveService] setInspectionArchived: ${e.message}');
      if (e.code == '42703' || e.message.contains('archived_at')) {
        return 'Recurso indisponível: execute '
            'migration_archive_inspection.sql no SQL Editor do Supabase.';
      }
      return 'Sem permissão para arquivar este relatório.';
    } catch (e) {
      debugPrint('[ArchiveService] setInspectionArchived: $e');
      return 'Erro ao arquivar. Verifique sua conexão.';
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // Checklists excluídos — soft delete
  // ══════════════════════════════════════════════════════════════════════

  /// IDs dos checklists excluídos (soft delete) do hospital.
  ///
  /// Serve para tirá-los das listas de trabalho e dos seletores de tarefa.
  /// NÃO serve para filtrar indicador: os relatórios gerados por um
  /// checklist excluído continuam valendo.
  static Future<List<String>> deletedChecklistIds(String hospitalId) async {
    try {
      final rows = await _db
          .from('checklists')
          .select('id')
          .eq('hospital_id', hospitalId)
          .not('deleted_at', 'is', null);
      return (rows as List).map((e) => e['id'] as String).toList();
    } catch (e) {
      debugPrint('[ArchiveService] deletedChecklistIds: $e');
      return const [];
    }
  }

  /// Exclui um checklist em soft delete, ou restaura.
  ///
  /// Nunca faz DELETE: a linha permanece e as inspeções feitas por ele
  /// continuam íntegras.
  static Future<String?> setChecklistDeleted({
    required String checklistId,
    required bool deleted,
    required String userId,
    String? hospitalId,
    required String title,
  }) async {
    try {
      await _db.from('checklists').update({
        'deleted_at':
            deleted ? DateTime.now().toUtc().toIso8601String() : null,
        'deleted_by': deleted ? userId : null,
      }).eq('id', checklistId);

      await AuditService.log(
        userId: userId,
        hospitalId: hospitalId,
        action: deleted ? 'excluir_checklist' : 'restaurar_checklist',
        entityType: 'checklist',
        entityId: checklistId,
        details: {'title': title},
      );
      return null;
    } on PostgrestException catch (e) {
      debugPrint('[ArchiveService] setChecklistDeleted: ${e.message}');
      if (e.code == '42703' || e.message.contains('deleted_at')) {
        return 'Recurso indisponível: execute '
            'migration_archive_inspection.sql no SQL Editor do Supabase.';
      }
      return 'Sem permissão para excluir este checklist.';
    } catch (e) {
      debugPrint('[ArchiveService] setChecklistDeleted: $e');
      return 'Erro ao excluir. Verifique sua conexão.';
    }
  }
}
