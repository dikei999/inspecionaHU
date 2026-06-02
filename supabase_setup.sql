-- ============================================================
-- InspecionaHU — Supabase Setup SQL
-- Baseado nas seções 7 (Tabelas) e 14 (RLS) do CLAUDE.md
-- Projeto piloto: HU-UFPI / Rede EBSERH
--
-- INSTRUÇÕES:
--   1. Acesse o SQL Editor do seu projeto Supabase
--   2. Cole e execute este arquivo inteiro de uma vez
--   3. Após executar, configure o Storage bucket manualmente:
--      - Nome: inspection-photos
--      - Visibilidade: Private (acesso via URLs assinadas)
-- ============================================================


-- ============================================================
-- PARTE 0-A: FUNÇÕES AUXILIARES (SECURITY DEFINER)
--
-- Usadas internamente pelas políticas RLS para buscar role e
-- hospital_id do usuário atual SEM causar recursão na tabela
-- profiles (que também tem RLS habilitado).
-- SECURITY DEFINER + SET search_path = public = bypass de RLS.
-- ============================================================

CREATE OR REPLACE FUNCTION get_my_role()
RETURNS TEXT
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT role FROM profiles WHERE id = auth.uid()
$$;

CREATE OR REPLACE FUNCTION get_my_hospital_id()
RETURNS UUID
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT hospital_id FROM profiles WHERE id = auth.uid()
$$;


-- ============================================================
-- PARTE 0-B: GERAÇÃO AUTOMÁTICA DE profile_code (USR-XXXX)
--
-- Trigger em profiles: ao inserir um novo perfil, gera um
-- código único no formato USR-XXXX (4 dígitos aleatórios).
-- Regra seção 5.1: código verificado único antes de salvar.
-- ============================================================

CREATE OR REPLACE FUNCTION generate_profile_code()
RETURNS TRIGGER
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  candidate TEXT;
BEGIN
  LOOP
    candidate := 'USR-' || LPAD(FLOOR(RANDOM() * 10000)::TEXT, 4, '0');
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM profiles WHERE profile_code = candidate
    );
  END LOOP;
  NEW.profile_code := candidate;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_generate_profile_code
  BEFORE INSERT ON profiles
  FOR EACH ROW
  WHEN (NEW.profile_code IS NULL OR NEW.profile_code = '')
  EXECUTE FUNCTION generate_profile_code();


-- ============================================================
-- PARTE 1: CREATE TABLE
-- Ordem: respeita dependências de chaves estrangeiras
-- Soft delete: campo status ('active' | 'inactive') em todas
-- NUNCA usar DELETE — sempre UPDATE status = 'inactive'
-- ============================================================

-- -----------------------------------------------------------
-- 1. hospitals
-- Tabela global (sem hospital_id). Acessível pelo Super Admin.
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS hospitals (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT        NOT NULL,
  sigla      TEXT        NOT NULL,
  city       TEXT        NOT NULL,
  state      TEXT        NOT NULL CHECK (char_length(state) = 2),
  status     TEXT        NOT NULL DEFAULT 'active'
                         CHECK (status IN ('active', 'inactive')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------
-- 2. profiles
-- Usuários do sistema. hospital_id = NULL antes da vinculação.
-- role = NULL antes da vinculação.
-- profile_code gerado automaticamente pelo trigger acima.
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS profiles (
  id           UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  hospital_id  UUID        REFERENCES hospitals(id),
  full_name    TEXT        NOT NULL,
  email        TEXT        NOT NULL UNIQUE,
  cpf          TEXT        NOT NULL UNIQUE CHECK (char_length(cpf) = 11),
  role         TEXT        CHECK (role IN ('super_admin', 'director', 'supervisor', 'inspector')),
  profile_code TEXT        NOT NULL UNIQUE DEFAULT '',
  photo_url    TEXT,
  status       TEXT        NOT NULL DEFAULT 'active'
                           CHECK (status IN ('active', 'inactive')),
  last_access  TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------
-- 3. sectors
-- owner_supervisor_id = NULL se criado pelo Director.
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS sectors (
  id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  hospital_id          UUID        NOT NULL REFERENCES hospitals(id),
  owner_supervisor_id  UUID        REFERENCES profiles(id),
  name                 TEXT        NOT NULL,
  description          TEXT,
  nr32_category        TEXT,
  status               TEXT        NOT NULL DEFAULT 'active'
                                   CHECK (status IN ('active', 'inactive')),
  created_by           UUID        NOT NULL REFERENCES profiles(id),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------
-- 4. inspector_sectors
-- Vinculação M:N entre Inspetor e Setor.
-- Inspetor pode estar em múltiplos setores (regra seção 4.4).
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS inspector_sectors (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  inspector_id UUID        NOT NULL REFERENCES profiles(id),
  sector_id    UUID        NOT NULL REFERENCES sectors(id),
  assigned_by  UUID        NOT NULL REFERENCES profiles(id),
  status       TEXT        NOT NULL DEFAULT 'active'
                           CHECK (status IN ('active', 'inactive')),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (inspector_id, sector_id)
);

-- -----------------------------------------------------------
-- 5. sector_access
-- Acesso compartilhado entre Supervisores (regra seção 6.8).
-- can_view e can_edit são independentes.
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS sector_access (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  sector_id     UUID        NOT NULL REFERENCES sectors(id),
  supervisor_id UUID        NOT NULL REFERENCES profiles(id),
  can_view      BOOLEAN     NOT NULL DEFAULT false,
  can_edit      BOOLEAN     NOT NULL DEFAULT false,
  granted_by    UUID        NOT NULL REFERENCES profiles(id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (sector_id, supervisor_id)
);

-- -----------------------------------------------------------
-- 6. checklist_templates
-- scope = 'global' → hospital_id IS NULL (Super Admin)
-- scope = 'local'  → hospital_id = hospital do Director
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS checklist_templates (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  hospital_id   UUID        REFERENCES hospitals(id),
  title         TEXT        NOT NULL,
  description   TEXT,
  nr32_category TEXT,
  scope         TEXT        NOT NULL CHECK (scope IN ('global', 'local')),
  status        TEXT        NOT NULL DEFAULT 'active'
                            CHECK (status IN ('active', 'inactive')),
  created_by    UUID        NOT NULL REFERENCES profiles(id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- global templates devem ter hospital_id NULL; locais devem ter hospital_id preenchido
  CONSTRAINT chk_template_scope CHECK (
    (scope = 'global' AND hospital_id IS NULL)
    OR (scope = 'local' AND hospital_id IS NOT NULL)
  )
);

-- -----------------------------------------------------------
-- 7. checklist_template_items
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS checklist_template_items (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id    UUID        NOT NULL REFERENCES checklist_templates(id),
  order_index    INTEGER     NOT NULL,
  description    TEXT        NOT NULL,
  nr32_reference TEXT,
  criticality    TEXT        NOT NULL DEFAULT 'normal'
                             CHECK (criticality IN ('normal', 'critical')),
  requires_photo BOOLEAN     NOT NULL DEFAULT false,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------
-- 8. checklists
-- frequency é REFERÊNCIA INFORMATIVA — tarefas são manuais
-- (regras seção 6.9 e nota da tabela 7.8)
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS checklists (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  sector_id    UUID        NOT NULL REFERENCES sectors(id),
  hospital_id  UUID        NOT NULL REFERENCES hospitals(id),
  title        TEXT        NOT NULL,
  frequency    TEXT        NOT NULL
                           CHECK (frequency IN ('daily', 'weekly', 'biweekly', 'monthly', 'custom')),
  custom_days  TEXT[],               -- ['mon','wed','fri'] — só quando frequency='custom'
  period_start DATE,
  period_end   DATE,
  status       TEXT        NOT NULL DEFAULT 'active'
                           CHECK (status IN ('active', 'inactive')),
  created_by   UUID        NOT NULL REFERENCES profiles(id),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------
-- 9. checklist_items
-- requires_observation REMOVIDO (regra fixa: NC = obs obrigatória)
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS checklist_items (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  checklist_id     UUID        NOT NULL REFERENCES checklists(id),
  order_index      INTEGER     NOT NULL,
  description      TEXT        NOT NULL,
  nr32_reference   TEXT,
  criticality      TEXT        NOT NULL DEFAULT 'normal'
                               CHECK (criticality IN ('normal', 'critical')),
  requires_photo   BOOLEAN     NOT NULL DEFAULT false,
  status           TEXT        NOT NULL DEFAULT 'active'
                               CHECK (status IN ('active', 'inactive')),
  last_modified_at TIMESTAMPTZ,
  last_modified_by UUID        REFERENCES profiles(id),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------
-- 10. tasks
-- overdue NÃO é status — é calculado no app:
--   due_date < now() AND status NOT IN ('submitted', 'validated')
-- recurrence REMOVIDO — atribuição manual (regra 6.9)
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS tasks (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  checklist_id UUID        NOT NULL REFERENCES checklists(id),
  sector_id    UUID        NOT NULL REFERENCES sectors(id),
  hospital_id  UUID        NOT NULL REFERENCES hospitals(id),
  inspector_id UUID        NOT NULL REFERENCES profiles(id),
  assigned_by  UUID        NOT NULL REFERENCES profiles(id),
  due_date     DATE        NOT NULL,
  status       TEXT        NOT NULL DEFAULT 'pending'
                           CHECK (status IN ('pending', 'in_progress', 'submitted', 'validated')),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------
-- 11. inspections
-- validated_by + validated_at → bloqueio permanente de edição
-- (regra 6.7: validado = locked forever)
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS inspections (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id        UUID        NOT NULL REFERENCES tasks(id),
  checklist_id   UUID        NOT NULL REFERENCES checklists(id),
  sector_id      UUID        NOT NULL REFERENCES sectors(id),
  hospital_id    UUID        NOT NULL REFERENCES hospitals(id),
  inspector_id   UUID        NOT NULL REFERENCES profiles(id),
  started_at     TIMESTAMPTZ,
  finished_at    TIMESTAMPTZ,
  submitted_at   TIMESTAMPTZ,
  overall_status TEXT        NOT NULL DEFAULT 'draft'
                             CHECK (overall_status IN ('draft', 'submitted', 'validated')),
  notes          TEXT,
  validated_by   UUID        REFERENCES profiles(id),
  validated_at   TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------
-- 12. inspection_responses
-- status NULL = item não respondido
-- observation obrigatória para NC (validado no app — seção 6.1)
-- foto: câmera obrigatória, galeria bloqueada (seção 6.5)
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS inspection_responses (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  inspection_id     UUID        NOT NULL REFERENCES inspections(id),
  checklist_item_id UUID        NOT NULL REFERENCES checklist_items(id),
  status            TEXT        CHECK (status IN ('C', 'NC', 'NA')),
  observation       TEXT,
  photo_url         TEXT,
  photo_captured_at TIMESTAMPTZ,
  photo_size_kb     INTEGER,
  answered_at       TIMESTAMPTZ
);

-- -----------------------------------------------------------
-- 13. reports
-- Dados calculados de inspection_responses.
-- Serve como cache e armazena URLs de exportação.
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS reports (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  inspection_id   UUID        NOT NULL REFERENCES inspections(id),
  hospital_id     UUID        NOT NULL REFERENCES hospitals(id),
  sector_id       UUID        NOT NULL REFERENCES sectors(id),
  total_items     INTEGER     NOT NULL,
  compliant       INTEGER     NOT NULL,
  non_compliant   INTEGER     NOT NULL,
  not_applicable  INTEGER     NOT NULL,
  compliance_rate DECIMAL(5,2) NOT NULL,
  pdf_url         TEXT,
  excel_url       TEXT,
  generated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------
-- 14. access_requests
-- resolved_by: pode ser o owner do setor OU o Director
-- (regra seção 4.2 e 6.8)
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS access_requests (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  sector_id    UUID        NOT NULL REFERENCES sectors(id),
  requester_id UUID        NOT NULL REFERENCES profiles(id),
  owner_id     UUID        NOT NULL REFERENCES profiles(id),
  can_view     BOOLEAN     NOT NULL DEFAULT false,
  can_edit     BOOLEAN     NOT NULL DEFAULT false,
  status       TEXT        NOT NULL DEFAULT 'pending'
                           CHECK (status IN ('pending', 'approved', 'denied')),
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at  TIMESTAMPTZ,
  resolved_by  UUID        REFERENCES profiles(id)
);

-- -----------------------------------------------------------
-- 15. notifications
-- Criadas por triggers/Edge Functions com service_role.
-- Mapa completo de tipos: seção 8 do CLAUDE.md.
-- NC Crítica NÃO gera notificação — apenas destaque visual.
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS notifications (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES profiles(id),
  hospital_id UUID        REFERENCES hospitals(id),
  type        TEXT        NOT NULL
                          CHECK (type IN (
                            'task_due_soon',
                            'task_overdue',
                            'draft_reminder',
                            'report_validated',
                            'access_request',
                            'access_approved',
                            'access_denied'
                          )),
  title       TEXT        NOT NULL,
  body        TEXT,
  read        BOOLEAN     NOT NULL DEFAULT false,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------
-- 16. audit_log
-- Apenas INSERT — nunca UPDATE ou DELETE (regra seção 7.16).
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_log (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES profiles(id),
  hospital_id UUID        REFERENCES hospitals(id),
  action      TEXT        NOT NULL,  -- ex: 'user.linked', 'inspection.submitted'
  entity_type TEXT        NOT NULL,  -- ex: 'profile', 'checklist', 'inspection'
  entity_id   UUID        NOT NULL,
  details     JSONB,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- ============================================================
-- PARTE 2: ENABLE ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE hospitals               ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles                ENABLE ROW LEVEL SECURITY;
ALTER TABLE sectors                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE inspector_sectors       ENABLE ROW LEVEL SECURITY;
ALTER TABLE sector_access           ENABLE ROW LEVEL SECURITY;
ALTER TABLE checklist_templates     ENABLE ROW LEVEL SECURITY;
ALTER TABLE checklist_template_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE checklists              ENABLE ROW LEVEL SECURITY;
ALTER TABLE checklist_items         ENABLE ROW LEVEL SECURITY;
ALTER TABLE tasks                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE inspections             ENABLE ROW LEVEL SECURITY;
ALTER TABLE inspection_responses    ENABLE ROW LEVEL SECURITY;
ALTER TABLE reports                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE access_requests         ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications           ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log               ENABLE ROW LEVEL SECURITY;


-- ============================================================
-- PARTE 3: POLÍTICAS RLS
--
-- Princípios (seção 14):
--   - Super Admin: acessa hospitals e profiles. NÃO acessa
--     tabelas operacionais.
--   - Director: acesso total onde hospital_id = seu hospital.
--   - Supervisor: setores onde é owner OU tem sector_access.
--   - Inspetor: apenas suas tasks, inspections e responses.
--   - get_my_role() e get_my_hospital_id() evitam recursão.
-- ============================================================


-- ============================================================
-- hospitals
-- ============================================================

-- Super Admin: acesso total (INSERT, SELECT, UPDATE)
CREATE POLICY "hospitals_super_admin_all"
  ON hospitals FOR ALL
  USING     (get_my_role() = 'super_admin')
  WITH CHECK (get_my_role() = 'super_admin');

-- Director / Supervisor / Inspector: apenas lê o próprio hospital
CREATE POLICY "hospitals_staff_select_own"
  ON hospitals FOR SELECT
  USING (id = get_my_hospital_id());


-- ============================================================
-- profiles
-- (tabela especial: também acessada por get_my_role/hospital_id)
-- ============================================================

-- Qualquer autenticado insere seu próprio perfil (pós-signUp)
CREATE POLICY "profiles_insert_own"
  ON profiles FOR INSERT
  WITH CHECK (id = auth.uid());

-- Todo usuário sempre lê o próprio perfil
CREATE POLICY "profiles_select_own"
  ON profiles FOR SELECT
  USING (id = auth.uid());

-- Super Admin lê todos os perfis
CREATE POLICY "profiles_select_super_admin"
  ON profiles FOR SELECT
  USING (get_my_role() = 'super_admin');

-- Director lê perfis do hospital + não vinculados (para vincular)
CREATE POLICY "profiles_select_director"
  ON profiles FOR SELECT
  USING (
    get_my_role() = 'director'
    AND (
      hospital_id = get_my_hospital_id()
      OR hospital_id IS NULL
    )
  );

-- Supervisor lê perfis do hospital (para ver equipe)
CREATE POLICY "profiles_select_supervisor"
  ON profiles FOR SELECT
  USING (
    get_my_role() = 'supervisor'
    AND hospital_id = get_my_hospital_id()
  );

-- Super Admin atualiza qualquer perfil (editar dados, desativar)
CREATE POLICY "profiles_update_super_admin"
  ON profiles FOR UPDATE
  USING     (get_my_role() = 'super_admin')
  WITH CHECK (get_my_role() = 'super_admin');

-- Director atualiza perfis do seu hospital (vincular, desativar)
CREATE POLICY "profiles_update_director"
  ON profiles FOR UPDATE
  USING (
    get_my_role() = 'director'
    AND hospital_id = get_my_hospital_id()
  )
  WITH CHECK (
    get_my_role() = 'director'
    AND hospital_id = get_my_hospital_id()
  );

-- Usuário atualiza o próprio perfil (foto, last_access)
CREATE POLICY "profiles_update_own"
  ON profiles FOR UPDATE
  USING     (id = auth.uid())
  WITH CHECK (id = auth.uid());


-- ============================================================
-- sectors
-- ============================================================

-- Director: acesso total ao hospital
CREATE POLICY "sectors_director_all"
  ON sectors FOR ALL
  USING (
    get_my_role() = 'director'
    AND hospital_id = get_my_hospital_id()
  )
  WITH CHECK (
    get_my_role() = 'director'
    AND hospital_id = get_my_hospital_id()
  );

-- Supervisor: SELECT em todos os setores do hospital
-- (vê cards de todos os setores — regra seção 4.3)
CREATE POLICY "sectors_supervisor_select"
  ON sectors FOR SELECT
  USING (
    get_my_role() = 'supervisor'
    AND hospital_id = get_my_hospital_id()
  );

-- Supervisor: INSERT (cria setor → vira owner)
CREATE POLICY "sectors_supervisor_insert"
  ON sectors FOR INSERT
  WITH CHECK (
    get_my_role() = 'supervisor'
    AND hospital_id = get_my_hospital_id()
    AND created_by = auth.uid()
  );

-- Supervisor: UPDATE apenas nos setores que é dono ou tem can_edit
CREATE POLICY "sectors_supervisor_update"
  ON sectors FOR UPDATE
  USING (
    get_my_role() = 'supervisor'
    AND hospital_id = get_my_hospital_id()
    AND (
      owner_supervisor_id = auth.uid()
      OR id IN (
        SELECT sector_id FROM sector_access
        WHERE supervisor_id = auth.uid() AND can_edit = true
      )
    )
  )
  WITH CHECK (
    get_my_role() = 'supervisor'
    AND hospital_id = get_my_hospital_id()
    AND (
      owner_supervisor_id = auth.uid()
      OR id IN (
        SELECT sector_id FROM sector_access
        WHERE supervisor_id = auth.uid() AND can_edit = true
      )
    )
  );

-- Inspector: SELECT apenas setores onde está vinculado
CREATE POLICY "sectors_inspector_select"
  ON sectors FOR SELECT
  USING (
    get_my_role() = 'inspector'
    AND id IN (
      SELECT sector_id FROM inspector_sectors
      WHERE inspector_id = auth.uid() AND status = 'active'
    )
  );


-- ============================================================
-- inspector_sectors
-- ============================================================

-- Director: acesso total (vincula/desvincula qualquer inspetor)
CREATE POLICY "inspector_sectors_director_all"
  ON inspector_sectors FOR ALL
  USING (
    get_my_role() = 'director'
    AND sector_id IN (
      SELECT id FROM sectors WHERE hospital_id = get_my_hospital_id()
    )
  )
  WITH CHECK (
    get_my_role() = 'director'
    AND sector_id IN (
      SELECT id FROM sectors WHERE hospital_id = get_my_hospital_id()
    )
  );

-- Supervisor: SELECT (ver inspetores de todos os setores do hospital)
CREATE POLICY "inspector_sectors_supervisor_select"
  ON inspector_sectors FOR SELECT
  USING (
    get_my_role() = 'supervisor'
    AND sector_id IN (
      SELECT id FROM sectors WHERE hospital_id = get_my_hospital_id()
    )
  );

-- Supervisor: INSERT (vincular inspetor ao próprio setor ou setor com can_edit)
CREATE POLICY "inspector_sectors_supervisor_insert"
  ON inspector_sectors FOR INSERT
  WITH CHECK (
    get_my_role() = 'supervisor'
    AND assigned_by = auth.uid()
    AND sector_id IN (
      SELECT id FROM sectors WHERE owner_supervisor_id = auth.uid()
      UNION
      SELECT sector_id FROM sector_access
      WHERE supervisor_id = auth.uid() AND can_edit = true
    )
  );

-- Supervisor: UPDATE (desativar vinculação nos setores com permissão)
CREATE POLICY "inspector_sectors_supervisor_update"
  ON inspector_sectors FOR UPDATE
  USING (
    get_my_role() = 'supervisor'
    AND sector_id IN (
      SELECT id FROM sectors WHERE owner_supervisor_id = auth.uid()
      UNION
      SELECT sector_id FROM sector_access
      WHERE supervisor_id = auth.uid() AND can_edit = true
    )
  )
  WITH CHECK (
    get_my_role() = 'supervisor'
    AND sector_id IN (
      SELECT id FROM sectors WHERE owner_supervisor_id = auth.uid()
      UNION
      SELECT sector_id FROM sector_access
      WHERE supervisor_id = auth.uid() AND can_edit = true
    )
  );

-- Inspector: SELECT (ver seus próprios vínculos — confirmar setores atribuídos)
CREATE POLICY "inspector_sectors_inspector_select"
  ON inspector_sectors FOR SELECT
  USING (
    get_my_role() = 'inspector'
    AND inspector_id = auth.uid()
  );


-- ============================================================
-- sector_access
-- ============================================================

-- Director: acesso total (conceder/revogar acesso compartilhado)
CREATE POLICY "sector_access_director_all"
  ON sector_access FOR ALL
  USING (
    get_my_role() = 'director'
    AND sector_id IN (
      SELECT id FROM sectors WHERE hospital_id = get_my_hospital_id()
    )
  )
  WITH CHECK (
    get_my_role() = 'director'
    AND sector_id IN (
      SELECT id FROM sectors WHERE hospital_id = get_my_hospital_id()
    )
  );

-- Supervisor: SELECT (ver seus acessos recebidos + acessos concedidos por ele)
CREATE POLICY "sector_access_supervisor_select"
  ON sector_access FOR SELECT
  USING (
    get_my_role() = 'supervisor'
    AND (
      supervisor_id = auth.uid()
      OR sector_id IN (
        SELECT id FROM sectors WHERE owner_supervisor_id = auth.uid()
      )
    )
  );

-- Supervisor (owner): INSERT (conceder acesso ao próprio setor)
CREATE POLICY "sector_access_supervisor_insert"
  ON sector_access FOR INSERT
  WITH CHECK (
    get_my_role() = 'supervisor'
    AND granted_by = auth.uid()
    AND sector_id IN (
      SELECT id FROM sectors WHERE owner_supervisor_id = auth.uid()
    )
  );

-- Supervisor (owner): UPDATE (alterar can_view / can_edit no próprio setor)
CREATE POLICY "sector_access_supervisor_update"
  ON sector_access FOR UPDATE
  USING (
    get_my_role() = 'supervisor'
    AND sector_id IN (
      SELECT id FROM sectors WHERE owner_supervisor_id = auth.uid()
    )
  )
  WITH CHECK (
    get_my_role() = 'supervisor'
    AND sector_id IN (
      SELECT id FROM sectors WHERE owner_supervisor_id = auth.uid()
    )
  );


-- ============================================================
-- checklist_templates
-- Tabela semi-global: globais (hospital_id NULL) visíveis a todos;
-- locais visíveis apenas ao hospital.
-- ============================================================

-- SELECT: todos veem globais + locais do seu hospital
CREATE POLICY "checklist_templates_select_all"
  ON checklist_templates FOR SELECT
  USING (
    scope = 'global'
    OR hospital_id = get_my_hospital_id()
  );

-- Super Admin: INSERT de templates globais
CREATE POLICY "checklist_templates_insert_super_admin"
  ON checklist_templates FOR INSERT
  WITH CHECK (
    get_my_role() = 'super_admin'
    AND scope = 'global'
    AND hospital_id IS NULL
  );

-- Director: INSERT de templates locais do seu hospital
CREATE POLICY "checklist_templates_insert_director"
  ON checklist_templates FOR INSERT
  WITH CHECK (
    get_my_role() = 'director'
    AND scope = 'local'
    AND hospital_id = get_my_hospital_id()
    AND created_by = auth.uid()
  );

-- Super Admin: UPDATE de templates globais
CREATE POLICY "checklist_templates_update_super_admin"
  ON checklist_templates FOR UPDATE
  USING (
    get_my_role() = 'super_admin'
    AND scope = 'global'
  )
  WITH CHECK (
    get_my_role() = 'super_admin'
    AND scope = 'global'
  );

-- Director: UPDATE de templates locais do seu hospital
CREATE POLICY "checklist_templates_update_director"
  ON checklist_templates FOR UPDATE
  USING (
    get_my_role() = 'director'
    AND scope = 'local'
    AND hospital_id = get_my_hospital_id()
  )
  WITH CHECK (
    get_my_role() = 'director'
    AND scope = 'local'
    AND hospital_id = get_my_hospital_id()
  );


-- ============================================================
-- checklist_template_items
-- ============================================================

-- SELECT: itens de templates acessíveis (globais + locais do hospital)
CREATE POLICY "checklist_template_items_select"
  ON checklist_template_items FOR SELECT
  USING (
    template_id IN (
      SELECT id FROM checklist_templates
      WHERE scope = 'global'
         OR hospital_id = get_my_hospital_id()
    )
  );

-- Super Admin: INSERT/UPDATE em templates globais
CREATE POLICY "checklist_template_items_insert_super_admin"
  ON checklist_template_items FOR INSERT
  WITH CHECK (
    get_my_role() = 'super_admin'
    AND template_id IN (
      SELECT id FROM checklist_templates WHERE scope = 'global'
    )
  );

CREATE POLICY "checklist_template_items_update_super_admin"
  ON checklist_template_items FOR UPDATE
  USING (
    get_my_role() = 'super_admin'
    AND template_id IN (
      SELECT id FROM checklist_templates WHERE scope = 'global'
    )
  )
  WITH CHECK (
    get_my_role() = 'super_admin'
    AND template_id IN (
      SELECT id FROM checklist_templates WHERE scope = 'global'
    )
  );

-- Director: INSERT/UPDATE em templates locais do seu hospital
CREATE POLICY "checklist_template_items_insert_director"
  ON checklist_template_items FOR INSERT
  WITH CHECK (
    get_my_role() = 'director'
    AND template_id IN (
      SELECT id FROM checklist_templates
      WHERE scope = 'local' AND hospital_id = get_my_hospital_id()
    )
  );

CREATE POLICY "checklist_template_items_update_director"
  ON checklist_template_items FOR UPDATE
  USING (
    get_my_role() = 'director'
    AND template_id IN (
      SELECT id FROM checklist_templates
      WHERE scope = 'local' AND hospital_id = get_my_hospital_id()
    )
  )
  WITH CHECK (
    get_my_role() = 'director'
    AND template_id IN (
      SELECT id FROM checklist_templates
      WHERE scope = 'local' AND hospital_id = get_my_hospital_id()
    )
  );


-- ============================================================
-- checklists
-- ============================================================

-- Director: acesso total ao hospital
CREATE POLICY "checklists_director_all"
  ON checklists FOR ALL
  USING (
    get_my_role() = 'director'
    AND hospital_id = get_my_hospital_id()
  )
  WITH CHECK (
    get_my_role() = 'director'
    AND hospital_id = get_my_hospital_id()
    AND created_by = auth.uid()
  );

-- Supervisor: SELECT em todos os checklists do hospital
-- (para o dashboard/calendário — regra seção 4.3)
CREATE POLICY "checklists_supervisor_select"
  ON checklists FOR SELECT
  USING (
    get_my_role() = 'supervisor'
    AND hospital_id = get_my_hospital_id()
  );

-- Supervisor: INSERT (nos setores com permissão)
CREATE POLICY "checklists_supervisor_insert"
  ON checklists FOR INSERT
  WITH CHECK (
    get_my_role() = 'supervisor'
    AND hospital_id = get_my_hospital_id()
    AND created_by = auth.uid()
    AND (
      sector_id IN (SELECT id FROM sectors WHERE owner_supervisor_id = auth.uid())
      OR sector_id IN (
        SELECT sector_id FROM sector_access
        WHERE supervisor_id = auth.uid() AND can_edit = true
      )
    )
  );

-- Supervisor: UPDATE (nos setores com permissão)
CREATE POLICY "checklists_supervisor_update"
  ON checklists FOR UPDATE
  USING (
    get_my_role() = 'supervisor'
    AND hospital_id = get_my_hospital_id()
    AND (
      sector_id IN (SELECT id FROM sectors WHERE owner_supervisor_id = auth.uid())
      OR sector_id IN (
        SELECT sector_id FROM sector_access
        WHERE supervisor_id = auth.uid() AND can_edit = true
      )
    )
  )
  WITH CHECK (
    get_my_role() = 'supervisor'
    AND hospital_id = get_my_hospital_id()
    AND (
      sector_id IN (SELECT id FROM sectors WHERE owner_supervisor_id = auth.uid())
      OR sector_id IN (
        SELECT sector_id FROM sector_access
        WHERE supervisor_id = auth.uid() AND can_edit = true
      )
    )
  );

-- Inspector: SELECT (checklists dos seus setores para leitura prévia)
CREATE POLICY "checklists_inspector_select"
  ON checklists FOR SELECT
  USING (
    get_my_role() = 'inspector'
    AND hospital_id = get_my_hospital_id()
    AND sector_id IN (
      SELECT sector_id FROM inspector_sectors
      WHERE inspector_id = auth.uid() AND status = 'active'
    )
  );


-- ============================================================
-- checklist_items
-- ============================================================

-- Director: acesso total
CREATE POLICY "checklist_items_director_all"
  ON checklist_items FOR ALL
  USING (
    get_my_role() = 'director'
    AND checklist_id IN (
      SELECT id FROM checklists WHERE hospital_id = get_my_hospital_id()
    )
  )
  WITH CHECK (
    get_my_role() = 'director'
    AND checklist_id IN (
      SELECT id FROM checklists WHERE hospital_id = get_my_hospital_id()
    )
  );

-- Supervisor: SELECT (todos os itens do hospital)
CREATE POLICY "checklist_items_supervisor_select"
  ON checklist_items FOR SELECT
  USING (
    get_my_role() = 'supervisor'
    AND checklist_id IN (
      SELECT id FROM checklists WHERE hospital_id = get_my_hospital_id()
    )
  );

-- Supervisor: INSERT/UPDATE (apenas nos checklists com permissão de edição)
CREATE POLICY "checklist_items_supervisor_insert"
  ON checklist_items FOR INSERT
  WITH CHECK (
    get_my_role() = 'supervisor'
    AND checklist_id IN (
      SELECT id FROM checklists
      WHERE hospital_id = get_my_hospital_id()
        AND (
          sector_id IN (SELECT id FROM sectors WHERE owner_supervisor_id = auth.uid())
          OR sector_id IN (
            SELECT sector_id FROM sector_access
            WHERE supervisor_id = auth.uid() AND can_edit = true
          )
        )
    )
  );

CREATE POLICY "checklist_items_supervisor_update"
  ON checklist_items FOR UPDATE
  USING (
    get_my_role() = 'supervisor'
    AND checklist_id IN (
      SELECT id FROM checklists
      WHERE hospital_id = get_my_hospital_id()
        AND (
          sector_id IN (SELECT id FROM sectors WHERE owner_supervisor_id = auth.uid())
          OR sector_id IN (
            SELECT sector_id FROM sector_access
            WHERE supervisor_id = auth.uid() AND can_edit = true
          )
        )
    )
  )
  WITH CHECK (
    get_my_role() = 'supervisor'
    AND checklist_id IN (
      SELECT id FROM checklists
      WHERE hospital_id = get_my_hospital_id()
        AND (
          sector_id IN (SELECT id FROM sectors WHERE owner_supervisor_id = auth.uid())
          OR sector_id IN (
            SELECT sector_id FROM sector_access
            WHERE supervisor_id = auth.uid() AND can_edit = true
          )
        )
    )
  );

-- Inspector: SELECT (itens dos seus checklists — para leitura prévia e resposta)
CREATE POLICY "checklist_items_inspector_select"
  ON checklist_items FOR SELECT
  USING (
    get_my_role() = 'inspector'
    AND checklist_id IN (
      SELECT id FROM checklists
      WHERE sector_id IN (
        SELECT sector_id FROM inspector_sectors
        WHERE inspector_id = auth.uid() AND status = 'active'
      )
    )
  );


-- ============================================================
-- tasks
-- ============================================================

-- Director: acesso total ao hospital
CREATE POLICY "tasks_director_all"
  ON tasks FOR ALL
  USING (
    get_my_role() = 'director'
    AND hospital_id = get_my_hospital_id()
  )
  WITH CHECK (
    get_my_role() = 'director'
    AND hospital_id = get_my_hospital_id()
    AND assigned_by = auth.uid()
  );

-- Supervisor: SELECT em todas as tarefas do hospital (quadro/calendário)
CREATE POLICY "tasks_supervisor_select"
  ON tasks FOR SELECT
  USING (
    get_my_role() = 'supervisor'
    AND hospital_id = get_my_hospital_id()
  );

-- Supervisor: INSERT (atribuir tarefas nos setores com permissão)
CREATE POLICY "tasks_supervisor_insert"
  ON tasks FOR INSERT
  WITH CHECK (
    get_my_role() = 'supervisor'
    AND hospital_id = get_my_hospital_id()
    AND assigned_by = auth.uid()
    AND (
      sector_id IN (SELECT id FROM sectors WHERE owner_supervisor_id = auth.uid())
      OR sector_id IN (
        SELECT sector_id FROM sector_access
        WHERE supervisor_id = auth.uid() AND can_edit = true
      )
    )
  );

-- Supervisor: UPDATE (reatribuir, alterar prazo, desativar tarefa)
CREATE POLICY "tasks_supervisor_update"
  ON tasks FOR UPDATE
  USING (
    get_my_role() = 'supervisor'
    AND hospital_id = get_my_hospital_id()
    AND (
      sector_id IN (SELECT id FROM sectors WHERE owner_supervisor_id = auth.uid())
      OR sector_id IN (
        SELECT sector_id FROM sector_access
        WHERE supervisor_id = auth.uid() AND can_edit = true
      )
    )
  )
  WITH CHECK (
    get_my_role() = 'supervisor'
    AND hospital_id = get_my_hospital_id()
    AND (
      sector_id IN (SELECT id FROM sectors WHERE owner_supervisor_id = auth.uid())
      OR sector_id IN (
        SELECT sector_id FROM sector_access
        WHERE supervisor_id = auth.uid() AND can_edit = true
      )
    )
  );

-- Inspector: SELECT (apenas suas tarefas)
CREATE POLICY "tasks_inspector_select"
  ON tasks FOR SELECT
  USING (
    get_my_role() = 'inspector'
    AND inspector_id = auth.uid()
  );

-- Inspector: UPDATE (atualizar status: pending→in_progress→submitted)
CREATE POLICY "tasks_inspector_update"
  ON tasks FOR UPDATE
  USING (
    get_my_role() = 'inspector'
    AND inspector_id = auth.uid()
  )
  WITH CHECK (
    get_my_role() = 'inspector'
    AND inspector_id = auth.uid()
  );


-- ============================================================
-- inspections
-- ============================================================

-- Director: acesso total ao hospital (incluindo validação)
CREATE POLICY "inspections_director_all"
  ON inspections FOR ALL
  USING (
    get_my_role() = 'director'
    AND hospital_id = get_my_hospital_id()
  )
  WITH CHECK (
    get_my_role() = 'director'
    AND hospital_id = get_my_hospital_id()
  );

-- Supervisor: SELECT em todas as inspeções do hospital
CREATE POLICY "inspections_supervisor_select"
  ON inspections FOR SELECT
  USING (
    get_my_role() = 'supervisor'
    AND hospital_id = get_my_hospital_id()
  );

-- Supervisor: UPDATE (para validar relatórios — regra 6.7)
CREATE POLICY "inspections_supervisor_update"
  ON inspections FOR UPDATE
  USING (
    get_my_role() = 'supervisor'
    AND hospital_id = get_my_hospital_id()
  )
  WITH CHECK (
    get_my_role() = 'supervisor'
    AND hospital_id = get_my_hospital_id()
  );

-- Inspector: SELECT (todas as suas inspeções — rascunhos e histórico)
CREATE POLICY "inspections_inspector_select"
  ON inspections FOR SELECT
  USING (
    get_my_role() = 'inspector'
    AND inspector_id = auth.uid()
  );

-- Inspector: INSERT (iniciar nova inspeção)
CREATE POLICY "inspections_inspector_insert"
  ON inspections FOR INSERT
  WITH CHECK (
    get_my_role() = 'inspector'
    AND inspector_id = auth.uid()
  );

-- Inspector: UPDATE apenas em rascunhos
-- Após submitted/validated: bloqueado permanentemente (regra 6.7)
CREATE POLICY "inspections_inspector_update"
  ON inspections FOR UPDATE
  USING (
    get_my_role() = 'inspector'
    AND inspector_id = auth.uid()
    AND overall_status = 'draft'
  )
  WITH CHECK (
    get_my_role() = 'inspector'
    AND inspector_id = auth.uid()
    AND overall_status IN ('draft', 'submitted')  -- permite submit (draft→submitted)
  );


-- ============================================================
-- inspection_responses
-- ============================================================

-- Director: SELECT em todas as respostas do hospital
CREATE POLICY "inspection_responses_director_select"
  ON inspection_responses FOR SELECT
  USING (
    get_my_role() = 'director'
    AND inspection_id IN (
      SELECT id FROM inspections WHERE hospital_id = get_my_hospital_id()
    )
  );

-- Supervisor: SELECT em todas as respostas do hospital
CREATE POLICY "inspection_responses_supervisor_select"
  ON inspection_responses FOR SELECT
  USING (
    get_my_role() = 'supervisor'
    AND inspection_id IN (
      SELECT id FROM inspections WHERE hospital_id = get_my_hospital_id()
    )
  );

-- Inspector: SELECT (todas as suas respostas — rascunho e histórico)
CREATE POLICY "inspection_responses_inspector_select"
  ON inspection_responses FOR SELECT
  USING (
    get_my_role() = 'inspector'
    AND inspection_id IN (
      SELECT id FROM inspections WHERE inspector_id = auth.uid()
    )
  );

-- Inspector: INSERT (salvar resposta — somente em rascunho)
CREATE POLICY "inspection_responses_inspector_insert"
  ON inspection_responses FOR INSERT
  WITH CHECK (
    get_my_role() = 'inspector'
    AND inspection_id IN (
      SELECT id FROM inspections
      WHERE inspector_id = auth.uid() AND overall_status = 'draft'
    )
  );

-- Inspector: UPDATE (alterar resposta — somente em rascunho)
-- Após submitted/validated: bloqueado (regra 6.7)
CREATE POLICY "inspection_responses_inspector_update"
  ON inspection_responses FOR UPDATE
  USING (
    get_my_role() = 'inspector'
    AND inspection_id IN (
      SELECT id FROM inspections
      WHERE inspector_id = auth.uid() AND overall_status = 'draft'
    )
  )
  WITH CHECK (
    get_my_role() = 'inspector'
    AND inspection_id IN (
      SELECT id FROM inspections
      WHERE inspector_id = auth.uid() AND overall_status = 'draft'
    )
  );


-- ============================================================
-- reports
-- ============================================================

-- Director: acesso total ao hospital
CREATE POLICY "reports_director_all"
  ON reports FOR ALL
  USING (
    get_my_role() = 'director'
    AND hospital_id = get_my_hospital_id()
  )
  WITH CHECK (
    get_my_role() = 'director'
    AND hospital_id = get_my_hospital_id()
  );

-- Supervisor: SELECT/INSERT/UPDATE relatórios do hospital
CREATE POLICY "reports_supervisor_select"
  ON reports FOR SELECT
  USING (
    get_my_role() = 'supervisor'
    AND hospital_id = get_my_hospital_id()
  );

CREATE POLICY "reports_supervisor_insert"
  ON reports FOR INSERT
  WITH CHECK (
    get_my_role() = 'supervisor'
    AND hospital_id = get_my_hospital_id()
  );

CREATE POLICY "reports_supervisor_update"
  ON reports FOR UPDATE
  USING (
    get_my_role() = 'supervisor'
    AND hospital_id = get_my_hospital_id()
  )
  WITH CHECK (
    get_my_role() = 'supervisor'
    AND hospital_id = get_my_hospital_id()
  );

-- Inspector: SELECT (ver seus próprios relatórios)
CREATE POLICY "reports_inspector_select"
  ON reports FOR SELECT
  USING (
    get_my_role() = 'inspector'
    AND inspection_id IN (
      SELECT id FROM inspections WHERE inspector_id = auth.uid()
    )
  );

-- Inspector: INSERT (gerar relatório ao enviar inspeção)
CREATE POLICY "reports_inspector_insert"
  ON reports FOR INSERT
  WITH CHECK (
    get_my_role() = 'inspector'
    AND inspection_id IN (
      SELECT id FROM inspections WHERE inspector_id = auth.uid()
    )
  );


-- ============================================================
-- access_requests
-- ============================================================

-- Director: acesso total ao hospital (pode aprovar qualquer pedido — regra 4.2)
CREATE POLICY "access_requests_director_all"
  ON access_requests FOR ALL
  USING (
    get_my_role() = 'director'
    AND sector_id IN (
      SELECT id FROM sectors WHERE hospital_id = get_my_hospital_id()
    )
  )
  WITH CHECK (
    get_my_role() = 'director'
    AND sector_id IN (
      SELECT id FROM sectors WHERE hospital_id = get_my_hospital_id()
    )
  );

-- Supervisor: SELECT (ver pedidos enviados + recebidos nos seus setores)
CREATE POLICY "access_requests_supervisor_select"
  ON access_requests FOR SELECT
  USING (
    get_my_role() = 'supervisor'
    AND (
      requester_id = auth.uid()
      OR owner_id = auth.uid()
    )
  );

-- Supervisor: INSERT (enviar pedido de acesso a outro setor)
CREATE POLICY "access_requests_supervisor_insert"
  ON access_requests FOR INSERT
  WITH CHECK (
    get_my_role() = 'supervisor'
    AND requester_id = auth.uid()
  );

-- Supervisor (owner): UPDATE (aprovar/negar pedidos para seus setores — regra 4.3)
CREATE POLICY "access_requests_supervisor_update"
  ON access_requests FOR UPDATE
  USING (
    get_my_role() = 'supervisor'
    AND owner_id = auth.uid()
  )
  WITH CHECK (
    get_my_role() = 'supervisor'
    AND owner_id = auth.uid()
  );


-- ============================================================
-- notifications
-- ============================================================

-- Usuário lê apenas suas próprias notificações
CREATE POLICY "notifications_select_own"
  ON notifications FOR SELECT
  USING (user_id = auth.uid());

-- Usuário atualiza apenas as suas (marcar como lida)
CREATE POLICY "notifications_update_own"
  ON notifications FOR UPDATE
  USING     (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Director/Supervisor criam notificações para usuários do hospital
-- (na prática, também criadas por Edge Functions com service_role)
CREATE POLICY "notifications_insert_staff"
  ON notifications FOR INSERT
  WITH CHECK (
    get_my_role() IN ('director', 'supervisor')
    AND hospital_id = get_my_hospital_id()
    AND user_id IN (
      SELECT id FROM profiles WHERE hospital_id = get_my_hospital_id()
    )
  );


-- ============================================================
-- audit_log
-- Apenas INSERT — UPDATE e DELETE deliberadamente omitidos
-- (sem policy = negado por padrão — regra seção 7.16)
-- ============================================================

-- Qualquer autenticado registra suas próprias ações
CREATE POLICY "audit_log_insert_own"
  ON audit_log FOR INSERT
  WITH CHECK (user_id = auth.uid());

-- Director lê o log do seu hospital
CREATE POLICY "audit_log_director_select"
  ON audit_log FOR SELECT
  USING (
    get_my_role() = 'director'
    AND hospital_id = get_my_hospital_id()
  );

-- Supervisor lê o log do seu hospital
CREATE POLICY "audit_log_supervisor_select"
  ON audit_log FOR SELECT
  USING (
    get_my_role() = 'supervisor'
    AND hospital_id = get_my_hospital_id()
  );

-- Super Admin lê todos os logs
CREATE POLICY "audit_log_super_admin_select"
  ON audit_log FOR SELECT
  USING (get_my_role() = 'super_admin');


-- ============================================================
-- FIM DO ARQUIVO
--
-- PRÓXIMOS PASSOS (manuais no painel Supabase):
--
-- 1. Storage → New bucket
--    - Name: inspection-photos
--    - Public bucket: OFF (privado)
--    - File size limit: 250KB
--    - Allowed MIME types: image/jpeg
--
-- 2. Criar o Super Admin:
--    a) Authentication → Users → Invite user (ou Add user)
--       - Email e senha do super admin
--    b) SQL Editor → execute:
--       UPDATE profiles
--       SET role = 'super_admin'
--       WHERE email = 'email-do-super-admin@exemplo.com';
--
-- 3. Copie a URL e anon key do projeto em:
--    Settings → API → Project URL e anon key
--    e cole em lib/core/services/supabase_service.dart
-- ============================================================
