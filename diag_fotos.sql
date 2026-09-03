-- ============================================================
-- InspecionaHU — Diagnóstico de fotos (item 3.1)
-- Quantas respostas realmente têm foto gravada?
-- ============================================================

-- ── A) Inspeção mais recente: resposta a resposta ────────────
WITH ultima AS (
  SELECT id, checklist_id, sector_id, submitted_at, created_at
  FROM inspections
  ORDER BY COALESCE(submitted_at, created_at) DESC
  LIMIT 1
)
SELECT
  ci.order_index + 1              AS item_num,
  left(ci.description, 45)        AS item,
  ir.status,
  CASE WHEN ir.photo_url IS NULL THEN 'SEM FOTO' ELSE 'com foto' END AS foto,
  ir.photo_size_kb                AS kb,
  ir.photo_captured_at,
  ci.requires_photo               AS exige_foto,
  ir.answered_at
FROM ultima u
JOIN inspection_responses ir ON ir.inspection_id = u.id
LEFT JOIN checklist_items ci ON ci.id = ir.checklist_item_id
ORDER BY ci.order_index;


-- ── B) Resumo da inspeção mais recente ───────────────────────
WITH ultima AS (
  SELECT id FROM inspections
  ORDER BY COALESCE(submitted_at, created_at) DESC
  LIMIT 1
)
SELECT
  count(*)                                          AS respostas_total,
  count(ir.photo_url)                               AS com_foto_gravada,
  count(*) - count(ir.photo_url)                    AS sem_foto,
  count(*) FILTER (WHERE ci.requires_photo
                     AND ir.photo_url IS NULL)      AS exigem_foto_e_faltam
FROM ultima u
JOIN inspection_responses ir ON ir.inspection_id = u.id
LEFT JOIN checklist_items ci ON ci.id = ir.checklist_item_id;


-- ── C) Fotos gravadas x arquivos existentes no Storage ───────
-- Se "no_storage" for menor que "gravadas", há photo_url apontando
-- para arquivo que não existe (upload que não completou).
WITH ultima AS (
  SELECT id, hospital_id FROM inspections
  ORDER BY COALESCE(submitted_at, created_at) DESC
  LIMIT 1
)
SELECT
  (SELECT count(ir.photo_url)
     FROM inspection_responses ir, ultima u
    WHERE ir.inspection_id = u.id)                       AS urls_gravadas,
  (SELECT count(*)
     FROM storage.objects o, ultima u
    WHERE o.bucket_id = 'inspection-photos'
      AND o.name LIKE u.hospital_id::text || '/' || u.id::text || '/%')
                                                          AS arquivos_no_storage;


-- ── D) Panorama de todas as inspeções (últimas 20) ───────────
SELECT
  i.id,
  s.name                          AS setor,
  i.overall_status,
  COALESCE(i.submitted_at, i.created_at) AS data,
  count(ir.id)                    AS respostas,
  count(ir.photo_url)             AS com_foto
FROM inspections i
JOIN sectors s ON s.id = i.sector_id
LEFT JOIN inspection_responses ir ON ir.inspection_id = i.id
GROUP BY i.id, s.name, i.overall_status, i.submitted_at, i.created_at
ORDER BY data DESC
LIMIT 20;
