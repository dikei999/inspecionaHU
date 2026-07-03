# Firebase Cloud Messaging — Guia de Configuração

O código de FCM já está pronto no app, isolado atrás da flag
`FirebaseConfig.enabled` ([lib/core/services/firebase_config.dart](../lib/core/services/firebase_config.dart)).
Enquanto o Firebase não for configurado, a flag fica `false` e o app funciona
normalmente — as notificações em tempo real chegam via **Supabase Realtime**
com o app aberto. O FCM adiciona o push com o **app fechado**.

Siga os passos abaixo **na ordem**.

---

## 1. Criar o projeto no Firebase Console

1. Acesse https://console.firebase.google.com e clique em **Adicionar projeto**.
2. Nome sugerido: `inspecionahu` (Google Analytics é opcional — pode desativar).
3. Dentro do projeto, clique no ícone **Android** para registrar o app:
   - **Nome do pacote Android**: `com.example.inspecionahu`
     (confira em `android/app/build.gradle.kts`, campo `applicationId` —
     se você trocar o applicationId antes de publicar, registre o novo valor).
   - Apelido e SHA-1 podem ficar em branco por enquanto.

## 2. Baixar o google-services.json

1. Ao final do registro, baixe o arquivo **google-services.json**.
2. Coloque-o exatamente em:
   ```
   android/app/google-services.json
   ```
3. **Não** commitar este arquivo em repositório público (o repo atual é
   privado, então é aceitável — mas confira antes).

## 3. Aplicar o plugin google-services no Gradle

> ⚠️ Só faça isto DEPOIS de colocar o `google-services.json` — aplicar o
> plugin sem o arquivo quebra o build. Foi por isso que ele não foi aplicado
> ainda.

**`android/settings.gradle.kts`** — no bloco `plugins { ... }`, adicionar:

```kotlin
id("com.google.gms.google-services") version "4.4.2" apply false
```

**`android/app/build.gradle.kts`** — no bloco `plugins { ... }` do topo, adicionar:

```kotlin
id("com.google.gms.google-services")
```

Depois rode `flutter clean && flutter build apk --debug` para confirmar que o
build passa. A partir daí, `FirebaseConfig.tryInitialize()` vai conseguir
inicializar e `FirebaseConfig.enabled` fica `true` automaticamente.

## 4. Coluna fcm_token no Supabase

O app salva o token do dispositivo em `profiles.fcm_token`. Rode no SQL Editor:

```sql
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS fcm_token TEXT;
```

## 5. Edge Function de envio (service account)

O envio do push é feito no servidor: uma Edge Function assina a API HTTP v1 do
FCM usando a **service account** do Firebase.

1. No Firebase Console: **Configurações do projeto → Contas de serviço →
   Gerar nova chave privada** (baixa um JSON).
2. No Supabase: **Edge Functions → Secrets**, criar o secret
   `FCM_SERVICE_ACCOUNT` colando o conteúdo do JSON inteiro.
3. Criar a função `send-push` (esqueleto):

```ts
// supabase/functions/send-push/index.ts
// Disparada por Database Webhook no INSERT de public.notifications:
// lê o fcm_token do destinatário e envia via FCM HTTP v1.
import { JWT } from "npm:google-auth-library@9";

const serviceAccount = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT")!);

Deno.serve(async (req) => {
  const { record } = await req.json(); // linha inserida em notifications

  // 1. Busca o fcm_token do destinatário (use SUPABASE_SERVICE_ROLE_KEY,
  //    disponível automaticamente no ambiente da Edge Function)
  // 2. Se não houver token, encerra silenciosamente
  // 3. Autentica com a service account e faz POST em
  //    https://fcm.googleapis.com/v1/projects/<PROJECT_ID>/messages:send
  //    com { message: { token, notification: { title, body },
  //          data: { type, reference_id } } }

  return new Response("ok");
});
```

4. Deploy: `supabase functions deploy send-push`.
5. Criar o **Database Webhook** (Dashboard → Database → Webhooks):
   - Tabela: `public.notifications`, evento: `INSERT`
   - Tipo: Supabase Edge Function → `send-push`

Assim **toda** notificação inserida (pelos triggers ou pelo pg_cron da
`migration_notifications.sql`) vira push automaticamente, sem duplicar lógica.

## 6. Checklist final

- [ ] `google-services.json` em `android/app/`
- [ ] Plugin `com.google.gms.google-services` aplicado nos dois Gradle
- [ ] Build passa (`flutter build apk --debug`)
- [ ] Coluna `profiles.fcm_token` criada
- [ ] Secret `FCM_SERVICE_ACCOUNT` configurado
- [ ] Edge Function `send-push` publicada + webhook em `notifications`
- [ ] Teste: validar um relatório e conferir o push com o app fechado
