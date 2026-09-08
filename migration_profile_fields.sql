-- ═══════════════════════════════════════════════════════════════════════════
-- migration_profile_fields.sql — perfil editável
--
-- Acrescenta telefone e cargo em profiles, e versiona as policies do bucket
-- de avatares, que até agora existia só no painel do Supabase.
--
-- Ambas as colunas são NULLABLE: nenhum registro existente quebra e nenhum
-- fluxo passa a exigir preenchimento.
--
-- Idempotente. NÃO altera nenhuma policy de profiles — as existentes já
-- governam quem lê e escreve cada linha, e colunas novas são cobertas por
-- elas automaticamente.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Telefone e cargo ───────────────────────────────────────────────────
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS phone     TEXT,
  ADD COLUMN IF NOT EXISTS job_title TEXT;

COMMENT ON COLUMN profiles.phone IS
  'Telefone de contato, opcional. Informado pelo próprio usuário no perfil.';
COMMENT ON COLUMN profiles.job_title IS
  'Cargo/função do usuário no hospital, opcional. É texto livre e NÃO se '
  'confunde com profiles.role, que define a permissão no sistema.';

-- Comprimento máximo defensivo: campo livre não pode virar depósito de texto.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'profiles_phone_len'
  ) THEN
    ALTER TABLE profiles
      ADD CONSTRAINT profiles_phone_len
      CHECK (phone IS NULL OR char_length(phone) <= 20);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'profiles_job_title_len'
  ) THEN
    ALTER TABLE profiles
      ADD CONSTRAINT profiles_job_title_len
      CHECK (job_title IS NULL OR char_length(job_title) <= 100);
  END IF;
END $$;

-- ── 2. Bucket de avatares ─────────────────────────────────────────────────
-- O app já grava em 'avatars', mas o bucket e suas policies só existiam no
-- painel. Versionar aqui torna o ambiente reproduzível.
--
-- Diferente de inspection-photos, este bucket é PÚBLICO para leitura: a foto
-- de perfil aparece em listas de equipe e não guarda informação sensível.
-- A ESCRITA continua restrita ao dono do arquivo.
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Leitura pública das fotos de perfil.
DROP POLICY IF EXISTS "avatars_public_read" ON storage.objects;
CREATE POLICY "avatars_public_read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');

-- Escrita: cada usuário só grava o próprio arquivo, nomeado avatars/<uid>.jpg.
-- storage.foldername() devolve o caminho sem o arquivo; como o app grava em
-- 'avatars/<uid>.jpg', a checagem é feita sobre o nome do arquivo.
DROP POLICY IF EXISTS "avatars_owner_insert" ON storage.objects;
CREATE POLICY "avatars_owner_insert"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'avatars'
    AND name = 'avatars/' || auth.uid()::text || '.jpg'
  );

DROP POLICY IF EXISTS "avatars_owner_update" ON storage.objects;
CREATE POLICY "avatars_owner_update"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'avatars'
    AND name = 'avatars/' || auth.uid()::text || '.jpg'
  )
  WITH CHECK (
    bucket_id = 'avatars'
    AND name = 'avatars/' || auth.uid()::text || '.jpg'
  );

DROP POLICY IF EXISTS "avatars_owner_delete" ON storage.objects;
CREATE POLICY "avatars_owner_delete"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'avatars'
    AND name = 'avatars/' || auth.uid()::text || '.jpg'
  );
