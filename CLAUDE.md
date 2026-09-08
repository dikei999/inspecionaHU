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
- **Soft delete: ÚNICA exceção** = reset_demo_data() (migration_demo_reset.sql), acionada no Painel Demo digitando LIMPAR. Apaga de verdade, mas SÓ no hospital HU-DEMO (WHERE hospital_id obrigatório) e só por super_admin. NÃO é precedente: dado real continua sendo soft delete sempre
- **postgrest-dart: .order() é DESCENDENTE por padrão** (`ascending: false`). Toda ordenação crescente DEVE passar `ascending: true` explicitamente — omitir inverte a lista silenciosamente
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
**Biblioteca NR-32** (docs/BIBLIOTECA_NR32.md, aprovada pelo orientador): 97 itens em 10 seções (IDs BIO/QUI/RAD/RES/REF/LAV/LIM/MAN/GER/PFC) + 11 templates globais por setor, carregados por seed_nr32_library() (migration_nr32_library.sql). Fonte da verdade: docs/nr32.pdf → docs/nr32_texto.md. Item sem cláusula literal na NR-32 NÃO existe (NR-23/17/06/24/RDC/NBR proibidas).
**Categorias** (AppConstants.nr32Categories) = as 10 seções da biblioteca ("32.2 Riscos Biológicos" … "Anexo III — Perfurocortantes"). Dropdowns de categoria (form_setor/form_template) usam nr32CategoryOptions(): valor legado salvo entra como opção extra, nunca quebra.
**Norma visível**: lib/core/constants/nr32_clauses.dart (texto literal das cláusulas usadas) + lib/widgets/nr32_clause_chip.dart — chip tocável (bottom sheet com cláusula + criticidade) em resposta_checklist e relatorio_individual; referência fora do mapa = chip não tocável. PDF exporta seção final "Base normativa" (referências citadas em ordem crescente com texto integral).

## STATUS DESENVOLVIMENTO — Estado atual (jul/2026)
✅ Fase 1-2: Supabase configurado, tabelas+RLS, Flutter setup, auth, cadastro, login, aguardo, roteamento
✅ Fase 3-5: Painéis Super Admin, Diretor, Supervisor e Inspetor funcionais (checklist com câmera, C/NC/NA, calendários, histórico, perfil)
✅ Redesign visual: fontes EMBUTIDAS em assets/fonts/ — Sora (títulos/AppBar, w400-800) + Manrope (corpo, w400-700), google_fonts REMOVIDO; AppColors com escala tonal + AppShadows (card/elevated/primaryGlow em uso), DashboardHeader azul institucional (canto inferior 24px, linha 3px brandGreen na base — único uso decorativo do verde) nos 4 dashboards com donut/HeaderMetric em versão clara; widgets reutilizáveis em lib/widgets/ (StatCard, StatusBadge/ResponseBadge, EmptyState, SkeletonLoader, AppLogo, NotificationBell, charts), dashboards com fl_chart, transições fade-forward
✅ Exportação: lib/core/services/report_export_service.dart — PDF (pdf+printing, fotos via signed URL re-gerada, NC crítica em destaque) e Excel (abas Resumo/Itens, share_plus); botões na relatorio_individual_screen; audit_log export_pdf/export_excel
✅ Notificações in-app: NotificationProvider (lib/core/services/notification_service.dart) — Supabase Realtime + flutter_local_notifications + badge no sino; notificacoes_screen real (marcar lida/todas, navegação contextual por reference_id); inicia no login, encerra no logout
✅ Biblioteca NR-32 (set/2026): docs/nr32_texto.md + docs/BIBLIOTECA_NR32.md; migration_nr32_library.sql (seed_nr32_library(): 11 templates globais, correção idempotente do seed demo — desativa itens NR-23, preenche nr32_reference); seeds demo limpos (extintor/rota de fuga NR-23 removidos); nr32_clauses.dart + Nr32ClauseChip; Base normativa no PDF; permissões INTERNET/CAMERA no AndroidManifest
✅ Docs de entrega: docs/ESCOPO_ENTREGA.md (bolsista × instituição), docs/PUBLICACAO_LOJAS.md (guia — publicação NÃO realizada), docs/DEPLOY_WEB.md, docs/FIREBASE_SETUP.md
⚠️ migration_notifications.sql (raiz): PRECISA ser executada no SQL Editor — triggers (report_validated agora vem SÓ do trigger, o app não insere mais ao validar) + pg_cron (due_soon/overdue/draft_reminder) + coluna notifications.reference_id + Realtime publication
⚠️ migration_nr32_library.sql (raiz): PRECISA ser executada no SQL Editor (depois dos demo RPCs) e em seguida SELECT seed_nr32_library();
⚠️ migration_demo_reset.sql (raiz): PRECISA ser executada para habilitar o botão "Limpar dados demo" no Painel Demo
⚠️ fix_order_index.sql (raiz): script de correção pontual do order_index invertido pelo bug do .order() — rodar UMA vez, passo a passo, conferindo antes do UPDATE
⚠️ migration_archive_checklist.sql (raiz): PRECISA ser executada no SQL Editor para habilitar Arquivar checklist. Idempotente, não altera nenhuma policy
⚠️ migration_task_series.sql (raiz): PRECISA ser executada no SQL Editor para habilitar Tarefa recorrente. Idempotente, não altera nenhuma policy
✅ Relatório em lista única (set/2026): sem seção separada de NC, na tela e no PDF; observação e foto aparecem em todo item (C/NC/NA); tabela do PDF ganhou coluna Foto; criticidade usa selo neutro (não o ícone vermelho); foto que falha no download vira placeholder identificando o item
🔧 FCM: scaffold pronto atrás de FirebaseConfig.enabled (false até configurar) — passo a passo em docs/FIREBASE_SETUP.md; plugin google-services NÃO aplicado no Gradle de propósito
✅ Arquivar checklist (set/2026): checklists.archived_at/archived_by (migration_archive_checklist.sql) — REVERSÍVEL, diferente de status inactive. Arquivado sai das listas de trabalho, não gera tarefa e NÃO entra em NENHUM indicador. Regra centralizada em ArchiveService (archivedChecklistIds / inspectionIdsDeArquivados): reports não tem checklist_id, a exclusão passa por inspections. Filtro Em operação/Arquivados na aba de checklists do setor. Escopo do Supervisor vem da RLS já existente
✅ Ações padronizadas (set/2026): lib/widgets/confirm_dialog.dart — confirmAction() (destrutivo vermelho / reversível neutro), confirmSignOut() e showActionFeedback(). Logout confirma em todas as telas (exceto aguardo, deliberado). Botão Validar do relatório agora exige role director. Reativar tem diálogo próprio (não mais o vermelho de Desativar)
✅ Offline real (set/2026): docs/OFFLINE.md. OfflineStore (JSON via path_provider — Drift NÃO usado, exigiria build_runner), OfflineSyncService (fila em disco, ordem de queued_at, idempotência por opId + upsert onConflict), OfflineDownloadService (baixar tarefa+checklist+itens+inspeção+respostas), ConnectionBanner global no builder do MaterialApp. auth_provider cacheia o perfil e entra offline com sessão válida. Foto persiste na pasta do app antes do upload e nunca é descartada
⚠️ LIMITE do offline: primeiro login exige internet, e iniciar tarefa NUNCA aberta com rede também (a linha de inspections é criada no servidor — criá-la offline mudaria o fluxo online, fora do que o escopo autorizava). Basta abrir/baixar a tarefa uma vez com rede
✅ Offline resiste a fechar o app (set/2026): o access token dura 1h e sem rede a renovação falha, fazendo o supabase_flutter DESCARTAR a sessão — por isso reabrir em modo avião voltava ao login. OfflineStore.markSignedOut/isSignedOut separa saída real de falha de renovação; _init() entra offline com perfil em cache quando não há sessão e não houve saída explícita; o evento signedOut só derruba a sessão se _signingOut estiver ativo; tentarSairDoModoOffline() chama refreshSession() ao voltar a rede
✅ Tarefa recorrente (set/2026): migration_task_series.sql — tasks.series_id/series_index/series_total + status cancelled. Série gerada NO ATO da atribuição (TaskSeriesUtils, testado), SEM job no servidor e sem pg_cron. Teto de 60 por série, uma série por Inspetor, card mostra "3 de 14". Cancelar série = soft delete só das ocorrências FUTURAS pendentes (não toca no que foi respondido nem na de hoje). As 4 telas que liam tasks sem allow-list de status passaram a excluir cancelled
✅ Localização pt_BR (set/2026): flutter_localizations (vem do SDK) + locale/supportedLocales/delegates no MaterialApp. O intl já formatava as datas; o inglês vinha dos widgets do Material (date picker). test/l10n_test.dart cobre os dois lados
✅ Gradiente do cabeçalho (set/2026): kHeaderGradient em dashboard_header.dart — primary → primary800, ambos da escala tonal já existente, nenhuma cor nova. Fonte única para os 4 dashboards. Contraste do branco: 9,47:1 no topo e 15,31:1 na base (AAA)
✅ Logo HU Brasil dimensionada por LARGURA: o arquivo é 500×500 com a arte ocupando só 424×124 (24,8% da altura), então limitar a altura a renderizava com ~7px reais. Login usa width 140 + ClipRect; PDF usa width 62. NÃO voltar para height
🔧 Testes: test/task_series_utils_test.dart (10 casos, inclui o mês curto do 31/01) e test/l10n_test.dart. Cobertura ainda parcial — o grosso do app continua sem teste