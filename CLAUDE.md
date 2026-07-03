# CLAUDE.MD — InspecionaHU
> Contexto fixo. Leia antes de cada sessão. Se não está aqui, PERGUNTE.

## PROJETO
App NR-32 compliance para hospitais EBSERH. Piloto HU-UFPI. Multi-tenant (hospital_id em TODAS tabelas operacionais).
Stack: Flutter/Dart + Supabase (PostgreSQL + Auth + Storage) + RLS. Repo GitHub privado.
**REGRA DE OURO: toda query DEVE filtrar hospital_id. Sem exceção.**

## PERFIS
**Super Admin** — manual no Supabase. RH global. Cria hospitais, vincula Diretores (1/hospital), gerencia templates globais NR-32. NÃO acessa dados operacionais.
**Diretor** — 1 por hospital. Acesso total no hospital. Cria setores, checklists, vincula Supervisores/Inspetores a qualquer setor, atribui tarefas, valida relatórios, exporta PDF/Excel. NÃO responde checklists.
**Supervisor** — dono do setor atribuído + setores que criar. Cria setores (vira owner), checklists, vincula Inspetores ao próprio setor. Vê dashboard de todos setores (só visualização). NÃO responde checklists. NÃO cria Supervisores.
**Inspetor** — múltiplos setores (tabela inspector_sectors). Responde checklists, foto câmera obrigatória (galeria BLOQUEADA), salvamento auto, offline sync. Vê só próprias tarefas/histórico.

## VINCULAÇÃO
Cadastro: nome, email, CPF, senha → Supabase Auth → INSERT profiles → tela de aguardo (mostra email). Vinculação pelo nível acima buscando por EMAIL. App atualiza auto após vínculo.
Desativar Diretor: obrigatório vincular substituto antes. Desativar Supervisor com tarefas: transferência obrigatória. Soft delete sempre (status active/inactive, NUNCA delete).

## REGRAS DE NEGÓCIO
- NC sem observação → BLOQUEIA envio. NC com requires_photo sem foto → BLOQUEIA envio
- NC Crítica: destaque visual, SEM push. Tarefa atrasada: vermelho no quadro, push SÓ pro Inspetor
- overdue é CALCULADO (due_date < now AND status not in submitted/validated), NÃO armazenado
- Tarefas: atribuição MANUAL. Frequency no checklist é só referência informativa
- Foto: câmera only, 1280px, 75% JPEG, ~200KB. Storage: {hospital_id}/{inspection_id}/{uuid}.jpg
- Validação: muda status→validated, BLOQUEIA edição, notifica Inspetor
- Acesso compartilhado: can_view e can_edit independentes, concedido por owner OU Diretor
- Relatório duplicado: permitido com confirmação. Ambos ficam no histórico
- Offline: last-write-wins + notificar se checklist mudou durante inspeção

## TABELAS (16)
hospitals | profiles (sem sector_id) | sectors (owner_supervisor_id) | inspector_sectors | sector_access (can_view/can_edit) | checklist_templates (scope global/local) | checklist_template_items | checklists (frequency + custom_days[]) | checklist_items (sem requires_observation — NC=obs obrigatória sempre) | tasks (sem recurrence — manual) | inspections | inspection_responses (C/NC/NA) | reports (cache calculado) | access_requests | notifications | audit_log (só INSERT)

## RLS
Super Admin: hospitals + profiles (todas). Diretor: tudo WHERE hospital_id = seu. Supervisor: setores owner + sector_access. Inspetor: só próprias tasks/inspections/responses. Funções: get_my_role(), get_my_hospital_id() (SECURITY DEFINER).

## SEGURANÇA
- RLS é segurança real. Front-end só UX. NUNCA service_role_key no Flutter, só anon_key
- CPF: exibir só últimos 4 (***.***.XXX-XX). Fotos: signed URL 1h, bucket privado
- Login falho: msg genérica. Inputs: validar tamanho/tipo, queries parametrizadas (.eq/.ilike)
- audit_log em TODA ação relevante (vincular, criar, editar, desativar, submeter, validar)
- Double-submit: loading state em todos botões. Navegação: verificar role antes de renderizar

## VISUAL
Principal #1A56DB | Conforme #16A34A | NC #DC2626 | Pendente #D97706 | Fundo #F3F4F6 | Card #FFFFFF
Tipografia: system-ui (corpo), Georgia (logo). Border-radius: 12px cards, 8px inputs, 10px botões. Bordas 0.5px.
Interface em português ("Diretor" não "Director"). Código interno em inglês ("director").

## ESTRUTURA FLUTTER
```
lib/
├── main.dart
├── app/ (app.dart, routes.dart, theme.dart)
├── core/ (constants/, utils/, services/, models/)
├── features/ (auth/, super_admin/, director/, supervisor/, inspector/, shared/, templates/)
└── widgets/
```
Provider/Riverpod. snake_case arquivos, camelCase vars, PascalCase classes. Cada tela = arquivo próprio. Models espelham tabelas. Constantes separadas. try/catch + SnackBar em toda chamada Supabase. Loading states em toda op async.

## CHECKLIST POR TELA
Filtra hospital_id? status='active'? RLS cobre? Loading? Erro tratado? Cores certas? Sem hardcode? Responsivo? audit_log? Permissões? Inputs validados? CPF mascarado? Signed URL? Rota protegida? Double-submit?

## NOTIFICAÇÕES
task_due_soon (24h antes) → Inspetor push | task_overdue → Inspetor push | draft_reminder → Inspetor push | report_validated → Inspetor push | access_request/approved/denied → Supervisor push | NC Crítica → NINGUÉM (só visual)

## TEMPLATES NR-32
Globais (Super Admin, hospital_id=NULL) + Locais (Diretor, hospital_id=X). Criar checklist "do zero" ou "usar template" → COPIA itens. Original intacto.

## STATUS DESENVOLVIMENTO — Estado atual (jul/2026)
✅ Fase 1-2: Supabase configurado, tabelas+RLS, Flutter setup, auth, cadastro, login, aguardo, roteamento
✅ Fase 3-5: Painéis Super Admin, Diretor, Supervisor e Inspetor funcionais (checklist com câmera, C/NC/NA, calendários, histórico, perfil)
✅ Redesign visual: Inter (google_fonts), AppColors com escala tonal + AppShadows, widgets reutilizáveis em lib/widgets/ (StatCard, StatusBadge/ResponseBadge, EmptyState, SkeletonLoader, AppLogo, NotificationBell, charts), login hero com gradiente, dashboards com fl_chart (donut de conformidade + barras semanais), transições fade-forward
✅ Exportação: lib/core/services/report_export_service.dart — PDF (pdf+printing, fotos via signed URL re-gerada, NC crítica em destaque) e Excel (abas Resumo/Itens, share_plus); botões na relatorio_individual_screen; audit_log export_pdf/export_excel
✅ Notificações in-app: NotificationProvider (lib/core/services/notification_service.dart) — Supabase Realtime + flutter_local_notifications + badge no sino; notificacoes_screen real (marcar lida/todas, navegação contextual por reference_id); inicia no login, encerra no logout
⚠️ migration_notifications.sql (raiz): PRECISA ser executada no SQL Editor — triggers (report_validated agora vem SÓ do trigger, o app não insere mais ao validar) + pg_cron (due_soon/overdue/draft_reminder) + coluna notifications.reference_id + Realtime publication
🔧 FCM: scaffold pronto atrás de FirebaseConfig.enabled (false até configurar) — passo a passo em docs/FIREBASE_SETUP.md; plugin google-services NÃO aplicado no Gradle de propósito
⬜ Offline real (Drift é STUB — offline_sync_service.dart); auto-save atual com retry+backoff, fila de reenvio e indicador salvando/salvo/erro; Testes