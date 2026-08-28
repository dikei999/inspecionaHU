-- ═══════════════════════════════════════════════════════════════════════════
-- migration_task_code.sql — Código curto por tarefa (ordem de serviço)
-- ═══════════════════════════════════════════════════════════════════════════
-- Formato: OS-YYYY-NNNNN  (ex.: OS-2026-00001)
-- Preenchido automaticamente no INSERT via trigger BEFORE INSERT.
--
-- Rodar no SQL Editor do Supabase (uma única vez).
-- Idempotente: pode ser executado novamente sem efeito colateral.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Coluna ──────────────────────────────────────────────────────────────
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS task_code TEXT;

-- ── 2. Sequence global ─────────────────────────────────────────────────────
-- Sequência única para todos os hospitais. O código é global e imutável,
-- não reinicia por ano (evita colisão em backfill e concorrência).
CREATE SEQUENCE IF NOT EXISTS tasks_code_seq START WITH 1 INCREMENT BY 1;

-- ── 3. Backfill dos registros existentes ───────────────────────────────────
-- Ordena por created_at para que tarefas mais antigas recebam códigos menores.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT id, created_at
    FROM tasks
    WHERE task_code IS NULL
    ORDER BY created_at ASC, id ASC
  LOOP
    UPDATE tasks
    SET task_code = 'OS-'
                    || to_char(r.created_at, 'YYYY')
                    || '-'
                    || lpad(nextval('tasks_code_seq')::TEXT, 5, '0')
    WHERE id = r.id;
  END LOOP;
END $$;

-- ── 4. Constraints ─────────────────────────────────────────────────────────
-- UNIQUE só depois do backfill (evita erro em base já populada).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'tasks_task_code_key'
  ) THEN
    ALTER TABLE tasks ADD CONSTRAINT tasks_task_code_key UNIQUE (task_code);
  END IF;
END $$;

-- ── 5. Trigger de geração automática ───────────────────────────────────────
CREATE OR REPLACE FUNCTION set_task_code()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.task_code IS NULL OR NEW.task_code = '' THEN
    NEW.task_code := 'OS-'
                     || to_char(COALESCE(NEW.created_at, now()), 'YYYY')
                     || '-'
                     || lpad(nextval('tasks_code_seq')::TEXT, 5, '0');
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_set_task_code ON tasks;
CREATE TRIGGER trg_set_task_code
  BEFORE INSERT ON tasks
  FOR EACH ROW
  EXECUTE FUNCTION set_task_code();

-- ── 6. Índice para busca por código ────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_tasks_task_code ON tasks (task_code);

-- ── 7. NOT NULL (após backfill + trigger ativos) ───────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM tasks WHERE task_code IS NULL) THEN
    ALTER TABLE tasks ALTER COLUMN task_code SET NOT NULL;
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Verificação:
--   SELECT task_code, due_date, status FROM tasks ORDER BY task_code LIMIT 20;
-- ═══════════════════════════════════════════════════════════════════════════
