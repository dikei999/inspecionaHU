# Escopo de Entrega — InspecionaHU

Divisão de responsabilidades entre o que foi **entregue pelo bolsista** ao final do projeto e o que fica **a cargo da instituição** (HU-UFPI / EBSERH) após a entrega. Baseado exclusivamente no que existe neste repositório.

## Entregue pelo bolsista

| Entrega | Onde está |
|---------|-----------|
| Aplicativo Flutter multiplataforma (Android e Web) com os 4 perfis — Super Admin, Diretor, Supervisor e Inspetor — incluindo cadastro, login, vinculação por e-mail, painéis, atribuição de tarefas, resposta de checklist com foto obrigatória pela câmera, validação de relatórios e histórico | `lib/` |
| Banco de dados PostgreSQL (Supabase) com 16 tabelas multi-tenant (`hospital_id` em todas as tabelas operacionais) e políticas RLS por perfil | `supabase_setup.sql` |
| Migrations complementares: contas demo, seed de dados de exemplo, notificações (triggers + pg_cron), políticas de Storage, códigos de tarefa, constraints de unicidade | `migration_*.sql` na raiz |
| Biblioteca NR-32: catálogo de 97 itens de inspeção referenciados à norma e 11 templates globais por tipo de setor, carregáveis via `seed_nr32_library()` | `docs/BIBLIOTECA_NR32.md`, `migration_nr32_library.sql` |
| Texto normativo da NR-32 embutido no app: chip de referência tocável nas telas de inspeção e relatório, com o texto integral da cláusula | `lib/core/constants/nr32_clauses.dart`, `lib/widgets/nr32_clause_chip.dart` |
| Exportação de relatórios em PDF (com fotos, destaque de NC crítica e seção "Base normativa") e Excel | `lib/core/services/report_export_service.dart` |
| Notificações in-app em tempo real (Supabase Realtime + notificações locais) e scaffold de push FCM desligado por flag (`FirebaseConfig.enabled`) | `lib/core/services/notification_service.dart`, `lib/core/services/firebase_config.dart`, `docs/FIREBASE_SETUP.md` |
| Identidade visual: fontes Sora/Manrope embutidas, paleta institucional, widgets reutilizáveis, dashboards com gráficos | `lib/widgets/`, `assets/` |
| Auditoria (`audit_log`) das ações relevantes e regras de segurança (anon key apenas, CPF mascarado, signed URLs de foto, soft delete) | transversal ao código |
| Documentação de operação: setup do Firebase, guia de publicação nas lojas, guia de deploy web, este escopo | `docs/` |
| Ambiente demo completo: contas `superadmin/diretor/supervisor/inspetor@demo.com` (senha `demo1234`), hospital HU-DEMO, setores, checklists e tarefas de exemplo | `migration_demo_rpcs.sql`, `migration_seed_fix.sql`, Painel Demo no app |

## A cargo da instituição após a entrega

| Responsabilidade | Observação |
|------------------|------------|
| **Hospedagem definitiva da versão web** | O guia `docs/DEPLOY_WEB.md` descreve build e deploy (Railway usado durante o desenvolvimento); a instituição define e custeia a hospedagem final |
| **Conta Supabase de produção** | O projeto atual é a instância de desenvolvimento/piloto do bolsista. Para produção: criar organização/projeto próprio da instituição, executar `supabase_setup.sql` + migrations na ordem documentada e migrar os dados que interessarem |
| **Contas de publicação nas lojas** (Google Play Console e Apple Developer Program) | Contas institucionais, taxas e revisão das lojas — passo a passo em `docs/PUBLICACAO_LOJAS.md`. A publicação **não foi realizada** no projeto |
| **Keystore de assinatura do APK/AAB de produção** | Deve ser gerada e guardada pela instituição (perder a keystore impede atualizações do app na Play Store) |
| **Projeto Firebase para push (FCM)** | O scaffold está pronto e desligado; ativação segue `docs/FIREBASE_SETUP.md` e exige projeto Firebase institucional |
| **Gestão de usuários reais** | Criação do Super Admin de produção, cadastro de hospitais e vinculação dos Diretores reais; desativação do modo demo (`AppConfig.showDemoLogin = false` em `lib/core/config/app_config.dart`) antes do build final |
| **Validação da biblioteca NR-32 pelo SESMT** | O catálogo de `docs/BIBLIOTECA_NR32.md` foi construído a partir do texto da norma (`docs/nr32.pdf`) e deve ser revisado/ajustado pelo SESMT do hospital antes do uso oficial em inspeções |
| **Manutenção evolutiva** | Novas funcionalidades, atualização de dependências Flutter/Supabase, acompanhamento de mudanças na NR-32 e nas políticas das lojas |
| **Itens em aberto conhecidos** | Sincronização offline real (Drift é stub em `lib/core/services/offline_sync_service.dart`; o auto-save atual usa retry + fila de reenvio online), suíte de testes automatizados, e execução de `migration_notifications.sql` no ambiente definitivo |

## Condições no momento da entrega

- `flutter analyze` sem erros; app funcional nos fluxos dos 4 perfis com dados demo.
- Publicação nas lojas **não realizada** — os guias em `docs/` são artefatos de transferência de conhecimento.
- `applicationId` ainda é `com.example.inspecionahu` e o build release assina com chave de debug — ambos devem ser alterados pela instituição antes de publicar (detalhado em `docs/PUBLICACAO_LOJAS.md`).
