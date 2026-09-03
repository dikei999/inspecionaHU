-- ============================================================
-- InspecionaHU — Reset do ambiente de DEMONSTRAÇÃO
-- Execute no SQL Editor do Supabase. Depois disso, o acionamento
-- fica disponível no Painel Demo do Super Admin.
--
-- ┌──────────────────────────────────────────────────────────┐
-- │ EXCEÇÃO ÚNICA À REGRA DE SOFT DELETE DO PROJETO.         │
-- │                                                          │
-- │ Todo o restante do sistema usa status='inactive' e NUNCA │
-- │ DELETE (ver CLAUDE.md → "Soft delete sempre").           │
-- │ reset_demo_data() é a única função que apaga linhas de   │
-- │ verdade, porque o ambiente de demonstração precisa       │
-- │ voltar ao zero entre apresentações — dados demo não têm  │
-- │ valor probatório nem exigência de rastreabilidade.       │
-- │                                                          │
-- │ NÃO use isto como precedente para dados reais: em        │
-- │ produção, remoção continua sendo soft delete.            │
-- │                                                          │
-- │ Salvaguardas: escopo travado no hospital de sigla        │
-- │ 'HU-DEMO' (o WHERE hospital_id é obrigatório em toda     │
-- │ instrução) e execução restrita a super_admin.            │
-- └──────────────────────────────────────────────────────────┘
--
-- PRESERVA: contas demo (profiles), o hospital HU-DEMO,
-- os templates globais da biblioteca NR-32 e o audit_log.
-- APAGA: setores, checklists, itens, tarefas, inspeções,
-- respostas e as fotos correspondentes no Storage.
-- ============================================================

DROP FUNCTION IF EXISTS reset_demo_data();

CREATE OR REPLACE FUNCTION reset_demo_data()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hospital_id UUID;

  v_fotos        INT := 0;
  v_respostas    INT := 0;
  v_inspecoes    INT := 0;
  v_tarefas      INT := 0;
  v_itens        INT := 0;
  v_checklists   INT := 0;
  v_vinculos     INT := 0;
  v_acessos      INT := 0;
  v_setores      INT := 0;
  v_notificacoes INT := 0;
BEGIN
  IF get_my_role() != 'super_admin' THEN
    RAISE EXCEPTION 'Apenas Super Admin pode resetar os dados de demonstração';
  END IF;

  -- Escopo travado: SEM hospital demo, nada é apagado.
  SELECT id INTO v_hospital_id FROM hospitals WHERE sigla = 'HU-DEMO';
  IF v_hospital_id IS NULL THEN
    RAISE EXCEPTION 'Hospital HU-DEMO não encontrado. Nada foi apagado.';
  END IF;

  -- ── 1. Fotos no Storage ────────────────────────────────────
  -- O path é {hospital_id}/{inspection_id}/{uuid}.jpg, então o
  -- prefixo do hospital demo isola tudo que será removido.
  DELETE FROM storage.objects
  WHERE bucket_id = 'inspection-photos'
    AND name LIKE v_hospital_id::text || '/%';
  GET DIAGNOSTICS v_fotos = ROW_COUNT;

  -- ── 2. Respostas de inspeção ───────────────────────────────
  DELETE FROM inspection_responses ir
  USING inspections i
  WHERE ir.inspection_id = i.id
    AND i.hospital_id = v_hospital_id;
  GET DIAGNOSTICS v_respostas = ROW_COUNT;

  -- ── 3. Inspeções ───────────────────────────────────────────
  DELETE FROM inspections WHERE hospital_id = v_hospital_id;
  GET DIAGNOSTICS v_inspecoes = ROW_COUNT;

  -- ── 4. Relatórios em cache (se a tabela tiver linhas demo) ──
  DELETE FROM reports WHERE hospital_id = v_hospital_id;

  -- ── 5. Tarefas ─────────────────────────────────────────────
  DELETE FROM tasks WHERE hospital_id = v_hospital_id;
  GET DIAGNOSTICS v_tarefas = ROW_COUNT;

  -- ── 6. Itens de checklist ──────────────────────────────────
  DELETE FROM checklist_items ci
  USING checklists c
  WHERE ci.checklist_id = c.id
    AND c.hospital_id = v_hospital_id;
  GET DIAGNOSTICS v_itens = ROW_COUNT;

  -- ── 7. Checklists ──────────────────────────────────────────
  DELETE FROM checklists WHERE hospital_id = v_hospital_id;
  GET DIAGNOSTICS v_checklists = ROW_COUNT;

  -- ── 8. Vínculos de inspetor e acessos compartilhados ───────
  DELETE FROM inspector_sectors isec
  USING sectors s
  WHERE isec.sector_id = s.id
    AND s.hospital_id = v_hospital_id;
  GET DIAGNOSTICS v_vinculos = ROW_COUNT;

  DELETE FROM sector_access sa
  USING sectors s
  WHERE sa.sector_id = s.id
    AND s.hospital_id = v_hospital_id;
  GET DIAGNOSTICS v_acessos = ROW_COUNT;

  -- Solicitações de acesso pendentes do hospital demo
  DELETE FROM access_requests WHERE hospital_id = v_hospital_id;

  -- ── 9. Setores ─────────────────────────────────────────────
  DELETE FROM sectors WHERE hospital_id = v_hospital_id;
  GET DIAGNOSTICS v_setores = ROW_COUNT;

  -- ── 10. Notificações das contas demo ───────────────────────
  DELETE FROM notifications n
  USING profiles p
  WHERE n.user_id = p.id
    AND p.hospital_id = v_hospital_id;
  GET DIAGNOSTICS v_notificacoes = ROW_COUNT;

  -- ── 11. Templates LOCAIS do hospital demo ──────────────────
  -- Os templates GLOBAIS da biblioteca NR-32 (hospital_id NULL)
  -- são preservados de propósito.
  DELETE FROM checklist_template_items ti
  USING checklist_templates t
  WHERE ti.template_id = t.id
    AND t.hospital_id = v_hospital_id;

  DELETE FROM checklist_templates WHERE hospital_id = v_hospital_id;

  RETURN json_build_object(
    'status', 'ok',
    'hospital', 'HU-DEMO',
    'fotos_storage', v_fotos,
    'respostas', v_respostas,
    'inspecoes', v_inspecoes,
    'tarefas', v_tarefas,
    'itens_checklist', v_itens,
    'checklists', v_checklists,
    'vinculos_inspetor', v_vinculos,
    'acessos_compartilhados', v_acessos,
    'setores', v_setores,
    'notificacoes', v_notificacoes,
    'preservados', 'contas demo, hospital HU-DEMO, templates globais NR-32'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION reset_demo_data() TO authenticated;
