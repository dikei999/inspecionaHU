-- ============================================================
-- InspecionaHU — Migration: Remover sistema de código USR-XXXX
-- Execute no SQL Editor do Supabase
-- ============================================================

-- 1. Remover trigger
DROP TRIGGER IF EXISTS trg_generate_profile_code ON profiles;

-- 2. Remover function
DROP FUNCTION IF EXISTS generate_profile_code();

-- 3. Remover coluna profile_code da tabela profiles
ALTER TABLE profiles DROP COLUMN IF EXISTS profile_code;

-- ============================================================
-- AÇÃO OBRIGATÓRIA FORA DO SQL EDITOR
-- ============================================================
-- Para que o cadastro funcione, desabilite a confirmação de e-mail:
--
-- Supabase Dashboard →
--   Authentication → Settings → Email →
--   desmarque "Enable email confirmations" → Save
--
-- Motivo: com confirmação ativa, signUp retorna session=null,
-- auth.uid() fica null e o INSERT em profiles é bloqueado pelo RLS
-- (policy profiles_insert_own exige id = auth.uid()).
-- ============================================================


-- ============================================================
-- Migration: Corrigir recursão infinita de RLS
--
-- PROBLEMA:
--   sectors_supervisor_update  → queries sector_access
--   sector_access_*            → queries sectors         → LOOP
--
--   sectors_inspector_select   → queries inspector_sectors
--   inspector_sectors_*        → queries sectors         → LOOP
--
-- SOLUÇÃO:
--   Criar funções SECURITY DEFINER que consultam as tabelas
--   sem passar pelo RLS, quebrando todos os ciclos.
-- ============================================================

-- ── 1. Funções auxiliares SECURITY DEFINER ──────────────────

-- Retorna hospital_id de um setor sem passar pelo RLS de sectors
CREATE OR REPLACE FUNCTION get_sector_hospital_id(p_sector_id UUID)
RETURNS UUID
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT hospital_id FROM sectors WHERE id = p_sector_id
$$;

-- Retorna owner_supervisor_id de um setor sem passar pelo RLS de sectors
CREATE OR REPLACE FUNCTION get_sector_owner_id(p_sector_id UUID)
RETURNS UUID
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT owner_supervisor_id FROM sectors WHERE id = p_sector_id
$$;

-- Retorna sector_ids onde o usuário atual tem can_edit=true
-- sem passar pelo RLS de sector_access
CREATE OR REPLACE FUNCTION get_my_editable_sector_ids()
RETURNS SETOF UUID
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT sector_id FROM sector_access
  WHERE supervisor_id = auth.uid() AND can_edit = true
$$;

-- Retorna sector_ids atribuídos ao inspetor atual
-- sem passar pelo RLS de inspector_sectors
CREATE OR REPLACE FUNCTION get_my_assigned_sector_ids()
RETURNS SETOF UUID
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT sector_id FROM inspector_sectors
  WHERE inspector_id = auth.uid() AND status = 'active'
$$;


-- ── 2. Corrigir policies de sectors ────────────────────────

-- Quebra: sectors_supervisor_update → sector_access → sectors
DROP POLICY IF EXISTS "sectors_supervisor_update" ON sectors;
CREATE POLICY "sectors_supervisor_update"
  ON sectors FOR UPDATE
  USING (
    get_my_role() = 'supervisor'
    AND hospital_id = get_my_hospital_id()
    AND (
      owner_supervisor_id = auth.uid()
      OR id IN (SELECT get_my_editable_sector_ids())
    )
  )
  WITH CHECK (
    get_my_role() = 'supervisor'
    AND hospital_id = get_my_hospital_id()
    AND (
      owner_supervisor_id = auth.uid()
      OR id IN (SELECT get_my_editable_sector_ids())
    )
  );

-- Quebra: sectors_inspector_select → inspector_sectors → sectors
DROP POLICY IF EXISTS "sectors_inspector_select" ON sectors;
CREATE POLICY "sectors_inspector_select"
  ON sectors FOR SELECT
  USING (
    get_my_role() = 'inspector'
    AND id IN (SELECT get_my_assigned_sector_ids())
  );


-- ── 3. Corrigir policies de sector_access ──────────────────

-- Quebra: sector_access_director_all → sectors → sector_access
DROP POLICY IF EXISTS "sector_access_director_all" ON sector_access;
CREATE POLICY "sector_access_director_all"
  ON sector_access FOR ALL
  USING (
    get_my_role() = 'director'
    AND get_sector_hospital_id(sector_id) = get_my_hospital_id()
  )
  WITH CHECK (
    get_my_role() = 'director'
    AND get_sector_hospital_id(sector_id) = get_my_hospital_id()
  );

-- Quebra: sector_access_supervisor_select → sectors → sector_access
DROP POLICY IF EXISTS "sector_access_supervisor_select" ON sector_access;
CREATE POLICY "sector_access_supervisor_select"
  ON sector_access FOR SELECT
  USING (
    get_my_role() = 'supervisor'
    AND (
      supervisor_id = auth.uid()
      OR get_sector_owner_id(sector_id) = auth.uid()
    )
  );

-- Quebra: sector_access_supervisor_insert → sectors → sector_access
DROP POLICY IF EXISTS "sector_access_supervisor_insert" ON sector_access;
CREATE POLICY "sector_access_supervisor_insert"
  ON sector_access FOR INSERT
  WITH CHECK (
    get_my_role() = 'supervisor'
    AND granted_by = auth.uid()
    AND get_sector_owner_id(sector_id) = auth.uid()
  );

-- Quebra: sector_access_supervisor_update → sectors → sector_access
DROP POLICY IF EXISTS "sector_access_supervisor_update" ON sector_access;
CREATE POLICY "sector_access_supervisor_update"
  ON sector_access FOR UPDATE
  USING (
    get_my_role() = 'supervisor'
    AND get_sector_owner_id(sector_id) = auth.uid()
  )
  WITH CHECK (
    get_my_role() = 'supervisor'
    AND get_sector_owner_id(sector_id) = auth.uid()
  );


-- ── 4. Corrigir policy profiles_select_director ────────────
--
-- BUG: a condição "hospital_id IS NULL" incluía o super_admin
-- (que tem hospital_id = NULL mas role = 'super_admin').
-- Deve ser "role IS NULL" para pegar só usuários sem vínculo.
DROP POLICY IF EXISTS "profiles_select_director" ON profiles;
CREATE POLICY "profiles_select_director"
  ON profiles FOR SELECT
  USING (
    get_my_role() = 'director'
    AND (
      hospital_id = get_my_hospital_id()
      OR role IS NULL
    )
  );


-- ── 6. Corrigir policy profiles_update_director ────────────
--
-- BUG CRÍTICO: a cláusula USING original exige
--   hospital_id = get_my_hospital_id()
-- mas perfis não vinculados têm hospital_id = NULL, então
-- o Director não consegue fazer o UPDATE de vinculação.
--
-- CORREÇÃO: USING permite UPDATE em perfis do hospital OU
-- em perfis sem vínculo (hospital_id IS NULL E role IS NULL).
-- WITH CHECK garante que após o UPDATE o perfil ficou no
-- hospital correto do Director (sem checar hospital_id IS NULL,
-- pois o UPDATE já define hospital_id = get_my_hospital_id()).
DROP POLICY IF EXISTS "profiles_update_director" ON profiles;
CREATE POLICY "profiles_update_director"
  ON profiles FOR UPDATE
  USING (
    get_my_role() = 'director'
    AND (
      hospital_id = get_my_hospital_id()
      OR (hospital_id IS NULL AND role IS NULL)
    )
  )
  WITH CHECK (
    get_my_role() = 'director'
    AND hospital_id = get_my_hospital_id()
  );


-- ── 5. Corrigir policies de inspector_sectors ──────────────

-- Quebra: inspector_sectors_director_all → sectors → inspector_sectors
DROP POLICY IF EXISTS "inspector_sectors_director_all" ON inspector_sectors;
CREATE POLICY "inspector_sectors_director_all"
  ON inspector_sectors FOR ALL
  USING (
    get_my_role() = 'director'
    AND get_sector_hospital_id(sector_id) = get_my_hospital_id()
  )
  WITH CHECK (
    get_my_role() = 'director'
    AND get_sector_hospital_id(sector_id) = get_my_hospital_id()
  );

-- Quebra: inspector_sectors_supervisor_select → sectors → inspector_sectors
DROP POLICY IF EXISTS "inspector_sectors_supervisor_select" ON inspector_sectors;
CREATE POLICY "inspector_sectors_supervisor_select"
  ON inspector_sectors FOR SELECT
  USING (
    get_my_role() = 'supervisor'
    AND get_sector_hospital_id(sector_id) = get_my_hospital_id()
  );

-- Quebra: inspector_sectors_supervisor_insert → sectors + sector_access → inspector_sectors
DROP POLICY IF EXISTS "inspector_sectors_supervisor_insert" ON inspector_sectors;
CREATE POLICY "inspector_sectors_supervisor_insert"
  ON inspector_sectors FOR INSERT
  WITH CHECK (
    get_my_role() = 'supervisor'
    AND assigned_by = auth.uid()
    AND (
      get_sector_owner_id(sector_id) = auth.uid()
      OR sector_id IN (SELECT get_my_editable_sector_ids())
    )
  );

-- Quebra: inspector_sectors_supervisor_update → sectors + sector_access → inspector_sectors
DROP POLICY IF EXISTS "inspector_sectors_supervisor_update" ON inspector_sectors;
CREATE POLICY "inspector_sectors_supervisor_update"
  ON inspector_sectors FOR UPDATE
  USING (
    get_my_role() = 'supervisor'
    AND (
      get_sector_owner_id(sector_id) = auth.uid()
      OR sector_id IN (SELECT get_my_editable_sector_ids())
    )
  )
  WITH CHECK (
    get_my_role() = 'supervisor'
    AND (
      get_sector_owner_id(sector_id) = auth.uid()
      OR sector_id IN (SELECT get_my_editable_sector_ids())
    )
  );
