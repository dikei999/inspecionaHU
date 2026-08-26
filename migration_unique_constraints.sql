-- ============================================================
-- InspecionaHU — Migration: constraints UNIQUE faltantes
-- Execute no SQL Editor do Supabase ANTES da apresentação.
-- ============================================================
--
-- MOTIVO (bug bloqueante do fluxo do Inspetor):
--   O app usa .upsert(..., onConflict: ...) em dois pontos:
--     1. inspection_responses (auto-save de cada resposta)
--        resposta_checklist_screen.dart:255 e :320
--     2. reports (geração do relatório ao enviar a inspeção)
--        resposta_checklist_screen.dart:530
--
--   O Postgres exige um índice UNIQUE que corresponda ao
--   ON CONFLICT. Sem ele, TODA chamada falha com:
--     42P10 "there is no unique or exclusion constraint
--            matching the ON CONFLICT specification"
--
--   Efeito prático: o Inspetor não consegue salvar nenhuma
--   resposta nem enviar a inspeção.
--
-- Estes índices são idempotentes e não alteram RLS.
-- ============================================================

-- 1. Uma resposta por item por inspeção.
CREATE UNIQUE INDEX IF NOT EXISTS inspection_responses_unique_item
  ON inspection_responses (inspection_id, checklist_item_id);

-- 2. Um relatório por inspeção.
--    (remove duplicatas antigas antes de criar o índice)
DELETE FROM reports a
  USING reports b
  WHERE a.ctid < b.ctid
    AND a.inspection_id = b.inspection_id;

CREATE UNIQUE INDEX IF NOT EXISTS reports_unique_inspection
  ON reports (inspection_id);
