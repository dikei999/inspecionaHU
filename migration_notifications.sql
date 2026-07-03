-- ============================================================
-- InspecionaHU — MIGRATION: Sistema de Notificações (servidor)
-- ============================================================
-- Colar este arquivo inteiro no SQL Editor do Supabase e executar.
--
-- Conteúdo:
--   0. Coluna reference_id + tabela notifications no Realtime
--   1. Trigger: relatório validado → notifica o Inspetor
--   2. Triggers: access_requests (criação / aprovação / negação)
--   3. Funções agendadas (pg_cron):
--        3a. task_due_soon  — prazo em ~24h  → notifica SÓ o Inspetor
--        3b. task_overdue   — atrasada (CALCULADO, nunca armazenado)
--        3c. draft_reminder — rascunho parado há 24h sem envio
--
-- Regras respeitadas:
--   - NC Crítica NÃO gera notificação (apenas destaque visual no app)
--   - overdue é calculado: due_date < now AND status NOT IN
--     ('submitted','validated') — nunca gravado na task
--   - Deduplicação por (user_id, type, reference_id): cada tarefa/
--     inspeção gera no máximo UMA notificação de cada tipo
--   - Todas as funções são SECURITY DEFINER (executam como owner,
--     ignorando RLS — necessário para inserir notificações de outros
--     usuários) com search_path fixado em public
--   - Textos de title/body em pt-BR
-- ============================================================


-- ============================================================
-- 0. PREPARAÇÃO
-- ============================================================

-- 0.1 Coluna reference_id: aponta para a entidade que originou a
--     notificação (task, inspection ou access_request). O app usa
--     esse id para navegação contextual ao tocar na notificação.
ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS reference_id UUID;

-- 0.2 Índice para a deduplicação das funções agendadas
CREATE INDEX IF NOT EXISTS idx_notifications_dedupe
  ON public.notifications (user_id, type, reference_id);

-- 0.3 Habilita Realtime na tabela notifications — o app assina
--     INSERTs filtrados por user_id para exibir notificação local
--     e atualizar o badge do sino em tempo real.
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
EXCEPTION
  WHEN duplicate_object THEN
    NULL; -- tabela já estava na publicação
END $$;


-- ============================================================
-- 1. TRIGGER: RELATÓRIO VALIDADO → NOTIFICA O INSPETOR
-- ============================================================
-- Dispara quando inspections.overall_status muda para 'validated'.
-- Notifica APENAS o Inspetor da inspeção (regra seção 8).

CREATE OR REPLACE FUNCTION public.fn_notify_report_validated()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_checklist_title TEXT;
BEGIN
  -- Só age na transição para 'validated' (não em re-updates)
  IF NEW.overall_status = 'validated'
     AND (OLD.overall_status IS DISTINCT FROM 'validated') THEN

    SELECT title INTO v_checklist_title
    FROM checklists WHERE id = NEW.checklist_id;

    INSERT INTO notifications
      (user_id, hospital_id, type, title, body, reference_id)
    VALUES (
      NEW.inspector_id,
      NEW.hospital_id,
      'report_validated',
      'Relatório validado',
      'Seu relatório de "' || COALESCE(v_checklist_title, 'inspeção')
        || '" foi validado e está bloqueado para edição.',
      NEW.id
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_report_validated ON public.inspections;
CREATE TRIGGER trg_notify_report_validated
  AFTER UPDATE OF overall_status ON public.inspections
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_notify_report_validated();


-- ============================================================
-- 2. TRIGGERS: ACCESS_REQUESTS
-- ============================================================

-- 2.1 CRIAÇÃO de pedido de acesso → notifica os envolvidos:
--     o Supervisor dono do setor (owner_id) e o(s) Diretor(es)
--     ativos do hospital do setor.
CREATE OR REPLACE FUNCTION public.fn_notify_access_request_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hospital_id    UUID;
  v_sector_name    TEXT;
  v_requester_name TEXT;
  v_director       RECORD;
BEGIN
  -- hospital_id vem do setor (multi-tenant: sempre presente)
  SELECT hospital_id, name INTO v_hospital_id, v_sector_name
  FROM sectors WHERE id = NEW.sector_id;

  SELECT full_name INTO v_requester_name
  FROM profiles WHERE id = NEW.requester_id;

  -- Notifica o Supervisor dono do setor
  INSERT INTO notifications
    (user_id, hospital_id, type, title, body, reference_id)
  VALUES (
    NEW.owner_id,
    v_hospital_id,
    'access_request',
    'Solicitação de acesso',
    COALESCE(v_requester_name, 'Um usuário')
      || ' solicitou acesso ao setor "'
      || COALESCE(v_sector_name, '—') || '".',
    NEW.id
  );

  -- Notifica o(s) Diretor(es) ativos do hospital (exceto se for o owner)
  FOR v_director IN
    SELECT id FROM profiles
    WHERE hospital_id = v_hospital_id
      AND role = 'director'
      AND status = 'active'
      AND id <> NEW.owner_id
  LOOP
    INSERT INTO notifications
      (user_id, hospital_id, type, title, body, reference_id)
    VALUES (
      v_director.id,
      v_hospital_id,
      'access_request',
      'Solicitação de acesso',
      COALESCE(v_requester_name, 'Um usuário')
        || ' solicitou acesso ao setor "'
        || COALESCE(v_sector_name, '—') || '".',
      NEW.id
    );
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_access_request_created
  ON public.access_requests;
CREATE TRIGGER trg_notify_access_request_created
  AFTER INSERT ON public.access_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_notify_access_request_created();


-- 2.2 RESOLUÇÃO do pedido (aprovado/negado) → notifica o solicitante
CREATE OR REPLACE FUNCTION public.fn_notify_access_request_resolved()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hospital_id UUID;
  v_sector_name TEXT;
BEGIN
  -- Só age quando o status muda de 'pending' para approved/denied
  IF NEW.status IN ('approved', 'denied')
     AND OLD.status IS DISTINCT FROM NEW.status THEN

    SELECT hospital_id, name INTO v_hospital_id, v_sector_name
    FROM sectors WHERE id = NEW.sector_id;

    IF NEW.status = 'approved' THEN
      INSERT INTO notifications
        (user_id, hospital_id, type, title, body, reference_id)
      VALUES (
        NEW.requester_id,
        v_hospital_id,
        'access_approved',
        'Acesso aprovado',
        'Seu pedido de acesso ao setor "'
          || COALESCE(v_sector_name, '—') || '" foi aprovado.',
        NEW.id
      );
    ELSE
      INSERT INTO notifications
        (user_id, hospital_id, type, title, body, reference_id)
      VALUES (
        NEW.requester_id,
        v_hospital_id,
        'access_denied',
        'Acesso negado',
        'Seu pedido de acesso ao setor "'
          || COALESCE(v_sector_name, '—') || '" foi negado.',
        NEW.id
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_access_request_resolved
  ON public.access_requests;
CREATE TRIGGER trg_notify_access_request_resolved
  AFTER UPDATE OF status ON public.access_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_notify_access_request_resolved();


-- ============================================================
-- 3. FUNÇÕES AGENDADAS (pg_cron)
-- ============================================================

-- 3a. PRAZO EM ~24H → notifica SÓ o Inspetor da tarefa
--     due_date é DATE: "vence em até 24h" = vence hoje ou amanhã.
--     Dedup: uma notificação task_due_soon por tarefa/inspetor.
CREATE OR REPLACE FUNCTION public.fn_notify_task_due_soon()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO notifications
    (user_id, hospital_id, type, title, body, reference_id)
  SELECT
    t.inspector_id,
    t.hospital_id,
    'task_due_soon',
    'Prazo chegando',
    'A inspeção "' || COALESCE(c.title, 'checklist')
      || '" vence em ' || to_char(t.due_date, 'DD/MM/YYYY') || '.',
    t.id
  FROM tasks t
  JOIN checklists c ON c.id = t.checklist_id
  WHERE t.status IN ('pending', 'in_progress')
    -- vence nas próximas ~24h (hoje ou amanhã), mas ainda não venceu
    AND t.due_date >= CURRENT_DATE
    AND t.due_date <= CURRENT_DATE + INTERVAL '1 day'
    -- deduplicação: nunca repetir para a mesma tarefa
    AND NOT EXISTS (
      SELECT 1 FROM notifications n
      WHERE n.user_id = t.inspector_id
        AND n.type = 'task_due_soon'
        AND n.reference_id = t.id
    );
END;
$$;

-- 3b. TAREFA ATRASADA → notifica SÓ o Inspetor, UMA vez por tarefa
--     Atrasada é sempre CALCULADO aqui (nunca gravado em tasks.status):
--     due_date < now  AND  status NOT IN ('submitted', 'validated')
CREATE OR REPLACE FUNCTION public.fn_notify_task_overdue()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO notifications
    (user_id, hospital_id, type, title, body, reference_id)
  SELECT
    t.inspector_id,
    t.hospital_id,
    'task_overdue',
    'Tarefa atrasada',
    'A inspeção "' || COALESCE(c.title, 'checklist')
      || '" venceu em ' || to_char(t.due_date, 'DD/MM/YYYY')
      || ' e ainda não foi enviada.',
    t.id
  FROM tasks t
  JOIN checklists c ON c.id = t.checklist_id
  WHERE t.due_date < CURRENT_DATE
    AND t.status NOT IN ('submitted', 'validated')
    -- deduplicação por task_id + tipo: uma única notificação de atraso
    AND NOT EXISTS (
      SELECT 1 FROM notifications n
      WHERE n.user_id = t.inspector_id
        AND n.type = 'task_overdue'
        AND n.reference_id = t.id
    );
END;
$$;

-- 3c. RASCUNHO PARADO HÁ 24H → notifica SÓ o Inspetor
--     Inspeção em 'draft' iniciada há mais de 24h e não enviada.
--     Dedup: um lembrete por inspeção.
CREATE OR REPLACE FUNCTION public.fn_notify_draft_reminder()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO notifications
    (user_id, hospital_id, type, title, body, reference_id)
  SELECT
    i.inspector_id,
    i.hospital_id,
    'draft_reminder',
    'Inspeção não finalizada',
    'Você tem um rascunho de "' || COALESCE(c.title, 'checklist')
      || '" iniciado há mais de 24h. Finalize e envie a inspeção.',
    i.id
  FROM inspections i
  JOIN checklists c ON c.id = i.checklist_id
  WHERE i.overall_status = 'draft'
    AND COALESCE(i.started_at, i.created_at) < now() - INTERVAL '24 hours'
    -- deduplicação por inspeção + tipo
    AND NOT EXISTS (
      SELECT 1 FROM notifications n
      WHERE n.user_id = i.inspector_id
        AND n.type = 'draft_reminder'
        AND n.reference_id = i.id
    );
END;
$$;


-- ============================================================
-- 4. AGENDAMENTO (pg_cron — disponível no Supabase)
-- ============================================================
-- As três verificações rodam de hora em hora, em minutos
-- alternados para não competir entre si.
-- Se a extensão ainda não estiver ativa, habilitar antes em:
-- Database → Extensions → pg_cron.

CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Remove agendamentos anteriores com o mesmo nome (re-execução segura)
DO $$
BEGIN
  PERFORM cron.unschedule('inspecionahu_task_due_soon');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  PERFORM cron.unschedule('inspecionahu_task_overdue');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  PERFORM cron.unschedule('inspecionahu_draft_reminder');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- Prazo em ~24h: a cada hora, no minuto 0
SELECT cron.schedule(
  'inspecionahu_task_due_soon',
  '0 * * * *',
  $$SELECT public.fn_notify_task_due_soon()$$
);

-- Tarefas atrasadas: a cada hora, no minuto 10
SELECT cron.schedule(
  'inspecionahu_task_overdue',
  '10 * * * *',
  $$SELECT public.fn_notify_task_overdue()$$
);

-- Rascunhos parados: a cada hora, no minuto 20
SELECT cron.schedule(
  'inspecionahu_draft_reminder',
  '20 * * * *',
  $$SELECT public.fn_notify_draft_reminder()$$
);

-- ============================================================
-- FIM DA MIGRATION
-- ============================================================
