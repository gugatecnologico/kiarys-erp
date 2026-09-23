# Kiarys ERP

Sistema de vendas e estoque da Kiarys Moda Feminina (Juazeiro do Norte, CE).
Projeto separado da Alyra Joias — outro repo, outro banco, outras contas
(mesmo Railway, mas serviços próprios). Brief completo:
`KIARYS_ERP_BRIEF.md` (histórico da conversa que originou este repositório).

## Arquitetura

- **Banco:** Postgres, como serviço no Railway (mesmo projeto/organização
  do resto do GVA, plano Pro já em uso).
- **API:** serviço Node/Express próprio (`api/`), também no Railway —
  mesma stack que o resto do GVA já usa (`kiara_instagram.js` etc). É
  quem fala com o navegador; o Postgres nunca é exposto direto.
- **Frontend:** Vite + React + TypeScript, PWA — servido como site
  estático pelo próprio Railway (ou por trás da mesma API).
- **Sem Supabase.** Toda regra crítica (venda, cancelamento, entrada,
  caixa, login) é função Postgres `SECURITY DEFINER`, chamada pela API
  via `pg` — nunca direto do navegador.
- **Domínio:** subdomínio de `kiarabijous.com.br` (domínio antigo da
  Alyra, hoje sem uso — ver "Domínio" abaixo), configurado como Custom
  Domain do serviço no Railway.

### Autenticação, sem Supabase Auth

Não existe mais um serviço de Auth separado — `kiarys.perfis` é ao mesmo
tempo identidade (email + `senha_hash`, bcrypt via `pgcrypto`) e perfil de
negócio (papel, comissão, limite de desconto). O fluxo:

1. Navegador manda email+senha pra `POST /auth/login` na API.
2. A API chama `select kiarys.autenticar($1, $2)` (a única função que
   ainda não exige sessão) e, se bater, **emite ela mesma** um JWT
   assinado (`jsonwebtoken`, secret em variável de ambiente) — o banco
   não sabe o que é um JWT, só devolve o perfil.
3. Toda requisição seguinte manda esse JWT; um middleware da API valida
   assinatura+validade, extrai o `id` do perfil, e — antes de rodar
   qualquer RPC/consulta — seta `select set_config('app.uid', $1, true)`
   **na mesma transação**. É esse `app.uid` que `kiarys.uid()`
   (`db/migrations/0001_base.sql`) lê, e é o que RLS usa pra filtrar.

### Acesso ao banco, em duas camadas

1. A API se conecta ao Postgres com **um único role**, `kiarys_app`
   (criado em `0014_permissoes.sql`) — não existe um role por papel de
   usuária no Postgres. Quem diferencia admin/gerente/vendedora é RLS
   lendo `kiarys.uid()`, não o role de conexão.
2. Mesmo a API sendo código confiável (não é o navegador), as tabelas de
   `kiarys` têm RLS ligado sem nenhuma policy de escrita, e os `GRANT`
   padrão são revogados de `kiarys_app` — só ~18 RPCs recebem `EXECUTE` e
   um punhado de views em `public` recebe `SELECT`. Isso é defesa em
   profundidade (brief, seção 2): um bug de rota na API que esqueça um
   `WHERE vendedora_id = ...` ainda esbarra em RLS; um SELECT solto numa
   rota genérica ainda esbarra no `GRANT` que falta.

Ver o comentário no topo de `db/migrations/0001_base.sql` e de
`0014_permissoes.sql` para o raciocínio completo.

## Status

Banco e API já estão no ar no Railway (projeto `kiarys-erp`, mesmo
workspace do resto do GVA): Postgres migrado (14 migrations), API
respondendo em `https://api-production-16a21.up.railway.app` (URL
provisória do Railway — troca pra `erp.kiarabijous.com.br` quando o
domínio for configurado, ver "Domínio"). Primeiro admin criado
(`gugabezerra20@gmail.com`) — **trocar a senha temporária assim que
logar**, via `POST /auth/trocar-senha`. Frontend (`web/`) ainda não
existe.

## Deploy (Railway)

### 1. Banco (Postgres)

1. No projeto do Railway, **New > Database > Postgres** — cria o serviço
   e já expõe uma `DATABASE_URL` interna.
2. Aplique as migrations: `DATABASE_URL=<a do serviço Postgres> npm run
   db:migrate` (local, apontando pra connection string pública do
   Postgres — Railway mostra em **Connect**).
3. **Troque a senha do role `kiarys_app`** (a migration cria com um
   placeholder): `psql "$DATABASE_URL" -c "alter role kiarys_app
   password '<senha forte>'"`. Guarde essa senha — é a que a API vai usar.

### 2. API (`api/`)

Serviço Node novo no Railway, root directory `api/`, builder
**Dockerfile** (`api/Dockerfile`) — não Railpack/Nixpacks. O repo tem 3
`package.json` irmãos (raiz, `api/`, `tests/concorrencia/`) sem
`workspaces` declarado, e a detecção automática de monorepo do Railpack
escolheu o pacote errado (instalou as dependências de
`tests/concorrencia` — só `pg` — em vez das da API). Dockerfile explícito
resolve isso sem ambiguidade. Variáveis de ambiente:

| Variável | Valor |
|---|---|
| `DATABASE_URL` | `postgresql://kiarys_app:<senha do passo 1>@<host interno do Postgres>/<db>` — use o host **interno** do Railway (`*.railway.internal`), não o público, já que API e banco estão no mesmo projeto |
| `JWT_SECRET` | uma string aleatória longa (`openssl rand -base64 48`) — nunca reaproveitar de outro serviço |
| `PORT` | Railway seta sozinho |

### 3. Frontend (`web/`)

Serviço estático (ou Static Site do Railway) apontando pra `web/`, build
`npm run build`, saída `web/dist`. Variável de ambiente do build:
`VITE_API_URL` (a URL pública do serviço da API).

### 4. Domínio

Em **Settings > Networking > Custom Domain** do serviço da API (ou do
frontend, dependendo de qual serve a página — decidir na hora), adicione
o subdomínio escolhido (ex. `erp.kiarabijous.com.br`). O Railway devolve
um CNAME pra criar no DNS do GoDaddy. Com o plano Pro isso não esbarra
mais no limite de 2 domínios por serviço que travava a P46 do
`kiara-catalogo` (esse outro domínio segue como pendência separada, sem
relação com este projeto).

### 5. Primeiro admin

Não existe rota pública de cadastro — `criar_usuaria` exige
`kiarys.eh_admin()`. Para criar o primeiro admin, direto no banco:

```sql
select kiarys.criar_usuaria(
  'Seu Nome', 'seu@email.com', 'uma senha forte',
  'admin'::kiarys.papel
);
```

Só dá pra rodar isso conectando como o **dono do banco** (não como
`kiarys_app`, que não tem `EXECUTE` liberado fora de sessão — e
`criar_usuaria` exige `eh_admin()`, que exige sessão). Rode via `psql
"$DATABASE_URL_DO_DONO"` com esse SQL direto (bypassa a checagem porque
roda como superuser, não via RPC autenticada) **ou**, mais simples: rode
o `INSERT` manual uma vez:

```sql
insert into kiarys.perfis (nome, email, senha_hash, papel)
values ('Seu Nome', 'seu@email.com', crypt('uma senha forte', gen_salt('bf')), 'admin');
```

A partir daí, faça login normalmente e crie as demais contas pela tela
de admin (que chama `criar_usuaria` via API, já autenticado como admin).

### 6. Backup

`scripts/backup.sh` faz `pg_dump` do schema `kiarys` (inclui
`perfis.senha_hash` — é hash, mas trate o dump como sensível mesmo
assim) pra um `.sql.gz`. `.github/workflows/backup.yml` roda isso toda
segunda e sobe como artifact do Actions (retenção de 90 dias) —
configure o secret `DATABASE_URL` do repositório (a connection string
pública do Postgres, Railway > serviço > Connect). Rodar manual:
`DATABASE_URL=... bash scripts/backup.sh`.

## Domínio

`kiarabijous.com.br` é o domínio antigo da Alyra Joias (ex-Kiara
Bijous), hoje sem uso oficial — está no GoDaddy. A pendência de
redirecioná-lo pro domínio novo da Alyra (`kiara-catalogo`, P46) é outro
assunto, travada por outro motivo, sem relação com este projeto. Usar um
**subdomínio** dele pra Kiarys ERP (ex. `erp.kiarabijous.com.br`) é só
um Custom Domain novo no Railway + um CNAME no GoDaddy.

## Desenvolvimento local

Precisa de um Postgres rodando local (`postgres:16` via Docker, ou
instalado direto) e Node 20+.

```bash
npm install                                    # dependências da raiz (scripts/migrate.js)
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/kiarys \
  npm run db:migrate:seed                       # migrations + db/seed.sql

cd api && npm install && npm run dev            # quando o serviço existir
cd web && npm install && npm run dev
```

`db/seed.sql` cria 3 usuárias de teste (`admin@kiarys.dev`,
`gerente@kiarys.dev`, `vendedora@kiarys.dev`, senha `teste123`), um
catálogo de exemplo (5 produtos × 4 tamanhos × 2 cores) e um caixa aberto.

### Testes

```bash
bash scripts/test-db.sh                            # pgTAP: permissões, ledger, venda, caixa, entrada, fuso
                                                     # (precisa da extensão pgtap instalada no Postgres)
cd tests/concorrencia && npm install && npm test    # 2 conexões reais, última peça
```

## Decisões que ajustam o brief

Registradas aqui porque mudam o comportamento do sistema em relação ao
que o brief original descrevia — para não se perderem numa conversa.

- **Railway em vez de Supabase/Cloudflare Pages.** O brief original
  marcava "FIXO — nada de Railway" por causa de custo. Isso mudou: o
  Railway Pro já é usado e pago pelo resto do GVA, então custo deixou de
  ser argumento — usar o que já se conhece e já se paga. Isso trocou:
  banco (Postgres do Railway em vez de Supabase), autenticação (API
  Node própria com JWT em vez de Supabase Auth) e frontend/domínio
  (Railway em vez de Cloudflare Pages). O **desenho de permissão
  continua o mesmo** (RLS + `SECURITY DEFINER` + role único de baixo
  privilégio) — só quem seta a identidade da sessão mudou de PostgREST
  pra um middleware Express.
- **API Node própria em vez de auto-hospedar o Supabase.** A alternativa
  óbvia seria subir os containers do próprio Supabase (Postgres + Auth +
  PostgREST) no Railway, preservando 100% do desenho original. Preferi
  uma API Express fina: menos serviços Docker pra manter, mesma stack
  que o resto do GVA já opera, e o desenho de segurança em RLS não muda
  — só o mecanismo que valida o JWT e seta `app.uid` por requisição.
- **`perfis` virou também a tabela de identidade** (`email` +
  `senha_hash`), sem uma tabela `auth.users` separada — não tem mais
  sentido separado sem um serviço de Auth dedicado.
- **Caixa único da loja, não um caixa por vendedora.** A gaveta é física
  e compartilhada; um fechamento "às cegas" por pessoa não faria sentido
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
  dinheiro devolvido fisicamente só existe se há uma gaveta aberta pra
  tirar dele.
- **Cadastro de usuária sempre pelo admin**, nunca autocadastro público —
  não existe rota pra isso na API; `criar_usuaria` exige `eh_admin()`.

## Estrutura do repositório

```
db/
  migrations/      0001–0014, nesta ordem (ver cabeçalho de cada arquivo)
  tests/           pgTAP — roda com scripts/test-db.sh
  seed.sql         dado de desenvolvimento
scripts/
  migrate.js       runner de migrations (idempotente, via public.schema_migrations)
  test-db.sh       roda os testes pgTAP contra um Postgres descartável
  backup.sh        pg_dump do schema kiarys
tests/concorrencia/ script Node com 2 conexões reais (não cabe em pgTAP)
api/               API Node/Express — ainda não iniciada
web/               frontend (Vite + React + TS) — ainda não iniciado
.github/workflows/ ci.yml (migrations + pgTAP + concorrência + build web/api),
                   backup.yml (dump semanal)
```

## Ordem das migrations

| # | Arquivo | O que cria |
|---|---|---|
| 0001 | `base.sql` | Schema, extensões, tipos, funções de apoio (`dia_local`, `kiarys.uid()`) |
| 0002 | `perfis_config.sql` | `perfis` (identidade + perfil de negócio), `configuracoes`, `taxas_pagamento`, `perfil_atual`/`eh_admin`/`pode_ver_custo`/`pode_cadastrar`, e as RPCs `autenticar`/`criar_usuaria`/`trocar_senha` |
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
| 0014 | `permissoes.sql` | Role `kiarys_app`, RLS default-deny + `GRANT`/`REVOKE` + policies |

## v2 / v3

Trocas + vale-troca, condicional, crediário, comissão detalhada,
inventário assistido, curva ABC, peças paradas, ruptura de grade — ver
seção 8/11 do brief. Os tipos de enum já existem desde `0001` para não
quebrar dado histórico quando essas tabelas nascerem; as tabelas em si
só entram quando o v2 começar.
