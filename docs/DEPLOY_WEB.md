# Deploy Web — InspecionaHU

Como gerar e hospedar a versão web do app. O repositório contém o alvo web do Flutter (`web/index.html`, `web/manifest.json`, ícones); **não há arquivo de configuração de deploy versionado** (Dockerfile, railway.json) — o deploy é o publish estático da pasta de build.

## 1. Build

```
flutter build web --release
```

- Saída: `build/web/` (conteúdo 100% estático — HTML, JS, assets, fontes).
- Base href: por padrão o app espera ser servido na **raiz** do domínio. Se for hospedado em subcaminho (ex.: `https://host/inspecionahu/`), use `flutter build web --release --base-href /inspecionahu/`.

## 2. Variáveis de ambiente do Supabase

Não há variáveis de ambiente em tempo de build ou execução: a URL e a `anon key` do Supabase são **constantes** em [lib/core/services/supabase_service.dart](../lib/core/services/supabase_service.dart) e são embutidas no bundle.

- Isso é seguro por design: a `anon key` é pública e toda a segurança real está nas políticas RLS do banco. A `service_role_key` **nunca** entra no app.
- Consequência prática: **trocar de projeto Supabase = editar as duas constantes nesse arquivo e rebuildar**. Não há como trocar a instância sem novo build.

## 3. Hospedagem no Railway (arranjo usado no desenvolvimento)

O Railway serve o conteúdo de `build/web/` como site estático. Um arranjo simples e reproduzível:

1. Criar um projeto no Railway e um serviço apontando para o repositório (ou para uma pasta com o build).
2. Como o Flutter não builda no ambiente padrão do Railway sem imagem própria, o caminho mais simples é **buildar localmente** e publicar só o estático. Duas opções:
   - **Opção A (serviço estático):** subir o conteúdo de `build/web/` em um serviço com um servidor estático mínimo, por exemplo Caddy — `Dockerfile` de 2 linhas:
     ```dockerfile
     FROM caddy:alpine
     COPY build/web /usr/share/caddy
     ```
   - **Opção B (Nixpacks + serve):** colocar `build/web` no deploy e definir o start command `npx serve -s build/web -l $PORT`.
3. Configurações no Railway:
   - **PORT**: o Railway injeta `$PORT`; o servidor escolhido deve escutá-la (Caddy: usar `CMD caddy file-server --root /usr/share/caddy --listen :$PORT`, ou mapear via `EXPOSE`).
   - **Domínio**: gerar o domínio público (Settings → Networking → Generate Domain) ou apontar domínio próprio.
   - Não há variável de ambiente do app a configurar (seção 2).
4. **No Supabase** (painel → Authentication → URL Configuration): incluir o domínio público do Railway em *Site URL / Redirect URLs*, senão links de confirmação/recuperação de senha apontam para o host errado.

## 4. Transição da hospedagem para a instituição

Quando a hospedagem passar para a instituição, muda o seguinte:

1. **Projeto Supabase de produção**: criar a instância institucional, rodar `supabase_setup.sql` + migrations (ordem em CLAUDE.md/`docs/`), e atualizar `supabaseUrl` e `supabaseAnonKey` em `lib/core/services/supabase_service.dart` → rebuild (`flutter build web --release`).
2. **Modo demo**: desligar (`AppConfig.showDemoLogin = false` em `lib/core/config/app_config.dart`) antes do build público.
3. **Domínio institucional**: hospedar `build/web/` no servidor da instituição (qualquer servidor estático serve: nginx, Apache, IIS, ou o próprio Railway em conta institucional) e refazer a configuração de URLs no painel do Supabase (item 3.4).
4. **HTTPS obrigatório**: câmera no navegador (`getUserMedia`) só funciona em contexto seguro — o domínio final precisa de TLS.
5. **Atualizações**: cada deploy é um novo build estático; recomenda-se limpar cache/CDN após publicar (o Flutter gera nomes com hash, mas `index.html` e `flutter_service_worker.js` precisam ser revalidados).
