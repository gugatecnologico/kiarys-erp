# Kiarys ERP

Sistema de vendas e estoque da Kiarys Moda Feminina (Juazeiro do Norte, CE).
Projeto separado da Alyra Joias — outro repo, outro banco, outras contas.
Brief completo: `KIARYS_ERP_BRIEF.md` (histórico da conversa que originou
este repositório).

## Arquitetura

- **Banco + Auth:** [Supabase](https://supabase.com) (plano Free).
- **Frontend:** Vite + React + TypeScript, PWA, hospedado no
  [Cloudflare Pages](https://pages.cloudflare.com) (plano Free).
- **Sem backend próprio.** Toda regra crítica (venda, cancelamento,
  entrada, caixa) é uma função Postgres `SECURITY DEFINER`, chamada
  direto pelo cliente Supabase via RPC.
- **Domínio:** subdomínio de `kiarabijous.com.br` (domínio antigo da Alyra,
  hoje sem uso — ver "Domínio" abaixo), CNAME para o Cloudflare Pages.

### Acesso ao banco, em duas camadas

1. `kiarys` (onde moram as tabelas) precisa estar em **Settings > API >
   Exposed schemas** do projeto Supabase, ao lado de `public` — senão o
   PostgREST não resolve as RPCs (`supabase.rpc('registrar_venda', …)`
   dá 404 antes de checar qualquer permissão).
2. Expor o schema **não** libera acesso: toda tabela de `kiarys` tem RLS
   ligado sem nenhuma policy de escrita e teve os `GRANT` padrão
   revogados de `anon`/`authenticated` (migration `0014_permissoes.sql`).
   Só ~15 funções RPC recebem `EXECUTE`, e um punhado de views em
   `public` recebe `SELECT`. Uma vendedora chamando a API REST direto em
   `/rest/v1/venda_itens` ou `/rest/v1/variacoes` recebe 401/403, mesmo
   sabendo o nome da tabela.

Ver o comentário no topo de `supabase/migrations/0001_base.sql` e de
`0014_permissoes.sql` para o raciocínio completo.

## Deploy

### 1. Supabase

1. Crie um projeto novo em [supabase.com](https://supabase.com) (plano Free).
2. `supabase link --project-ref <ref>`
3. `supabase db push` — aplica as migrations em `supabase/migrations/`.
4. Em **Settings > API > Exposed schemas**, adicione `kiarys` (além de
   `public`, que já vem por padrão).
5. Em **Authentication > Providers**, deixe só e-mail/senha. Em
   **Authentication > Settings**, desligue "Enable email signup" público
   — o cadastro de vendedora é sempre pelo admin (ver abaixo).
6. Copie a **URL do projeto** e a **anon key** (Settings > API) para o
   `.env` do frontend (`web/.env`, a partir de `web/.env.example`).

O plano Free do Supabase **pausa o projeto após ~7 dias sem uso**. Numa
loja que vende todo dia isso não deve acontecer, mas se pausar: abra o
projeto no painel do Supabase e clique em "Restore" — não há perda de
dado, só o tempo do restore (minutos).

### 2. Frontend (Cloudflare Pages)

1. Conecte o repositório no Cloudflare Pages.
2. Build command: `npm run build` · diretório de saída: `web/dist` ·
   diretório raiz do projeto: `web`.
3. Variáveis de ambiente do build: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`.
4. Domínio: em **Custom domains** do projeto no Cloudflare Pages, adicione
   o subdomínio escolhido (ex. `erp.kiarabijous.com.br`) e crie o CNAME
   correspondente no DNS do GoDaddy, apontando para o host que o
   Cloudflare Pages indicar. Isso não depende do Railway nem entra na
   fila de domínios de lá (ver "Domínio" abaixo).

### 3. Primeiro admin

Não existe autocadastro público (`enable_signup = false`). Para criar o
primeiro admin:

1. No painel do Supabase, **Authentication > Users > Add user** — crie
   com e-mail e senha. O trigger `on_auth_user_created` já cria um perfil
   em `kiarys.perfis`, mas **inativo** e com papel `vendedora`.
2. No **SQL Editor** do Supabase, rode:
   ```sql
   update kiarys.perfis set ativo = true, papel = 'admin'
   where id = (select id from auth.users where email = 'SEU_EMAIL_AQUI');
   ```
3. A partir daí, o próprio admin ativa e configura as demais contas pelo
   painel — sem precisar mais do SQL Editor.

### 4. Backup

`scripts/backup.sh` faz `pg_dump` do schema `kiarys` para um `.sql.gz`.
O workflow `.github/workflows/backup.yml` roda isso toda segunda e sobe o
arquivo como artifact do Actions (retenção de 90 dias) — configure o
secret `SUPABASE_DB_URL` do repositório (Settings > Database > Connection
string, modo "Session", em Settings do projeto Supabase). Pode rodar
manual também: `SUPABASE_DB_URL=... bash scripts/backup.sh`.

## Domínio

`kiarabijous.com.br` é o domínio antigo da Alyra Joias (ex-Kiara Bijous),
hoje sem uso oficial — está no GoDaddy, e o pendência de redirecioná-lo
pro domínio novo da Alyra está travada por outro motivo (vaga de domínio
no Railway do outro repositório) sem relação com este projeto. Usar um
**subdomínio** dele para a Kiarys ERP (ex. `erp.kiarabijous.com.br`) não
depende do Railway nem interfere nesse redirecionamento — é só um CNAME
novo apontando pro Cloudflare Pages.

## Desenvolvimento local

```bash
supabase start          # sobe Postgres + Auth + Studio locais
supabase db reset        # aplica migrations + supabase/seed.sql
cd web && npm install && npm run dev
```

`supabase/seed.sql` cria 3 usuárias de teste (`admin@kiarys.dev`,
`gerente@kiarys.dev`, `vendedora@kiarys.dev`, senha `teste123`), um
catálogo de exemplo (5 produtos × 4 tamanhos × 2 cores) e um caixa aberto.

### Testes

```bash
supabase test db                          # pgTAP: permissões, ledger, venda, caixa, entrada, fuso
cd tests/concorrencia && npm install && npm test   # 2 conexões reais, última peça
```

## Decisões que ajustam o brief

Registradas aqui porque mudam o comportamento do sistema em relação ao
que o brief original descrevia — para não se perderem numa conversa.

- **Caixa único da loja, não um caixa por vendedora.** A gaveta é física e
  compartilhada; um fechamento "às cegas" por pessoa não faria sentido
  com uma gaveta só. `caixas` não tem `vendedora_id`: tem
  `usuario_abertura`/`usuario_fechamento` (quem mexeu na gaveta), e cada
  `vendas.vendedora_id` registra quem vendeu cada peça — a comissão e o
  ranking por vendedora vêm daí, não do caixa.
- **Gerente não vê custo/margem nem cadastra, por padrão.** Os dois são
  ligáveis em `configuracoes` (`gerente_ve_custo`, `gerente_cadastra`)
  pelo admin, sem precisar de migration nova.
- **Estorno em dinheiro sai do caixa aberto de quem cancelou.** Se a
  venda cancelada tinha pagamento em dinheiro e não há caixa aberto no
  momento, `cancelar_venda` recusa (pede pra abrir o caixa antes) — o
  dinheiro devolvido physicamente só existe se há uma gaveta aberta pra
  tirar dele.
- **Cloudflare Pages em vez da Vercel.** O plano Hobby da Vercel proíbe
  uso comercial; uma loja é uso comercial. Cloudflare Pages Free permite
  e não limita banda.
- **Cadastro de usuária sempre pelo admin**, nunca autocadastro público —
  ver "Primeiro admin" acima. Evita que qualquer e-mail vire conta com
  acesso, já que não há backend próprio para intermediar isso com mais
  cuidado (Edge Function fica como opção futura, se incomodar o fluxo
  manual pelo painel do Supabase).

## Estrutura do repositório

```
supabase/
  migrations/      0001–0014, nesta ordem (ver cabeçalho de cada arquivo)
  tests/           pgTAP — roda com `supabase test db`
  seed.sql         dado de desenvolvimento
tests/concorrencia/ script Node com 2 conexões reais (não cabe em pgTAP)
web/               frontend (Vite + React + TS) — ainda não iniciado,
                   aguardando aprovação das migrations
scripts/backup.sh
.github/workflows/ ci.yml (migrations + concorrência + build do web),
                   backup.yml (dump semanal)
```

## Ordem das migrations

| # | Arquivo | O que cria |
|---|---|---|
| 0001 | `base.sql` | Schema, extensões, tipos, funções de apoio (`perfil_atual`, `eh_admin`, `pode_ver_custo`, `dia_local`) |
| 0002 | `perfis_config.sql` | `perfis` (+ trigger em `auth.users`), `configuracoes`, `taxas_pagamento` |
| 0003 | `catalogo.sql` | `categorias`, `colecoes`, `fornecedores`, `produtos`, `variacoes`, `preco_efetivo()` |
| 0004 | `estoque.sql` | `movimentos_estoque` (insert-only) + `estoque_saldos` (cache por trigger) |
| 0005 | `entradas.sql` | `entradas`, `entrada_itens` |
| 0006 | `clientes.sql` | `clientes` |
| 0007 | `caixa.sql` | `caixas` (único por vez, ver decisão acima), `caixa_movimentos` |
| 0008 | `vendas.sql` | `vendas`, `venda_itens`, `pagamentos` |
| 0009 | `auditoria.sql` | `auditoria` + trigger genérico em `variacoes`/`perfis` |
| 0010 | `rpc_caixa.sql` | `abrir_caixa`, `movimentar_caixa`, `fechar_caixa` |
| 0011 | `rpc_venda.sql` | `registrar_venda`, `cancelar_venda` |
| 0012 | `rpc_estoque.sql` | `criar_produto_com_grade`, `importar_produtos`, `registrar_entrada`, `ajustar_estoque`, `alterar_precos` |
| 0013 | `api_views.sql` | Views de leitura em `public` |
| 0014 | `permissoes.sql` | RLS default-deny + `GRANT`/`REVOKE` + policies |

## v2 / v3

Trocas + vale-troca, condicional, crediário, comissão detalhada,
inventário assistido, curva ABC, peças paradas, ruptura de grade — ver
seção 8/11 do brief. Os tipos de enum já existem desde `0001` para não
quebrar dado histórico quando essas tabelas nascerem; as tabelas em si
só entram quando o v2 começar.
