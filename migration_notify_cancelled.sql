-- ═══════════════════════════════════════════════════════════════════════════
-- migration_notify_cancelled.sql
--
-- Tarefa CANCELADA (ocorrência futura de uma série interrompida) não pode
-- gerar notificação de atraso.
--
-- fn_notify_task_overdue() foi escrita antes do status 'cancelled' existir e
-- filtra apenas ('submitted', 'validated'); uma ocorrência cancelada com
-- prazo vencido continuaria cobrando o Inspetor.
--
-- As demais funções JÁ ESTÃO CORRETAS e não são tocadas aqui:
--   • fn_notify_task_due_soon()  usa status IN ('pending','in_progress'),
--     que naturalmente exclui 'cancelled';
--   • ambas olham CURRENT_DATE, então ocorrência AGENDADA (data futura)
--     nunca notificou antes da hora.
--
-- Esta migration reproduz a função original com UMA única mudança, o filtro
-- de status. Título, corpo e deduplicação seguem idênticos.
--
-- Executar DEPOIS de migration_notifications.sql e migration_task_series.sql.
-- Idempotente. Nenhuma policy alterada.
-- ═══════════════════════════════════════════════════════════════════════════

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
    -- ÚNICA mudança: 'cancelled' entra na exclusão.
    AND t.status NOT IN ('submitted', 'validated', 'cancelled')
    -- deduplicação por task_id + tipo: uma única notificação de atraso
    AND NOT EXISTS (
      SELECT 1 FROM notifications n
      WHERE n.user_id = t.inspector_id
        AND n.type = 'task_overdue'
        AND n.reference_id = t.id
    );
END;
$$;
