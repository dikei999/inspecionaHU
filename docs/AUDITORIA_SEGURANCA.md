# Auditoria de Segurança — InspecionaHU

**Data:** 9 de setembro de 2026
**Escopo:** aplicativo Flutter + backend Supabase (PostgreSQL, Auth, Storage, RLS)
**Alvo dos testes:** projeto `xccmdnwexdkevrlpynio`, hospitais `HU-DEMO` e `HU-UFPI`
**Método:** leitura das 78 políticas RLS **e** teste ativo contra o banco real,
usando apenas a `anon key` pública embutida no APK — ou seja, exatamente a
superfície disponível a quem tiver o aplicativo instalado.

> Este documento registra constatações. Onde a proteção falhou, está escrito que
> falhou, com o resultado do teste. Onde só a interface protegia, está apontado
> como falha, conforme solicitado.

---

## Sumário das constatações

| # | Constatação | Gravidade | Situação |
|---|---|---|---|
| 1 | Usuário altera o próprio `role` e vira Diretor | **Crítica** | Corrigida (SQL) |
| 2 | Fotos de inspeção sem isolamento entre hospitais | **Crítica** | Corrigida (SQL) |
| 3 | Supervisor valida relatório; só a interface barrava | **Alta** | Corrigida (SQL) |
| 4 | `reports.hospital_id` forjável pelo Inspetor | Média | Corrigida (SQL) |
| 5 | `inspections.hospital_id` forjável no INSERT | Média | Corrigida (SQL) |
| 6 | `audit_log.hospital_id` forjável | Média | Corrigida (SQL) |
| 7 | Inspetor lê o `audit_log` do hospital | Média | Corrigida (SQL) |
| 8 | Vínculo de inspetor de outro hospital a um setor | Média | Corrigida (SQL) |
| 9 | Pedido de acesso a setor de outro hospital | Baixa | Corrigida (SQL) |
| 10 | Histórico do Inspetor não filtrava `hospital_id` | Média | Corrigida (app) |
| 11 | Observação da NC sem limite de tamanho | Baixa | Corrigida (app) |
| 12 | CPF completo trafega na API (máscara é só de tela) | Média | **Não corrigida** |
| 13 | Sessão em armazenamento não criptografado no aparelho | Média | **Não corrigida** |
| 14 | Senhas demo em texto claro dentro do APK | Média | **Não corrigida** |
| 15 | `audit_log` não registra login, logout nem convite | Baixa | **Não corrigida** |
| 16 | Perfil com `role` nulo em produção | Baixa | **Não corrigida** |

O isolamento **de leitura** entre hospitais — que é o requisito central do
projeto multiunidade — resistiu a todos os testes. As falhas encontradas são de
**escrita** e de **escalonamento de privilégio**, não de vazamento entre
unidades.

---

## B1. Políticas RLS, tabela por tabela

RLS está habilitado nas 16 tabelas. As funções `get_my_role()` e
`get_my_hospital_id()` são `SECURITY DEFINER` com `search_path` fixo, o que
evita tanto a recursão de política quanto o sequestro de `search_path`. Correto.

| Tabela | Lê | Escreve | Isolamento entre hospitais |
|---|---|---|---|
| `hospitals` | Super Admin: todos. Demais: só o próprio | Só Super Admin | Íntegro |
| `profiles` | Próprio; Super Admin todos; Diretor do hospital + não vinculados; Supervisor do hospital | Próprio (ver #1); Diretor no hospital; Super Admin | Íntegro na leitura |
| `sectors` | Diretor/Supervisor do hospital; Inspetor só onde vinculado | Diretor; Supervisor se `owner` ou `can_edit` | Íntegro |
| `inspector_sectors` | Diretor/Supervisor do hospital; Inspetor os próprios | Diretor; Supervisor nos setores com permissão | Falha #8 |
| `sector_access` | Diretor; Supervisor envolvido | Diretor; Supervisor owner | Íntegro |
| `checklist_templates` | Globais + locais do hospital | Super Admin (global); Diretor (local) | Íntegro |
| `checklist_template_items` | Herdado do template | Idem | Íntegro |
| `checklists` | Diretor/Supervisor do hospital; Inspetor via setor | Diretor; Supervisor com permissão | Íntegro |
| `checklist_items` | Herdado do checklist | Idem | Íntegro |
| `tasks` | Diretor/Supervisor do hospital; Inspetor só as próprias | Diretor; Supervisor com permissão; Inspetor só status | Íntegro |
| `inspections` | Diretor/Supervisor do hospital; Inspetor as próprias | Diretor; Supervisor (ver #3); Inspetor só rascunho | Falha #5 no INSERT |
| `inspection_responses` | Via inspeção | Inspetor, só enquanto rascunho | Íntegro |
| `reports` | Diretor/Supervisor do hospital; Inspetor os próprios | Diretor; Supervisor; Inspetor | Falha #4 no INSERT |
| `access_requests` | Diretor do hospital; Supervisor envolvido | Diretor; Supervisor requester/owner | Falha #9 |
| `notifications` | Só as próprias | Diretor/Supervisor para o próprio hospital | Íntegro |
| `audit_log` | Diretor/Supervisor do hospital; Super Admin todos | Qualquer autenticado (ver #6) | Falha #6 e #7 |

Dois acertos que merecem registro: `audit_log` **não tem** política de UPDATE nem
de DELETE — sem política, o Postgres nega. O log é imutável por construção, não
por convenção. E o bloqueio de edição após envio é RLS de verdade:
`inspection_responses` exige `overall_status = 'draft'` na própria política.

---

## B2. Isolamento multiunidade — testado, não presumido

Um Diretor autenticado no `HU-DEMO` tentou alcançar o `HU-UFPI` por rota direta
da API, sem passar pela interface:

```
[BLOQUEADO] ler sectors do outro hospital           (0 linhas)
[BLOQUEADO] ler checklists do outro hospital        (0 linhas)
[BLOQUEADO] ler tasks do outro hospital             (0 linhas)
[BLOQUEADO] ler inspections do outro hospital       (0 linhas)
[BLOQUEADO] ler reports do outro hospital           (0 linhas)
[BLOQUEADO] ler audit_log do outro hospital         (0 linhas)
[BLOQUEADO] ler notifications do outro hospital     (0 linhas)
[BLOQUEADO] contar inspeções do outro hospital      (0 linhas)
[BLOQUEADO] criar setor no outro hospital           (403, RLS)
```

Sem autenticação nenhuma, as sete tabelas testadas devolvem 200 com **zero
linhas** — a RLS nega por ausência de política, não por erro. Não há vazamento
para visitante anônimo.

**Contagem e indicadores** merecem nota separada, porque foi um ponto levantado:
o `count=exact` do PostgREST é aplicado **depois** da RLS. O Diretor do
`HU-DEMO` recebeu contagem zero para o `HU-UFPI` — não é possível inferir volume
de dados alheios contando linhas.

**Exportação** (PDF e Excel) não é uma rota paralela: `report_export_service.dart`
monta o arquivo a partir de dados já carregados pela tela, que passaram pela RLS.
Não há consulta privilegiada nem `service_role` no caminho de exportação.

**Conclusão de B2: o isolamento de leitura entre hospitais está íntegro.**

---

## B3. Escalonamento de privilégio — duas falhas confirmadas

### #1 — Usuário se promove a Diretor (crítica)

A política `profiles_update_own` permitia ao usuário atualizar o próprio perfil,
mas **não restringia quais colunas**. Como `role` mora em `profiles`:

```
PATCH /rest/v1/profiles?id=eq.<próprio id>   {"role": "director"}
```

Resultado do teste:

```
[>>> PASSOU <<<] inspetor se promove a diretor      (1 linha alterada)
[>>> PASSOU <<<] supervisor se promove a diretor    (1 linha alterada)
```

Um Inspetor com o APK em mãos virava Diretor do próprio hospital e, a partir
daí, tinha acesso legítimo a tudo daquela unidade — inclusive validar
relatórios e exportar. Não é falha de interface: a RLS autorizava.

Os dois perfis foram revertidos ao papel original imediatamente após o teste, e
o estado final foi conferido.

**Corrigido** por trigger `trg_protege_campos_de_vinculo`: `role`, `hospital_id`
e `status` só mudam por Diretor ou Super Admin. O usuário continua editando
nome, telefone, cargo e foto normalmente — a correção preserva o valor antigo
desses três campos em vez de rejeitar o UPDATE inteiro.

### #3 — Supervisor valida relatório (alta)

A regra do projeto é explícita: quem valida é o Diretor. A interface obedece — o
botão Validar exige `role == 'director'`. A RLS, não:
`inspections_supervisor_update` dava UPDATE amplo em qualquer inspeção do
hospital.

```
[>>> PASSOU <<<] supervisor VALIDA relatório (só a UI barra?)   (1 linha)
```

**Este é o caso pedido em B3: proteção que existia apenas na interface.** Um
Supervisor podia validar o próprio trabalho por chamada direta, marcando como
conferido um relatório que ninguém conferiu — e a validação bloqueia edição
posterior, então o efeito é permanente.

A inspeção foi revertida para `submitted` logo após o teste.

**Corrigido** por trigger `trg_so_diretor_valida`: a transição para `validated`
exige papel `director`, independentemente da rota usada.

### O que a RLS já barrava corretamente

```
[BLOQUEADO] inspetor valida a própria inspeção enviada
[BLOQUEADO] ler tarefas de outro inspetor            (0 alheias de 25)
[BLOQUEADO] super_admin lê inspections / reports / tasks / responses
```

O Super Admin **não** alcança dado operacional, como a regra do projeto exige —
verificado nas quatro tabelas. E o Inspetor não enxerga tarefa de colega.

---

## B4. Storage — falha crítica de isolamento

O bucket `inspection-photos` é privado e o app lê sempre por *signed URL* de
1 hora (3600s), gerada no momento da exibição. Correto.

O problema estava nas políticas de `storage.objects`. Elas exigiam apenas
*"estar autenticado com um papel conhecido"* — **sem olhar o hospital**. O
próprio arquivo `migration_storage_policies.sql` documentava a decisão:
*"Não restringe por hospital_id aqui — a app já filtra por hospital_id em todas
as queries"*. Confiar no filtro do aplicativo é confiar no cliente.

Teste com o token do Inspetor do `HU-DEMO`, contra a pasta do `HU-UFPI`:

```
listar pasta do outro hospital   → 0 itens
upload em pasta alheia           → status 200  ← GRAVOU
remoção do arquivo alheio        → status 200  ← APAGOU
```

Listar não retornou nada, o que dá a impressão de isolamento. Mas **escrever e
apagar funcionaram**. Como o caminho é `{hospital_id}/{inspection_id}/{uuid}.jpg`
e é previsível, um usuário de qualquer unidade podia sobrescrever ou destruir a
evidência fotográfica de uma não conformidade de outro hospital — a prova
documental que a NR-32 exige. O arquivo de teste foi removido e a pasta
verificada como vazia.

**Corrigido**: as quatro políticas passaram a exigir
`(storage.foldername(name))[1] = get_my_hospital_id()::text`, usando a estrutura
de pastas que já existia. O DELETE ficou restrito ao Diretor — apagar evidência
não é operação de rotina do Inspetor.

Acerto do lado do bucket: o MIME é validado no servidor. Upload de `text/html`
foi rejeitado com `415 invalid_mime_type`, então não é possível hospedar
conteúdo arbitrário no bucket de fotos.

**Tempo de vida das URLs assinadas:** 1 hora. Uma URL vazada continua válida por
até 60 minutos mesmo que o acesso do usuário seja revogado no minuto seguinte.
Para fotos exibidas em tela é aceitável; está anotado como resíduo abaixo.

---

## B5. Sessão e aparelho perdido

- **Expiração:** access token de 1 hora, com refresh automático pelo
  `supabase_flutter`.
- **Renovação:** sem rede a renovação falha e o SDK **descarta** a sessão. O app
  trata isso deliberadamente (`OfflineStore.markSignedOut` separa saída real de
  falha de renovação), para não expulsar o Inspetor em campo.
- **O que fica no aparelho, em modo offline:** perfil em cache
  (`offline/profile.json`, inclui nome, e-mail, CPF e papel), pacotes de tarefa
  baixados (checklist, itens, inspeção, respostas), fila de envio e as fotos
  aguardando upload. Tudo em **JSON e JPEG em claro**, na pasta de documentos do
  app. O refresh token fica no `SharedPreferences`, também sem criptografia.

**Risco, em uma frase:** com o aparelho desbloqueado ou com acesso root, um
terceiro lê os dados da unidade que estavam em cache e usa a sessão salva até
que ela seja revogada — o cache é preservado deliberadamente no logout para
permitir o "Continuar offline", o que amplia a janela de exposição.

Mitigação existente: a pasta do app é isolada por sandbox do Android e
inacessível a outros aplicativos em aparelho não comprometido.

---

## B6. Validação de entrada

- **Tipo de arquivo:** validado **no servidor** (rejeitou `text/html` com 415), o
  que é a proteção que vale. A galeria continua bloqueada na captura de foto de
  inspeção; a exceção deliberada é a foto de perfil.
- **Injeção por texto livre:** não se aplica na forma clássica. Todas as consultas
  passam pelo PostgREST via `.eq()` / `.ilike()` / `.inFilter()`, que
  parametrizam. A tentativa `name=ilike.*'; DROP TABLE sectors;--*` foi barrada
  antes mesmo do banco, pelo WAF do Supabase (403). Não há concatenação de SQL
  no aplicativo.
- **Volume:** `limit=99999` devolveu apenas as 14 linhas visíveis ao perfil — a
  RLS limita o que existe, não o que se pede.
- **Tamanho de campo:** 23 campos já tinham `maxLength`. Faltava justamente no
  texto livre mais usado do app — a **observação da não conformidade**, que é
  salva automaticamente a cada digitação. **Corrigido**: teto de 1000 caracteres
  ali e 80 na busca de relatórios.

Lacuna remanescente: os campos de cadastro (`cadastro_screen`) validam formato,
mas não têm teto de tamanho. O risco é baixo, porque o Postgres já limita pelo
tipo da coluna.

---

## B7. Chaves e segredos no APK

Está embutido no aplicativo:

1. **URL do projeto Supabase** — público por natureza.
2. **`anon key`** — em `supabase_service.dart`, em texto claro.
3. **Senhas das contas demo** — em `demo_credentials.dart`, em texto claro.

**Não** há `service_role_key` no código Flutter. Verificado: a única chave é a
`anon`, e o comentário do arquivo alerta contra a outra. Este é o ponto correto
e importante.

**Por que a `anon key` exposta não dá acesso a dado de outro hospital.** Ela não
é uma credencial de acesso — é um identificador de projeto. Seu papel no JWT é
literalmente `"role": "anon"`. Toda linha devolvida pela API passa antes pela
RLS, que decide com base em `auth.uid()`, ou seja, em **quem fez login**, não em
qual chave foi usada. Com a `anon key` sozinha, sem autenticar, as sete tabelas
testadas devolveram zero linhas. É por isso que ela pode viajar no APK: ela abre
a porta do prédio, mas cada sala tem sua própria fechadura, e a fechadura é a
RLS. A `service_role_key`, ao contrário, **ignora** a RLS — e é por isso que
nunca pode estar no cliente.

**Ressalva sobre as senhas demo (#14):** com elas, qualquer pessoa que abra o
APK entra como Diretor do `HU-DEMO`. Para a defesa isso é intencional e o
hospital é de demonstração. Antes de qualquer uso real, `AppConfig.showDemoLogin`
deve ir para `false` e as senhas demo devem ser trocadas — o próprio código já
traz o aviso.

---

## B8. audit_log — o que é e o que não é registrado

**É registrado** (31 pontos no código, 21 ações distintas): criar/editar/apagar
hospital, criar e editar setor, vincular inspetor a setores, conceder e revogar
acesso compartilhado, atribuir tarefa e série, cancelar série, criar e desativar
checklist, arquivar e desarquivar, criar e editar template, editar e desativar
usuário, alterar senha, atualizar perfil e foto, submeter inspeção, validar
relatório, exportar PDF e Excel.

Cobertura boa nas ações de gestão, e as exportações são registradas — o que é
relevante, já que exportar é o momento em que o dado sai do sistema.

**Não é registrado, e deveria ser (#15):**

- **Login e logout.** Nenhuma chamada em `auth_provider` ou `login_screen`. Sem
  isso não há como saber quem entrou, de onde, nem investigar um acesso
  indevido — que é justamente o cenário em que o log importa. É a lacuna mais
  significativa.
- **Tentativa de login malsucedida.** Sem registro, ataque de força bruta não
  deixa rastro no aplicativo.
- **Envio de convite** (`convidar_usuario_screen`), embora aceitar o vínculo seja
  registrado.
- **Entrada no modo offline** e **sincronização da fila** — trabalho feito sem
  rede não deixa marca temporal de quando foi de fato transmitido.

Também vale registrar como constatação estrutural: até a correção #6, o
`hospital_id` da linha de log vinha do cliente, então um registro podia ser
gravado carimbado com outra unidade.

---

## B9. Correções aplicadas e correções recomendadas

### Aplicadas nesta rodada

**No banco** — arquivo `migration_security_hardening.sql`, idempotente, sem
alterar regra de negócio. **Precisa ser executado no SQL Editor:**

1. Trigger que impede alteração de `role`, `hospital_id` e `status` do próprio perfil.
2. Trigger que reserva a validação de relatório ao Diretor.
3. Políticas do bucket `inspection-photos` com isolamento por hospital; DELETE só para Diretor.
4. `audit_log` só aceita INSERT com o `hospital_id` de quem escreve.
5. Política explícita: Inspetor lê apenas os próprios registros de auditoria.
6. `reports` e `inspections`: INSERT do Inspetor exige o hospital correto.
7. `inspector_sectors`: não é possível vincular inspetor de outra unidade.
8. `access_requests`: o setor pedido tem de ser do próprio hospital.

**No aplicativo:**

9. `historico_screen.dart` — a consulta de inspeções filtrava por `inspector_id`
   mas **não** por `hospital_id`, contrariando a regra de ouro do projeto. A RLS
   já cobria o caso, então não havia vazamento; ainda assim a regra existe para
   que a proteção não dependa de uma única camada. Corrigido, aqui e na consulta
   de séries que a acompanha.
10. Teto de tamanho na observação da NC (1000) e na busca de relatórios (80).

### Recomendadas e **não** feitas, com o motivo

| Recomendação | Por que não foi feita agora |
|---|---|
| **Não devolver o CPF completo pela API** (#12). A máscara `***.***.XXX-XX` é aplicada na tela, mas `SELECT * FROM profiles` devolve os 11 dígitos, e várias telas usam `select()` sem projeção. O correto é uma *view* sem a coluna, ou colunas selecionadas explicitamente em cada consulta. | Exige tocar em todas as consultas de `profiles` e revisar cada tela que exibe usuário, na véspera da apresentação. É mudança ampla com risco de regressão em cadastro e vinculação — desproporcional a esta rodada. Dado sensível sob LGPD; deve ser o próximo item. |
| **Criptografar a sessão e o cache offline** (#13), com `flutter_secure_storage`. | Acrescenta dependência nativa e mexe no fluxo de sessão offline, que foi o mais delicado de estabilizar (ver o histórico de correções do modo offline). Alterá-lo agora arrisca reintroduzir o bug de "volta ao login em modo avião". |
| **Registrar login, logout e falha de autenticação no audit_log** (#15). | É a lacuna mais relevante do log e a correção é simples, mas escrever no `audit_log` durante o login exige cuidado com o momento em que o perfil ainda não foi carregado e com o modo offline, onde não há rede para gravar. Merece ser feito com teste próprio, não às pressas. |
| **Reduzir a validade da signed URL** de 3600s para ~300s. | Fotos são pré-carregadas antes de a tela abrir (`_preloadFotos`) e o PDF regenera a URL na exportação; reduzir o prazo pode quebrar a exibição em conexão lenta. Precisa de medição antes. |
| **Desligar o login demo** (`AppConfig.showDemoLogin = false`) e trocar as senhas (#14). | É requisito da própria apresentação que o modo demo funcione. Deve ser feito **antes de qualquer uso real**, não antes da defesa. |
| **Corrigir o perfil com `role` nulo** (#16). Existe em produção um perfil ("João Silva") com papel nulo. | É dado, não código. Não afeta a demonstração: sem papel, `get_my_role()` devolve nulo e todas as políticas negam — falha fechada. Deve ser vinculado ou desativado pelo Diretor. |
| **Bloqueio após N tentativas de login.** Hoje o app mostra mensagem genérica (correto), mas não limita tentativas. | Depende de configuração no painel do Supabase Auth, fora do código do aplicativo. |

---

## Conclusão

O modelo de segurança do InspecionaHU está apoiado no lugar certo: RLS no banco,
`anon key` no cliente, `service_role` ausente do aplicativo, log imutável por
construção e bloqueio de edição após envio garantido por política, não por tela.
O isolamento entre hospitais — o requisito que sustenta a proposta multiunidade —
resistiu a todas as tentativas de leitura cruzada.

As duas falhas críticas encontradas têm a mesma origem: uma política escrita em
termos de *"quem é o dono da linha"* sem dizer *"quais colunas"* (o `role`
editável), e uma política escrita em termos de *"está autenticado"* sem dizer
*"de qual hospital"* (o bucket de fotos). Ambas são corrigíveis no banco, sem
mudar uma linha do aplicativo, e a correção está pronta em
`migration_security_hardening.sql`.

O achado que mais merece atenção na defesa não é técnico, é de método: a
validação de relatório pelo Supervisor estava barrada apenas na interface e
passou despercebida porque, pela tela, o comportamento estava correto. Foi
preciso chamar a API diretamente para descobrir. É a diferença entre o
aplicativo se comportar bem e o sistema ser seguro.
