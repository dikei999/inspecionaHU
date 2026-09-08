-- ═══════════════════════════════════════════════════════════════════════════
-- migration_archive_inspection.sql
--
-- Inverte a regra do arquivamento: quem alimenta gráfico e taxa é o
-- RELATÓRIO DE INSPEÇÃO, não o formulário. Então:
--
--   • inspections.archived_at  → arquivar/desarquivar o relatório
--     (REVERSÍVEL; sai de todos os indicadores; visível no filtro
--      "Arquivados"; nada é deletado)
--
--   • checklists.deleted_at    → EXCLUSÃO em soft delete
--     (sai das listas, não recebe tarefa nova; as inspeções já feitas
--      continuam íntegras e legíveis — inclusive as geradas por ele)
--
-- As colunas checklists.archived_at/archived_by continuam existindo por
-- compatibilidade com o que já foi arquivado, mas deixam de ser usadas na
-- interface. NADA é deletado do banco.
--
-- Idempotente. Não altera nenhuma policy de RLS: arquivar uma inspeção e
-- excluir um checklist são UPDATEs, e as policies existentes já governam
-- quem pode fazer UPDATE em cada tabela.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Arquivamento de relatório (inspections) ────────────────────────────
ALTER TABLE inspections
  ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS archived_by UUID REFERENCES profiles(id);

COMMENT ON COLUMN inspections.archived_at IS
  'Relatório arquivado: sai de TODOS os indicadores, gráficos e taxas, e '
  'passa a aparecer só no filtro "Arquivados". Reversível. NULL = ativo.';
COMMENT ON COLUMN inspections.archived_by IS
  'Quem arquivou o relatório. Limpo ao desarquivar.';

-- Índice parcial: a maioria esmagadora das linhas tem archived_at NULL,
-- então ele cobre exatamente o conjunto pequeno que precisamos excluir.
CREATE INDEX IF NOT EXISTS idx_inspections_archived
  ON inspections (hospital_id, id)
  WHERE archived_at IS NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'inspections_archived_consistency'
  ) THEN
    ALTER TABLE inspections
      ADD CONSTRAINT inspections_archived_consistency
      CHECK (archived_by IS NULL OR archived_at IS NOT NULL);
  END IF;
END $$;

-- ── 2. Exclusão em soft delete do checklist ───────────────────────────────
ALTER TABLE checklists
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deleted_by UUID REFERENCES profiles(id);

COMMENT ON COLUMN checklists.deleted_at IS
  'Exclusão em SOFT DELETE (regra do projeto: nunca DELETE). O checklist '
  'sai das listas e não recebe tarefa nova, mas as inspeções já feitas por '
  'ele continuam íntegras e legíveis. NULL = ativo.';
COMMENT ON COLUMN checklists.deleted_by IS
  'Quem excluiu o checklist.';

CREATE INDEX IF NOT EXISTS idx_checklists_deleted
  ON checklists (hospital_id, id)
  WHERE deleted_at IS NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'checklists_deleted_consistency'
  ) THEN
    ALTER TABLE checklists
      ADD CONSTRAINT checklists_deleted_consistency
      CHECK (deleted_by IS NULL OR deleted_at IS NOT NULL);
  END IF;
END $$;

-- ── 3. Nota sobre as colunas antigas ──────────────────────────────────────
COMMENT ON COLUMN checklists.archived_at IS
  'OBSOLETO: o arquivamento passou para inspections.archived_at. Mantida '
  'por compatibilidade com o que já foi arquivado. Não usar na interface.';
