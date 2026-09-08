# Modo offline — InspecionaHU

> Bloco 6 da rodada de fechamento. Objetivo: o Inspetor responde checklist em
> campo sem internet.

## Limitação principal (6.7)

**O primeiro login exige internet.** É uma limitação de projeto, não um bug.

O app precisa de uma sessão do Supabase Auth e do perfil do usuário (papel,
hospital) para saber o que mostrar. Nenhum dos dois existe antes do primeiro
login bem-sucedido. A partir daí:

- a sessão do Supabase já era persistida pelo `supabase_flutter`;
- o perfil passa a ser gravado localmente a cada carga bem-sucedida;
- nas aberturas seguintes, sem rede, o app entra com o perfil em cache.

Não há botão de "entrar offline" na tela de login — a entrada offline é
automática e só acontece quando existe sessão válida **e** perfil em cache.

Ao **sair da conta**, o cache do perfil e todos os dados de trabalho
(tarefas baixadas, fila, fotos) são apagados: o próximo usuário deste
aparelho não herda nada do anterior. Por isso o aviso na confirmação de
logout diz que será preciso internet para entrar de novo.

## O que funciona sem rede

| Recurso | Offline |
|---|---|
| Abrir o app com sessão existente | Sim (perfil em cache) |
| Abrir checklist já baixado | Sim |
| Responder C / NC / NA | Sim |
| Escrever observação | Sim |
| Tirar foto pela câmera | Sim (fica na fila) |
| Enviar a inspeção (finalizar) | Não — exige rede |
| Primeiro login | Não |
| Iniciar uma tarefa nunca aberta com rede | Não (ver abaixo) |

### Por que iniciar uma tarefa nova offline não funciona

A linha em `inspections` é criada no servidor (`_createInspection`), e as
respostas referenciam esse `inspection_id`. Criar a inspeção offline exigiria
gerar o id no aparelho e sincronizar a inserção da inspeção antes das
respostas — mudança no caminho que o fluxo online usa hoje.

O item 6.6 é explícito: se algum ponto do offline ameaçar o fluxo online,
parar e avisar em vez de improvisar. **Foi o que se fez.**

Na prática o efeito é pequeno: basta o Inspetor **abrir a tarefa uma vez com
internet** (ou tocar em "Baixar para uso offline", que já cria a inspeção) e
dali em diante ela funciona sem rede.

## Como usar

1. **Com internet**, no painel do Inspetor, toque no ícone de download no card
   da tarefa. O checklist inteiro (itens, referência da NR-32, criticidade,
   exigência de foto) é salvo no aparelho.
2. A seção **"Disponível offline"**, no topo da lista, mostra o que já está
   salvo.
3. **Sem internet**, abra a tarefa normalmente: respostas, observações e
   fotos são gravadas no aparelho.
4. Ao voltar a conexão, o envio é automático. A faixa fina no topo mostra
   quantas respostas estão na fila e o resultado do envio.

## Como funciona por dentro

### Armazenamento (`lib/core/services/offline_store.dart`)

Arquivos JSON na pasta de documentos do app, via `path_provider`. Drift está
no pubspec, mas exigiria `build_runner` e code generation; o volume aqui é
pequeno (uma tarefa, dezenas de respostas) e arquivo resolve sem acrescentar
um passo de build.

```
offline/profile.json          perfil em cache
offline/tasks/[taskId].json   pacote baixado
offline/queue/[opId].json     fila de envio
offline/photos/[uuid].jpg     foto aguardando upload
```

### Idempotência (6.4)

Duas garantias, uma na gravação e outra no envio:

1. o id da operação é `resp_[inspectionId]_[checklistItemId]` — reescrever a
   mesma resposta **sobrescreve o arquivo** em vez de empilhar duplicata;
2. o envio é `upsert` com `onConflict: 'inspection_id,checklist_item_id'` —
   o mesmo que o fluxo online já usava, então reenviar não duplica linha.

A fila é drenada **em ordem** de `queued_at`.

### Foto nunca é descartada (6.3)

Antes, falha de upload limpava o thumbnail local e a foto se perdia. Agora,
assim que é comprimida, a foto sai do diretório temporário do sistema (que o
Android pode limpar) e vai para a pasta do app, junto do destino no Storage.
Ela só é apagada **depois** do upload confirmado. Se o upload falha, a
operação inteira fica na fila e é tentada de novo.

### Faixa de status (6.5)

`lib/widgets/connection_banner.dart`, montada no `builder` do `MaterialApp`,
portanto global. Aparece só quando há o que dizer: sem conexão, com pendência
na fila, ou logo após um envio. **Online e com fila vazia, ela não ocupa um
pixel.**

## O que não mudou (6.6)

O caminho online é o mesmo de antes: `upsert` direto, upload direto, retry com
backoff. As alterações ficaram todas nos ramos de falha e de ausência de rede
— que antes só marcavam erro na tela e perdiam o trabalho.
