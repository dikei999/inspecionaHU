-- ============================================================
-- InspecionaHU — RPCs de contas/dados DEMO (ferramenta de dev)
-- Execute manualmente no SQL Editor do Supabase.
-- NÃO faz parte do fluxo de produção — só afeta contas @demo.com.
--
-- Cria 3 functions:
--   1. provision_demo_accounts() — cria hospital HU-DEMO + 4 contas
--   2. reset_demo_passwords()    — reseta senha das 4 contas p/ demo1234
--   3. seed_demo_data()          — popula setores/checklists/tarefas
--
-- Todas SECURITY DEFINER, search_path = public, e restritas a
-- get_my_role() = 'super_admin' (exceto provision_demo_accounts,
-- que também exige super_admin — só quem já está logado como tal
-- deve poder criar contas).
-- ============================================================

-- pgcrypto fornece crypt()/gen_salt(), usadas para hashear a
-- senha demo do mesmo jeito que o Supabase Auth faz.
-- Normalmente já vem habilitada por padrão no projeto.
CREATE EXTENSION IF NOT EXISTS pgcrypto;


-- ============================================================
-- 1. provision_demo_accounts()
-- Cria o hospital HU-DEMO (se não existir) e as 4 contas fixas
-- em auth.users + profiles (se não existirem). Idempotente.
-- ============================================================
CREATE OR REPLACE FUNCTION provision_demo_accounts()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hospital_id UUID;
  v_created INT := 0;
  v_existing INT := 0;
  v_accounts JSONB := '[
    {"email": "superadmin@demo.com", "name": "Super Admin Demo", "role": "super_admin", "cpf": "11111111030"},
    {"email": "diretor@demo.com",    "name": "Diretor Demo",     "role": "director",    "cpf": "22222222060"},
    {"email": "supervisor@demo.com", "name": "Supervisor Demo",  "role": "supervisor",  "cpf": "33333333090"},
    {"email": "inspetor@demo.com",   "name": "Inspetor Demo",    "role": "inspector",   "cpf": "44444444010"}
  ]'::jsonb;
  v_acc JSONB;
  v_user_id UUID;
  v_needs_hospital BOOLEAN;
BEGIN
  IF get_my_role() != 'super_admin' THEN
    RAISE EXCEPTION 'Apenas Super Admin pode provisionar contas demo';
  END IF;

  -- Hospital HU-DEMO
  SELECT id INTO v_hospital_id FROM hospitals WHERE sigla = 'HU-DEMO';
  IF v_hospital_id IS NULL THEN
    INSERT INTO hospitals (name, sigla, city, state, status)
    VALUES ('Hospital Universitário Demo', 'HU-DEMO', 'Teresina', 'PI', 'active')
    RETURNING id INTO v_hospital_id;
  END IF;

  FOR v_acc IN SELECT * FROM jsonb_array_elements(v_accounts)
  LOOP
    SELECT id INTO v_user_id FROM auth.users WHERE email = v_acc->>'email';

    IF v_user_id IS NOT NULL THEN
      -- Conta já existe: garante que o profile também existe e está correto.
      v_existing := v_existing + 1;
      v_needs_hospital := (v_acc->>'role') != 'super_admin';
      INSERT INTO profiles (id, hospital_id, full_name, email, cpf, role, status)
      VALUES (
        v_user_id,
        CASE WHEN v_needs_hospital THEN v_hospital_id ELSE NULL END,
        v_acc->>'name',
        v_acc->>'email',
        v_acc->>'cpf',
        v_acc->>'role',
        'active'
      )
      ON CONFLICT (id) DO UPDATE SET
        hospital_id = EXCLUDED.hospital_id,
        role        = EXCLUDED.role,
        status      = 'active';
      CONTINUE;
    END IF;

    -- Cria em auth.users (senha inicial: demo1234)
    v_user_id := gen_random_uuid();
    INSERT INTO auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, confirmation_token, recovery_token,
      email_change_token_new, email_change,
      raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000000',
      v_user_id,
      'authenticated',
      'authenticated',
      v_acc->>'email',
      crypt('demo1234', gen_salt('bf')),
      now(),
      '', '', '', '',
      '{"provider":"email","providers":["email"]}',
      '{}',
      now(), now()
    );

    v_needs_hospital := (v_acc->>'role') != 'super_admin';
    INSERT INTO profiles (id, hospital_id, full_name, email, cpf, role, status)
    VALUES (
      v_user_id,
      CASE WHEN v_needs_hospital THEN v_hospital_id ELSE NULL END,
      v_acc->>'name',
      v_acc->>'email',
      v_acc->>'cpf',
      v_acc->>'role',
      'active'
    );

    v_created := v_created + 1;
  END LOOP;

  RETURN json_build_object('created', v_created, 'existing', v_existing);
END;
$$;

GRANT EXECUTE ON FUNCTION provision_demo_accounts() TO authenticated;


-- ============================================================
-- 2. reset_demo_passwords()
-- Reseta a senha das 4 contas @demo.com para 'demo1234'.
-- ============================================================
CREATE OR REPLACE FUNCTION reset_demo_passwords()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  IF get_my_role() != 'super_admin' THEN
    RAISE EXCEPTION 'Apenas Super Admin pode resetar senhas demo';
  END IF;

  UPDATE auth.users
  SET encrypted_password = crypt('demo1234', gen_salt('bf')),
      updated_at = now()
  WHERE email IN (
    'superadmin@demo.com', 'diretor@demo.com',
    'supervisor@demo.com', 'inspetor@demo.com'
  );

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION reset_demo_passwords() TO authenticated;


-- ============================================================
-- 3. seed_demo_data()
-- Popula setores, checklist global, checklists locais + itens,
-- vínculos e tarefas de exemplo no HU-DEMO. Idempotente:
-- verifica existência antes de inserir (não duplica ao rodar
-- de novo).
-- ============================================================
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

  v_template_id UUID;

  v_checklist_1 UUID;
  v_checklist_2 UUID;

  v_task_hoje UUID;
  v_task_amanha UUID;
BEGIN
  IF get_my_role() != 'super_admin' THEN
    RAISE EXCEPTION 'Apenas Super Admin pode popular dados demo';
  END IF;

  SELECT id INTO v_hospital_id FROM hospitals WHERE sigla = 'HU-DEMO';
  IF v_hospital_id IS NULL THEN
    RAISE EXCEPTION 'Hospital HU-DEMO não existe. Rode provision_demo_accounts() primeiro.';
  END IF;

  SELECT id INTO v_director_id FROM profiles WHERE email = 'diretor@demo.com';
  SELECT id INTO v_supervisor_id FROM profiles WHERE email = 'supervisor@demo.com';
  SELECT id INTO v_inspector_id FROM profiles WHERE email = 'inspetor@demo.com';

  IF v_director_id IS NULL OR v_supervisor_id IS NULL OR v_inspector_id IS NULL THEN
    RAISE EXCEPTION 'Contas demo incompletas. Rode provision_demo_accounts() primeiro.';
  END IF;

  -- Garante vínculo do Diretor ao hospital demo.
  UPDATE profiles SET hospital_id = v_hospital_id, role = 'director'
    WHERE id = v_director_id AND (hospital_id IS DISTINCT FROM v_hospital_id);

  -- ── Setores ────────────────────────────────────────────────
  SELECT id INTO v_sector_lavanderia FROM sectors
    WHERE hospital_id = v_hospital_id AND name = 'Lavanderia';
  IF v_sector_lavanderia IS NULL THEN
    INSERT INTO sectors (hospital_id, owner_supervisor_id, name, nr32_category, created_by, status)
    VALUES (v_hospital_id, v_supervisor_id, 'Lavanderia', 'Processamento de roupas', v_director_id, 'active')
    RETURNING id INTO v_sector_lavanderia;
  ELSE
    UPDATE sectors SET owner_supervisor_id = v_supervisor_id WHERE id = v_sector_lavanderia;
  END IF;

  SELECT id INTO v_sector_enfermaria FROM sectors
    WHERE hospital_id = v_hospital_id AND name = 'Enfermaria';
  IF v_sector_enfermaria IS NULL THEN
    INSERT INTO sectors (hospital_id, owner_supervisor_id, name, nr32_category, created_by, status)
    VALUES (v_hospital_id, NULL, 'Enfermaria', 'Assistência à saúde', v_director_id, 'active')
    RETURNING id INTO v_sector_enfermaria;
  END IF;

  SELECT id INTO v_sector_centro_cirurgico FROM sectors
    WHERE hospital_id = v_hospital_id AND name = 'Centro Cirúrgico';
  IF v_sector_centro_cirurgico IS NULL THEN
    INSERT INTO sectors (hospital_id, owner_supervisor_id, name, nr32_category, created_by, status)
    VALUES (v_hospital_id, NULL, 'Centro Cirúrgico', 'Assistência à saúde', v_director_id, 'active')
    RETURNING id INTO v_sector_centro_cirurgico;
  END IF;

  -- ── Vínculos do Inspetor aos 3 setores ───────────────────────
  INSERT INTO inspector_sectors (inspector_id, sector_id, assigned_by, status)
  SELECT v_inspector_id, s.id, v_director_id, 'active'
  FROM (VALUES (v_sector_lavanderia), (v_sector_enfermaria), (v_sector_centro_cirurgico)) AS s(id)
  ON CONFLICT (inspector_id, sector_id) DO NOTHING;

  -- ── Template global NR-32 (se não existir nenhum) ────────────
  SELECT id INTO v_template_id FROM checklist_templates
    WHERE scope = 'global' AND title = 'Template NR-32 Demo';
  IF v_template_id IS NULL THEN
    INSERT INTO checklist_templates (hospital_id, title, description, nr32_category, scope, created_by, status)
    VALUES (NULL, 'Template NR-32 Demo', 'Template de exemplo para testes', 'Geral', 'global', v_director_id, 'active')
    RETURNING id INTO v_template_id;

    INSERT INTO checklist_template_items (template_id, order_index, description, criticality, requires_photo)
    VALUES
      (v_template_id, 1, 'EPI disponível e em bom estado', 'normal', false),
      (v_template_id, 2, 'Sinalização de risco biológico visível', 'normal', false),
      (v_template_id, 3, 'Extintor de incêndio dentro da validade', 'critical', true),
      (v_template_id, 4, 'Rota de fuga desobstruída', 'normal', false);
  END IF;

  -- ── Checklist 1: Lavanderia ───────────────────────────────────
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

  -- ── Checklist 2: Centro Cirúrgico ─────────────────────────────
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
  END IF;

  -- ── Tarefas do Inspetor ────────────────────────────────────────
  SELECT id INTO v_task_hoje FROM tasks
    WHERE checklist_id = v_checklist_1 AND inspector_id = v_inspector_id AND due_date = CURRENT_DATE;
  IF v_task_hoje IS NULL THEN
    INSERT INTO tasks (checklist_id, sector_id, hospital_id, inspector_id, assigned_by, due_date, status)
    VALUES (v_checklist_1, v_sector_lavanderia, v_hospital_id, v_inspector_id, v_director_id, CURRENT_DATE, 'pending');
  END IF;

  SELECT id INTO v_task_amanha FROM tasks
    WHERE checklist_id = v_checklist_2 AND inspector_id = v_inspector_id AND due_date = CURRENT_DATE + 1;
  IF v_task_amanha IS NULL THEN
    INSERT INTO tasks (checklist_id, sector_id, hospital_id, inspector_id, assigned_by, due_date, status)
    VALUES (v_checklist_2, v_sector_centro_cirurgico, v_hospital_id, v_inspector_id, v_director_id, CURRENT_DATE + 1, 'pending');
  END IF;

  RETURN json_build_object('status', 'ok', 'hospital_id', v_hospital_id);
END;
$$;

GRANT EXECUTE ON FUNCTION seed_demo_data() TO authenticated;
