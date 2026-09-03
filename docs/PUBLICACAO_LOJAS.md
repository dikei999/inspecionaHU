# Publicação nas Lojas — Google Play e App Store

Guia específico do **InspecionaHU** para publicação futura pela instituição.

> **Importante:** a publicação **não foi realizada** durante o projeto. Este guia é um artefato de transferência de conhecimento — descreve exatamente o que falta para publicar este app, no estado em que ele está no repositório.

## 1. Estado atual do projeto (o que precisa mudar antes de publicar)

| Item | Estado atual | Ação antes de publicar |
|------|--------------|------------------------|
| `applicationId` / `namespace` | `com.example.inspecionahu` em `android/app/build.gradle.kts` | Trocar por identificador institucional definitivo (ex.: `br.ebserh.huufpi.inspecionahu`). A Play Store **rejeita** `com.example.*`. O id não pode mais mudar depois da 1ª publicação |
| Assinatura release | `signingConfig = signingConfigs.getByName("debug")` | Criar keystore própria e configurar signing de release (seção 3) |
| Versão | `version: 1.0.0+1` no `pubspec.yaml` (formato `versionName+versionCode`) | Incrementar o `+N` (versionCode) a cada envio à loja; o nome (`1.0.0`) é livre |
| Modo demo | `AppConfig.showDemoLogin = true` em `lib/core/config/app_config.dart` | Mudar para `false` no build de loja |
| Permissões Android | `INTERNET`, `CAMERA` e `POST_NOTIFICATIONS` declaradas em `android/app/src/main/AndroidManifest.xml` | Conferir que continuam após qualquer alteração |
| iOS | O diretório `ios/` do template Flutter precisa ser gerado/configurado em um Mac (`flutter create --platforms=ios .` se ausente, bundle id, `NSCameraUsageDescription` no `Info.plist`) | Obrigatório para App Store |

## 2. Contas de desenvolvedor e custos

| Loja | Conta | Custo (verificar valor vigente) | Observações |
|------|-------|--------------------------------|-------------|
| Google Play | Google Play Console (conta de organização, com verificação D-U-N-S/CNPJ) | Taxa única (~US$ 25) | Conta institucional, não pessoal — a titularidade é permanente |
| App Store | Apple Developer Program (organização, exige D-U-N-S) | Anual (~US$ 99/ano) | Build e envio exigem macOS com Xcode |

## 3. Assinatura Android (keystore)

1. Gerar a keystore (guardar em local seguro da instituição, **fora do repositório**):
   ```
   keytool -genkey -v -keystore inspecionahu-release.keystore -alias inspecionahu -keyalg RSA -keysize 2048 -validity 10000
   ```
2. Criar `android/key.properties` (não versionar):
   ```
   storePassword=***
   keyPassword=***
   keyAlias=inspecionahu
   storeFile=/caminho/para/inspecionahu-release.keystore
   ```
3. Em `android/app/build.gradle.kts`, carregar `key.properties`, declarar `signingConfigs.release` e trocar
   `signingConfig = signingConfigs.getByName("debug")` por `getByName("release")`
   (padrão documentado em docs.flutter.dev/deployment/android).
4. Recomendado: aderir ao **Play App Signing** (o Google guarda a chave de assinatura final; a keystore local vira "upload key").

> Perder a keystore/upload key sem o Play App Signing habilitado impede publicar qualquer atualização do app.

## 4. Builds de loja

```
# Google Play exige AAB (não APK):
flutter build appbundle --release
# artefato: build/app/outputs/bundle/release/app-release.aab

# iOS (em macOS, após configurar ios/):
flutter build ipa --release
```

As credenciais do Supabase são constantes em `lib/core/services/supabase_service.dart` (apenas `anon key` — a segurança real é o RLS), então o build não requer `--dart-define`.

## 5. Exigências das lojas para este app

- **Política de privacidade (obrigatória nas duas lojas):** URL pública descrevendo os dados tratados pelo app — nome, e-mail, CPF (exibido mascarado), fotos de inspeção (bucket privado com signed URL) e logs de auditoria, armazenados no Supabase. A instituição deve publicar esse documento (LGPD) e informar a URL na ficha do app.
- **Declaração de uso de câmera:** o app usa a câmera exclusivamente para registrar fotos de inspeção e foto de perfil; a galeria é bloqueada por regra de negócio nas inspeções. Na Play Store, declarar em *App content → Data safety* (fotos coletadas, associadas ao usuário, não compartilhadas com terceiros). Na App Store, preencher `NSCameraUsageDescription` com texto equivalente em português.
- **Seção Data Safety (Play) / App Privacy (Apple):** declarar coleta de identificadores de conta (e-mail), informações pessoais (nome, CPF) e fotos; finalidade "funcionalidade do app"; criptografia em trânsito (HTTPS/Supabase).
- **Login de revisão:** as lojas exigem credenciais de teste — usar as contas demo (`inspetor@demo.com` / `demo1234` etc.) ou contas de revisão dedicadas, com o backend demo ativo durante a análise.
- **Público-alvo:** app corporativo/profissional (18+), sem anúncios, sem compras no app.

## 6. Sequência sugerida de publicação (Android primeiro)

1. Ajustar `applicationId`, keystore e `showDemoLogin` (seção 1 e 3).
2. `flutter build appbundle --release` e teste do AAB via *internal testing* no Play Console.
3. Preencher ficha da loja: descrição, capturas de tela (telefone e tablet), ícone 512px, banner, política de privacidade, Data safety, classificação de conteúdo.
4. Faixa interna → faixa fechada (piloto HU-UFPI) → produção.
5. iOS depois, quando houver Mac + conta Apple: gerar `ios/`, configurar bundle id e certificados no Xcode, `flutter build ipa`, envio via Transporter/Xcode e revisão da App Store.
