-- ═══════════════════════════════════════════════════════════════════════════
-- migration_task_series.sql — tarefa recorrente (série de ocorrências)
--
-- A tarefa continua sendo UMA LINHA POR DATA (tasks.due_date), como o schema
-- sempre foi. O que muda é que a atribuição pode gerar VÁRIAS de uma vez,
-- ligadas por um identificador de série.
--
-- NÃO existe agendamento no servidor, nem pg_cron, nem job em segundo plano:
-- todas as ocorrências são criadas no ato da atribuição, pelo app.
--
-- Idempotente: pode ser executada mais de uma vez.
-- Não altera nenhuma policy de RLS — as policies de tasks já cobrem estas
-- colunas, porque continuam sendo linhas comuns da tabela tasks.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Colunas de série ───────────────────────────────────────────────────
ALTER TABLE tasks
  ADD COLUMN IF NOT EXISTS series_id     UUID,
  ADD COLUMN IF NOT EXISTS series_index  INTEGER,
  ADD COLUMN IF NOT EXISTS series_total  INTEGER;

COMMENT ON COLUMN tasks.series_id IS
  'Agrupa as ocorrências geradas na mesma atribuição recorrente. '
  'NULL = tarefa avulsa (comportamento anterior, preservado).';
COMMENT ON COLUMN tasks.series_index IS
  'Posição desta ocorrência na série, a partir de 1. Exibida como "3 de 14".';
COMMENT ON COLUMN tasks.series_total IS
  'Total de ocorrências criadas na série, para o rótulo "3 de 14".';

-- ── 2. Status cancelled ───────────────────────────────────────────────────
-- Cancelar a série cancela SÓ as ocorrências futuras ainda não respondidas.
-- É soft delete: a linha permanece, muda de status. Nada é apagado.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'tasks_status_check'
  ) THEN
    ALTER TABLE tasks DROP CONSTRAINT tasks_status_check;
  END IF;

  ALTER TABLE tasks
    ADD CONSTRAINT tasks_status_check
    CHECK (status IN ('pending', 'in_progress', 'submitted', 'validated',
                      'cancelled'));
END $$;

-- ── 3. Índice para carregar e cancelar uma série ──────────────────────────
CREATE INDEX IF NOT EXISTS idx_tasks_series
  ON tasks (series_id, series_index)
  WHERE series_id IS NOT NULL;
