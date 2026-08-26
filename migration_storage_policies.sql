-- ============================================================
-- InspecionaHU — Policies de RLS para o bucket inspection-photos
-- Execute manualmente no SQL Editor do Supabase.
--
-- MOTIVO:
--   O bucket inspection-photos existe (privado), mas nunca teve
--   policies de RLS criadas para storage.objects. Todo upload de
--   foto de inspeção falha com:
--     StorageException(message: new row violates row-level
--     security policy, statusCode: 403)
--
-- Libera INSERT/SELECT/UPDATE/DELETE em storage.objects para o
-- bucket inspection-photos apenas para usuários autenticados com
-- role in ('inspector', 'director', 'supervisor', 'super_admin'),
-- via get_my_role() (já existe, SECURITY DEFINER, sem recursão).
--
-- Path usado pelo app: {hospital_id}/{inspection_id}/{uuid}.jpg
-- Não restringe por hospital_id aqui — a app já filtra por
-- hospital_id em todas as queries e o acesso de leitura é sempre
-- via signed URL de 1h (bucket privado). Escopo cirúrgico: só
-- resolve o 403 de RLS, sem introduzir regra nova de negócio.
-- ============================================================

DROP POLICY IF EXISTS "inspection_photos_insert" ON storage.objects;
DROP POLICY IF EXISTS "inspection_photos_select" ON storage.objects;
DROP POLICY IF EXISTS "inspection_photos_update" ON storage.objects;
DROP POLICY IF EXISTS "inspection_photos_delete" ON storage.objects;

CREATE POLICY "inspection_photos_insert"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'inspection-photos'
    AND get_my_role() IN ('inspector', 'director', 'supervisor', 'super_admin')
  );

CREATE POLICY "inspection_photos_select"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'inspection-photos'
    AND get_my_role() IN ('inspector', 'director', 'supervisor', 'super_admin')
  );

CREATE POLICY "inspection_photos_update"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'inspection-photos'
    AND get_my_role() IN ('inspector', 'director', 'supervisor', 'super_admin')
  )
  WITH CHECK (
    bucket_id = 'inspection-photos'
    AND get_my_role() IN ('inspector', 'director', 'supervisor', 'super_admin')
  );

CREATE POLICY "inspection_photos_delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'inspection-photos'
    AND get_my_role() IN ('inspector', 'director', 'supervisor', 'super_admin')
  );
