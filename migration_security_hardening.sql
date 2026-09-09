-- ============================================================
-- InspecionaHU — Correções de segurança da auditoria (set/2026)
--
-- Origem: docs/AUDITORIA_SEGURANCA.md. Cada bloco abaixo fecha uma
-- falha CONFIRMADA por teste contra o banco real, com a anon key
-- pública — ou seja, explorável por qualquer pessoa com o APK.
--
-- Idempotente: pode rodar mais de uma vez.
-- NÃO altera nenhuma regra de negócio, nenhuma cor, nenhum dado.
-- Executar no SQL Editor DEPOIS de supabase_setup.sql.
-- ============================================================


-- ============================================================
-- 1. ESCALONAMENTO DE PRIVILÉGIO (crítico)
--
-- Falha: profiles_update_own permitia ao usuário atualizar o
-- PRÓPRIO perfil sem restringir QUAIS colunas. Como `role` e
-- `hospital_id` moram em profiles, um Inspetor executava
--   PATCH /rest/v1/profiles?id=eq.<seu id>  {"role":"director"}
-- e virava Diretor do hospital. Confirmado no teste: passou com
-- status 200, tanto para Inspetor quanto para Supervisor.
--
-- Correção: a policy continua permitindo editar o próprio
-- perfil, mas um trigger impede que role, hospital_id e status
-- sejam alterados por quem não é Diretor ou Super Admin. Esses
-- três campos são de VINCULAÇÃO, feita pelo nível acima — nunca
-- pelo próprio usuário.
-- ============================================================

CREATE OR REPLACE FUNCTION fn_protege_campos_de_vinculo()
RETURNS TRIGGER
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  meu_papel TEXT;
BEGIN
  SELECT role INTO meu_papel FROM profiles WHERE id = auth.uid();

  -- Diretor e Super Admin vinculam e desativam: é a função deles.
  IF meu_papel IN ('director', 'super_admin') THEN
    RETURN NEW;
  END IF;

  -- Qualquer outro (inclusive o próprio dono da linha) não muda
  -- papel, hospital nem situação. Falha fechada: em vez de negar
  -- o UPDATE inteiro, preserva o valor antigo desses três campos,
  -- para que editar nome/telefone/foto continue funcionando.
  NEW.role        := OLD.role;
  NEW.hospital_id := OLD.hospital_id;
  NEW.status      := OLD.status;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protege_campos_de_vinculo ON profiles;
CREATE TRIGGER trg_protege_campos_de_vinculo
  BEFORE UPDATE ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION fn_protege_campos_de_vinculo();


-- ============================================================
-- 2. SUPERVISOR VALIDANDO RELATÓRIO (alto)
--
-- Regra do projeto: quem valida é o Diretor. A RLS, porém, dava
-- ao Supervisor UPDATE amplo em inspections do hospital, e o
-- teste confirmou: o Supervisor mudou overall_status para
-- 'validated' direto pela API. Só a interface barrava.
--
-- Correção: a policy do Supervisor continua existindo (ele
-- precisa de UPDATE para outras operações do setor), mas um
-- trigger reserva a TRANSIÇÃO para 'validated' a Diretor.
-- ============================================================

CREATE OR REPLACE FUNCTION fn_so_diretor_valida()
RETURNS TRIGGER
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  meu_papel TEXT;
BEGIN
  -- Só interessa quando a linha está VIRANDO validada agora.
  IF NEW.overall_status = 'validated'
     AND COALESCE(OLD.overall_status, '') <> 'validated' THEN
    SELECT role INTO meu_papel FROM profiles WHERE id = auth.uid();
    IF meu_papel IS DISTINCT FROM 'director' THEN
      RAISE EXCEPTION 'Apenas o Diretor pode validar um relatório.'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_so_diretor_valida ON inspections;
CREATE TRIGGER trg_so_diretor_valida
  BEFORE UPDATE ON inspections
  FOR EACH ROW
  EXECUTE FUNCTION fn_so_diretor_valida();


-- ============================================================
-- 3. STORAGE SEM ISOLAMENTO ENTRE HOSPITAIS (crítico)
--
-- Falha: as policies do bucket inspection-photos exigiam apenas
-- "estar autenticado com um papel conhecido". Não olhavam o
-- hospital. Confirmado no teste: o Inspetor do HU-DEMO gravou E
-- apagou um arquivo dentro da pasta do HU-UFPI.
--
-- O path já é {hospital_id}/{inspection_id}/{uuid}.jpg, então a
-- primeira pasta do caminho é a chave do isolamento:
--   (storage.foldername(name))[1] = hospital do usuário.
--
-- Super Admin fica de fora do bucket: ele não acessa dado
-- operacional (regra do projeto), e foto de inspeção é dado
-- operacional.
-- ============================================================

DROP POLICY IF EXISTS "inspection_photos_insert" ON storage.objects;
DROP POLICY IF EXISTS "inspection_photos_select" ON storage.objects;
DROP POLICY IF EXISTS "inspection_photos_update" ON storage.objects;
DROP POLICY IF EXISTS "inspection_photos_delete" ON storage.objects;

CREATE POLICY "inspection_photos_insert"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'inspection-photos'
    AND get_my_role() IN ('inspector', 'director', 'supervisor')
    AND (storage.foldername(name))[1] = get_my_hospital_id()::text
  );

CREATE POLICY "inspection_photos_select"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'inspection-photos'
    AND get_my_role() IN ('inspector', 'director', 'supervisor')
    AND (storage.foldername(name))[1] = get_my_hospital_id()::text
  );

CREATE POLICY "inspection_photos_update"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'inspection-photos'
    AND get_my_role() IN ('inspector', 'director', 'supervisor')
    AND (storage.foldername(name))[1] = get_my_hospital_id()::text
  )
  WITH CHECK (
    bucket_id = 'inspection-photos'
    AND get_my_role() IN ('inspector', 'director', 'supervisor')
    AND (storage.foldername(name))[1] = get_my_hospital_id()::text
  );

-- DELETE: só Diretor. Apagar evidência de inspeção não é operação
-- de rotina do Inspetor, e a foto é a prova documental da NC.
CREATE POLICY "inspection_photos_delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'inspection-photos'
    AND get_my_role() = 'director'
    AND (storage.foldername(name))[1] = get_my_hospital_id()::text
  );


-- ============================================================
-- 4. audit_log COM hospital_id FORJÁVEL (médio)
--
-- Falha: audit_log_insert_own só exigia user_id = auth.uid().
-- O hospital_id vinha do cliente, então era possível gravar
-- registro carimbado com o hospital de outra unidade, poluindo
-- o log de quem não tem como perceber.
--
-- Correção: a linha tem de ser do hospital de quem escreve.
-- ============================================================

DROP POLICY IF EXISTS "audit_log_insert_own" ON audit_log;
CREATE POLICY "audit_log_insert_own"
  ON audit_log FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    AND (
      hospital_id = get_my_hospital_id()
      -- Super Admin não tem hospital: age fora de unidade.
      OR (hospital_id IS NULL AND get_my_role() = 'super_admin')
    )
  );


-- ============================================================
-- 5. INSPETOR LENDO O audit_log INTEIRO (médio)
--
-- Falha: não havia policy de SELECT para o Inspetor em
-- audit_log, mas o teste leu 5 linhas com o token dele. A causa
-- é a policy audit_log_director_select / _supervisor_select
-- combinada com o papel elevado do teste anterior — ainda assim,
-- o log expõe quem fez o quê no hospital inteiro e não é
-- informação de Inspetor.
--
-- Correção: torna explícito que o Inspetor lê apenas os próprios
-- registros, em vez de depender da ausência de policy.
-- ============================================================

DROP POLICY IF EXISTS "audit_log_inspector_select" ON audit_log;
CREATE POLICY "audit_log_inspector_select"
  ON audit_log FOR SELECT
  USING (
    get_my_role() = 'inspector'
    AND user_id = auth.uid()
  );


-- ============================================================
-- 6. reports COM hospital_id FORJÁVEL PELO INSPETOR (médio)
--
-- Falha: reports_inspector_insert validava a inspeção, mas não o
-- hospital_id da linha de reports, que vem do cliente. Um
-- relatório podia ser carimbado com outro hospital e entrar nos
-- indicadores de uma unidade alheia.
-- ============================================================

DROP POLICY IF EXISTS "reports_inspector_insert" ON reports;
CREATE POLICY "reports_inspector_insert"
  ON reports FOR INSERT
  WITH CHECK (
    get_my_role() = 'inspector'
    AND hospital_id = get_my_hospital_id()
    AND inspection_id IN (
      SELECT id FROM inspections WHERE inspector_id = auth.uid()
    )
  );


-- ============================================================
-- 7. inspections CRIADA COM hospital_id DE OUTRA UNIDADE (médio)
--
-- Mesma classe do item 6: o INSERT do Inspetor não checava o
-- hospital da linha.
-- ============================================================

DROP POLICY IF EXISTS "inspections_inspector_insert" ON inspections;
CREATE POLICY "inspections_inspector_insert"
  ON inspections FOR INSERT
  WITH CHECK (
    get_my_role() = 'inspector'
    AND inspector_id = auth.uid()
    AND hospital_id = get_my_hospital_id()
  );


-- ============================================================
-- 8. VÍNCULO DE INSPETOR DE OUTRO HOSPITAL (médio)
--
-- Falha: inspector_sectors_supervisor_insert conferia o setor,
-- mas não o hospital do inspetor vinculado — era possível
-- vincular alguém de outra unidade a um setor local.
-- ============================================================

DROP POLICY IF EXISTS "inspector_sectors_supervisor_insert" ON inspector_sectors;
CREATE POLICY "inspector_sectors_supervisor_insert"
  ON inspector_sectors FOR INSERT
  WITH CHECK (
    get_my_role() = 'supervisor'
    AND assigned_by = auth.uid()
    AND inspector_id IN (
      SELECT id FROM profiles WHERE hospital_id = get_my_hospital_id()
    )
    AND sector_id IN (
      SELECT id FROM sectors WHERE owner_supervisor_id = auth.uid()
      UNION
      SELECT sector_id FROM sector_access
      WHERE supervisor_id = auth.uid() AND can_edit = true
    )
  );


-- ============================================================
-- 9. PEDIDO DE ACESSO SEM CHECAR HOSPITAL (baixo)
--
-- access_requests_supervisor_insert só exigia requester_id =
-- auth.uid(). O setor pedido podia ser de outra unidade.
-- ============================================================

DROP POLICY IF EXISTS "access_requests_supervisor_insert" ON access_requests;
CREATE POLICY "access_requests_supervisor_insert"
  ON access_requests FOR INSERT
  WITH CHECK (
    get_my_role() = 'supervisor'
    AND requester_id = auth.uid()
    AND sector_id IN (
      SELECT id FROM sectors WHERE hospital_id = get_my_hospital_id()
    )
  );


-- ============================================================
-- 10. CONFERÊNCIA
-- ============================================================

DO $$
BEGIN
  RAISE NOTICE 'Correções de segurança aplicadas.';
  RAISE NOTICE 'Confira com: SELECT tablename, policyname FROM pg_policies';
  RAISE NOTICE '  WHERE schemaname IN (''public'',''storage'') ORDER BY 1,2;';
END $$;
