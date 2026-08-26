-- ============================================================
-- InspecionaHU — Correção de seed_demo_data()
-- Execute manualmente no SQL Editor do Supabase, DEPOIS de
-- migration_demo_rpcs.sql já ter sido executado (precisa do
-- hospital HU-DEMO e das 4 contas demo).
--
-- MOTIVO:
--   A tela atribuir_tarefa_screen.dart só lista Inspetores que
--   têm registro em inspector_sectors para o setor selecionado.
--   O Inspetor demo estava sem esses vínculos, deixando o
--   dropdown de Inspetores sempre vazio.
--
-- Esta versão:
--   - reafirma explicitamente os 3 setores demo e seus donos
--     (Lavanderia com owner_supervisor_id = Supervisor demo)
--   - vincula o Inspetor demo aos 3 setores em inspector_sectors
--     (ON CONFLICT DO NOTHING — idempotente)
--   - mantém os 2 checklists de exemplo (um com item
--     requires_photo=true e criticality='critical')
--   - mantém as 2 tarefas do Inspetor demo (hoje / amanhã)
--   - cada bloco checa existência antes de inserir, então rodar
--     esta função várias vezes não duplica nada
-- ============================================================

DROP FUNCTION IF EXISTS seed_demo_data();

CREATE OR REPLACE FUNCTION seed_demo_data()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hospital_id UUID;
  v_director_id UUID;
  v_supervisor_id UUID;
  v_inspector_id UUID;

  v_sector_lavanderia UUID;
  v_sector_enfermaria UUID;
  v_sector_centro_cirurgico UUID;

  v_checklist_1 UUID;
  v_checklist_2 UUID;

  v_vinculos_criados INT := 0;
BEGIN
  IF get_my_role() != 'super_admin' THEN
    RAISE EXCEPTION 'Apenas Super Admin pode popular dados demo';
  END IF;

  -- ── Pré-requisitos: hospital e contas demo já provisionados ──
  SELECT id INTO v_hospital_id FROM hospitals WHERE sigla = 'HU-DEMO';
  IF v_hospital_id IS NULL THEN
    RAISE EXCEPTION 'Hospital HU-DEMO não existe. Rode provision_demo_accounts() primeiro.';
  END IF;

  SELECT id INTO v_director_id FROM profiles WHERE email = 'diretor@demo.com';
  SELECT id INTO v_supervisor_id FROM profiles WHERE email = 'supervisor@demo.com';
  SELECT id INTO v_inspector_id FROM profiles WHERE email = 'inspetor@demo.com';

  IF v_director_id IS NULL OR v_supervisor_id IS NULL OR v_inspector_id IS NULL THEN
    RAISE EXCEPTION 'Contas demo incompletas (Diretor/Supervisor/Inspetor). Rode provision_demo_accounts() primeiro.';
  END IF;

  -- Garante vínculo do Diretor ao hospital demo.
  UPDATE profiles SET hospital_id = v_hospital_id, role = 'director'
    WHERE id = v_director_id AND (hospital_id IS DISTINCT FROM v_hospital_id);

  -- Garante vínculo do Supervisor ao hospital demo.
  UPDATE profiles SET hospital_id = v_hospital_id, role = 'supervisor'
    WHERE id = v_supervisor_id AND (hospital_id IS DISTINCT FROM v_hospital_id);

  -- Garante vínculo do Inspetor ao hospital demo.
  UPDATE profiles SET hospital_id = v_hospital_id, role = 'inspector'
    WHERE id = v_inspector_id AND (hospital_id IS DISTINCT FROM v_hospital_id);

  -- ── Setores ────────────────────────────────────────────────
  -- Lavanderia: owner = Supervisor demo.
  SELECT id INTO v_sector_lavanderia FROM sectors
    WHERE hospital_id = v_hospital_id AND name = 'Lavanderia';
  IF v_sector_lavanderia IS NULL THEN
    INSERT INTO sectors (hospital_id, owner_supervisor_id, name, nr32_category, created_by, status)
    VALUES (v_hospital_id, v_supervisor_id, 'Lavanderia', 'Processamento de roupas', v_director_id, 'active')
    RETURNING id INTO v_sector_lavanderia;
  ELSE
    UPDATE sectors SET owner_supervisor_id = v_supervisor_id, status = 'active'
      WHERE id = v_sector_lavanderia;
  END IF;

  SELECT id INTO v_sector_enfermaria FROM sectors
    WHERE hospital_id = v_hospital_id AND name = 'Enfermaria';
  IF v_sector_enfermaria IS NULL THEN
    INSERT INTO sectors (hospital_id, owner_supervisor_id, name, nr32_category, created_by, status)
    VALUES (v_hospital_id, NULL, 'Enfermaria', 'Assistência à saúde', v_director_id, 'active')
    RETURNING id INTO v_sector_enfermaria;
  ELSE
    UPDATE sectors SET status = 'active' WHERE id = v_sector_enfermaria;
  END IF;

  SELECT id INTO v_sector_centro_cirurgico FROM sectors
    WHERE hospital_id = v_hospital_id AND name = 'Centro Cirúrgico';
  IF v_sector_centro_cirurgico IS NULL THEN
    INSERT INTO sectors (hospital_id, owner_supervisor_id, name, nr32_category, created_by, status)
    VALUES (v_hospital_id, NULL, 'Centro Cirúrgico', 'Assistência à saúde', v_director_id, 'active')
    RETURNING id INTO v_sector_centro_cirurgico;
  ELSE
    UPDATE sectors SET status = 'active' WHERE id = v_sector_centro_cirurgico;
  END IF;

  -- Confere que os 3 setores foram de fato resolvidos antes de
  -- seguir — evita inserir um NULL em inspector_sectors.sector_id
  -- (NOT NULL) e abortar a transação inteira sem mensagem clara.
  IF v_sector_lavanderia IS NULL OR v_sector_enfermaria IS NULL
     OR v_sector_centro_cirurgico IS NULL THEN
    RAISE EXCEPTION 'Falha ao criar/localizar um dos 3 setores demo.';
  END IF;

  -- ── Vínculo do Inspetor demo aos 3 setores ────────────────────
  INSERT INTO inspector_sectors (inspector_id, sector_id, assigned_by, status)
  VALUES
    (v_inspector_id, v_sector_lavanderia, v_director_id, 'active'),
    (v_inspector_id, v_sector_enfermaria, v_director_id, 'active'),
    (v_inspector_id, v_sector_centro_cirurgico, v_director_id, 'active')
  ON CONFLICT (inspector_id, sector_id)
    DO UPDATE SET status = 'active'
    WHERE inspector_sectors.status != 'active';

  GET DIAGNOSTICS v_vinculos_criados = ROW_COUNT;

  -- ── Checklist 1: Lavanderia (com item crítico + foto) ─────────
  SELECT id INTO v_checklist_1 FROM checklists
    WHERE sector_id = v_sector_lavanderia AND title = 'Inspeção NR-32 — Lavanderia';
  IF v_checklist_1 IS NULL THEN
    INSERT INTO checklists (sector_id, hospital_id, title, frequency, created_by, status)
    VALUES (v_sector_lavanderia, v_hospital_id, 'Inspeção NR-32 — Lavanderia', 'weekly', v_director_id, 'active')
    RETURNING id INTO v_checklist_1;

    INSERT INTO checklist_items (checklist_id, order_index, description, criticality, requires_photo, status)
    VALUES
      (v_checklist_1, 1, 'EPI disponível e em bom estado', 'normal', false, 'active'),
      (v_checklist_1, 2, 'Separação de roupa suja/limpa respeitada', 'normal', false, 'active'),
      (v_checklist_1, 3, 'Extintor de incêndio dentro da validade', 'critical', true, 'active'),
      (v_checklist_1, 4, 'Piso sem risco de escorregamento', 'normal', false, 'active'),
      (v_checklist_1, 5, 'Sinalização de risco biológico visível', 'normal', false, 'active');
  END IF;

  -- ── Checklist 2: Centro Cirúrgico (com item crítico + foto) ────
  SELECT id INTO v_checklist_2 FROM checklists
    WHERE sector_id = v_sector_centro_cirurgico AND title = 'Inspeção NR-32 — Centro Cirúrgico';
  IF v_checklist_2 IS NULL THEN
    INSERT INTO checklists (sector_id, hospital_id, title, frequency, created_by, status)
    VALUES (v_sector_centro_cirurgico, v_hospital_id, 'Inspeção NR-32 — Centro Cirúrgico', 'daily', v_director_id, 'active')
    RETURNING id INTO v_checklist_2;

    INSERT INTO checklist_items (checklist_id, order_index, description, criticality, requires_photo, status)
    VALUES
      (v_checklist_2, 1, 'Autoclave funcionando corretamente', 'critical', true, 'active'),
      (v_checklist_2, 2, 'Descarte de perfurocortantes adequado', 'normal', false, 'active'),
      (v_checklist_2, 3, 'Rota de fuga desobstruída', 'normal', false, 'active'),
      (v_checklist_2, 4, 'EPI disponível e em bom estado', 'normal', false, 'active');
  ELSE
    -- Checklist já existe: garante que pelo menos um item crítico
    -- com foto obrigatória está presente (idempotente via NOT EXISTS).
    INSERT INTO checklist_items (checklist_id, order_index, description, criticality, requires_photo, status)
    SELECT v_checklist_2, 1, 'Autoclave funcionando corretamente', 'critical', true, 'active'
    WHERE NOT EXISTS (
      SELECT 1 FROM checklist_items
      WHERE checklist_id = v_checklist_2 AND criticality = 'critical'
    );
  END IF;

  -- ── Tarefas do Inspetor demo ───────────────────────────────────
  INSERT INTO tasks (checklist_id, sector_id, hospital_id, inspector_id, assigned_by, due_date, status)
  SELECT v_checklist_1, v_sector_lavanderia, v_hospital_id, v_inspector_id, v_director_id, CURRENT_DATE, 'pending'
  WHERE NOT EXISTS (
    SELECT 1 FROM tasks
    WHERE checklist_id = v_checklist_1 AND inspector_id = v_inspector_id AND due_date = CURRENT_DATE
  );

  INSERT INTO tasks (checklist_id, sector_id, hospital_id, inspector_id, assigned_by, due_date, status)
  SELECT v_checklist_2, v_sector_centro_cirurgico, v_hospital_id, v_inspector_id, v_director_id, CURRENT_DATE + 1, 'pending'
  WHERE NOT EXISTS (
    SELECT 1 FROM tasks
    WHERE checklist_id = v_checklist_2 AND inspector_id = v_inspector_id AND due_date = CURRENT_DATE + 1
  );

  RETURN json_build_object(
    'status', 'ok',
    'hospital_id', v_hospital_id,
    'setores', json_build_array(v_sector_lavanderia, v_sector_enfermaria, v_sector_centro_cirurgico),
    'inspector_sectors_afetados', v_vinculos_criados
  );
END;
$$;

GRANT EXECUTE ON FUNCTION seed_demo_data() TO authenticated;
