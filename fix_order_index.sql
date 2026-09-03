-- ============================================================
-- InspecionaHU — Correção de order_index invertido
--
-- CAUSA: postgrest-dart usa `ascending: false` por padrão em
-- .order(). O fluxo "Usar template" lia os itens do template em
-- ordem DECRESCENTE e gravava order_index 0..N nessa ordem,
-- deixando os checklists espelhados.
--
-- NÃO altera id de item nem toca em inspection_responses.
-- Só reescreve a coluna order_index.
-- ============================================================


-- ══════════════════════════════════════════════════════════
-- PASSO 1 (DIAGNÓSTICO) — quais checklists estão invertidos?
--
-- Casa os itens ativos de cada checklist com os itens do
-- template de mesma description e mede a correlação entre as
-- duas ordens. Se a ordem do checklist é o inverso da ordem do
-- template, o checklist está afetado.
-- ══════════════════════════════════════════════════════════
WITH par AS (
  SELECT
    ci.checklist_id,
    t.id                AS template_id,
    t.title             AS template_title,
    ci.order_index      AS idx_checklist,
    ti.order_index      AS idx_template
  FROM checklist_items ci
  JOIN checklists c          ON c.id = ci.checklist_id
  JOIN checklist_template_items ti ON ti.description = ci.description
  JOIN checklist_templates t ON t.id = ti.template_id
  WHERE ci.status = 'active'
),
agrupado AS (
  SELECT
    checklist_id,
    template_id,
    template_title,
    count(*)                              AS itens_casados,
    corr(idx_checklist::float, idx_template::float) AS correlacao
  FROM par
  GROUP BY checklist_id, template_id, template_title
  HAVING count(*) >= 3
)
SELECT
  c.id            AS checklist_id,
  c.title         AS checklist,
  s.name          AS setor,
  h.sigla         AS hospital,
  a.template_title,
  a.itens_casados,
  round(a.correlacao::numeric, 3) AS correlacao,
  CASE
    WHEN a.correlacao < -0.9 THEN 'INVERTIDO — corrigir'
    WHEN a.correlacao >  0.9 THEN 'ok'
    ELSE 'parcial — conferir manualmente'
  END AS diagnostico
FROM agrupado a
JOIN checklists c ON c.id = a.checklist_id
JOIN sectors   s ON s.id = c.sector_id
JOIN hospitals h ON h.id = c.hospital_id
ORDER BY diagnostico, c.title;


-- ══════════════════════════════════════════════════════════
-- PASSO 2 (CONTAGEM) — quantos checklists e itens serão afetados
-- ══════════════════════════════════════════════════════════
WITH par AS (
  SELECT ci.checklist_id, ci.order_index AS idx_checklist,
         ti.order_index AS idx_template
  FROM checklist_items ci
  JOIN checklist_template_items ti ON ti.description = ci.description
  WHERE ci.status = 'active'
),
invertidos AS (
  SELECT checklist_id
  FROM par
  GROUP BY checklist_id
  HAVING count(*) >= 3
     AND corr(idx_checklist::float, idx_template::float) < -0.9
)
SELECT
  (SELECT count(*) FROM invertidos)                         AS checklists_afetados,
  (SELECT count(*) FROM checklist_items ci
    WHERE ci.status = 'active'
      AND ci.checklist_id IN (SELECT checklist_id FROM invertidos)) AS itens_afetados;


-- ══════════════════════════════════════════════════════════
-- PASSO 3 (PRÉVIA) — como cada item ficará, antes de gravar
-- Rode e confira algumas linhas antes do UPDATE do passo 4.
-- ══════════════════════════════════════════════════════════
WITH par AS (
  SELECT ci.checklist_id, ci.order_index AS idx_checklist,
         ti.order_index AS idx_template
  FROM checklist_items ci
  JOIN checklist_template_items ti ON ti.description = ci.description
  WHERE ci.status = 'active'
),
invertidos AS (
  SELECT checklist_id
  FROM par
  GROUP BY checklist_id
  HAVING count(*) >= 3
     AND corr(idx_checklist::float, idx_template::float) < -0.9
),
novo AS (
  SELECT
    ci.id,
    ci.checklist_id,
    ci.description,
    ci.order_index AS order_index_atual,
    -- inverte a ordem atual: o último vira o primeiro
    (row_number() OVER (PARTITION BY ci.checklist_id
                        ORDER BY ci.order_index DESC, ci.id DESC) - 1) AS order_index_novo
  FROM checklist_items ci
  WHERE ci.status = 'active'
    AND ci.checklist_id IN (SELECT checklist_id FROM invertidos)
)
SELECT c.title AS checklist, n.order_index_atual, n.order_index_novo,
       left(n.description, 60) AS item
FROM novo n
JOIN checklists c ON c.id = n.checklist_id
ORDER BY c.title, n.order_index_novo;


-- ══════════════════════════════════════════════════════════
-- PASSO 4 (CORREÇÃO) — só rode após conferir os passos 1 a 3.
--
-- Reescreve APENAS order_index. Não altera id, não apaga item,
-- não toca em inspection_responses (que apontam por
-- checklist_item_id e continuam válidas).
-- Envolvido em transação: confira o resultado e dê COMMIT.
-- ══════════════════════════════════════════════════════════
BEGIN;

WITH par AS (
  SELECT ci.checklist_id, ci.order_index AS idx_checklist,
         ti.order_index AS idx_template
  FROM checklist_items ci
  JOIN checklist_template_items ti ON ti.description = ci.description
  WHERE ci.status = 'active'
),
invertidos AS (
  SELECT checklist_id
  FROM par
  GROUP BY checklist_id
  HAVING count(*) >= 3
     AND corr(idx_checklist::float, idx_template::float) < -0.9
),
novo AS (
  SELECT
    ci.id,
    (row_number() OVER (PARTITION BY ci.checklist_id
                        ORDER BY ci.order_index DESC, ci.id DESC) - 1) AS order_index_novo
  FROM checklist_items ci
  WHERE ci.status = 'active'
    AND ci.checklist_id IN (SELECT checklist_id FROM invertidos)
)
UPDATE checklist_items ci
SET order_index = n.order_index_novo
FROM novo n
WHERE ci.id = n.id
  AND ci.order_index IS DISTINCT FROM n.order_index_novo;

-- Confira a contagem retornada e então:
--   COMMIT;   (para gravar)
--   ROLLBACK; (para descartar)


-- ══════════════════════════════════════════════════════════
-- PASSO 5 (VERIFICAÇÃO pós-COMMIT) — a correlação deve virar
-- positiva (~1.0) nos checklists corrigidos.
-- Basta repetir o PASSO 1.
-- ══════════════════════════════════════════════════════════
