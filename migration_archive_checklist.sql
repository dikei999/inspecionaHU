-- ═══════════════════════════════════════════════════════════════════════════
-- migration_archive_checklist.sql — BLOCO 1: arquivar checklist
--
-- Objetivo: permitir que Diretor e Supervisor tirem um checklist de teste da
-- operação SEM apagar nada. Arquivado é REVERSÍVEL e NÃO é soft delete:
--
--   status = 'inactive'  → desativado (já existia; não gera tarefa nova)
--   archived_at IS NOT NULL → arquivado (sai das listas de trabalho E de
--                             TODOS os indicadores/gráficos/taxas)
--
-- As inspeções já respondidas continuam existindo e acessíveis pelo filtro
-- "Arquivados". NADA é deletado — a regra de soft delete permanece intacta.
--
-- Idempotente: pode ser executada mais de uma vez sem efeito colateral.
-- Não altera nenhuma policy de RLS: arquivar é um UPDATE em checklists e as
-- policies existentes (checklists_director_all / checklists_supervisor_update)
-- já restringem o Supervisor aos setores onde é owner ou tem can_edit.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Colunas de arquivamento ────────────────────────────────────────────
ALTER TABLE checklists
  ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS archived_by UUID REFERENCES profiles(id);

COMMENT ON COLUMN checklists.archived_at IS
  'Arquivamento reversível: quando preenchido, o checklist sai das listas de '
  'trabalho e de TODOS os indicadores. NULL = em operação. Nada é deletado.';
COMMENT ON COLUMN checklists.archived_by IS
  'Quem arquivou. Limpo ao desarquivar.';

-- ── 2. Índice para os filtros de indicador ────────────────────────────────
-- Índice parcial: a esmagadora maioria das linhas tem archived_at NULL, então
-- o índice cobre exatamente o conjunto pequeno que precisamos excluir.
CREATE INDEX IF NOT EXISTS idx_checklists_archived
  ON checklists (hospital_id, id)
  WHERE archived_at IS NOT NULL;

-- ── 3. Consistência ───────────────────────────────────────────────────────
-- archived_by só faz sentido junto de archived_at.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'checklists_archived_consistency'
  ) THEN
    ALTER TABLE checklists
      ADD CONSTRAINT checklists_archived_consistency
      CHECK (archived_by IS NULL OR archived_at IS NOT NULL);
  END IF;
END $$;
