-- 0003_catalogo.sql
-- Categorias, coleções, fornecedores, produtos e variações (grade
-- tamanho × cor). Estoque, código de barras e preço vivem na variação
-- (brief, seção 2, princípio 2).

set search_path = kiarys, public;

create table kiarys.categorias (
  id    uuid primary key default gen_random_uuid(),
  nome  text not null unique check (btrim(nome) <> '')
);

create table kiarys.colecoes (
  id        uuid primary key default gen_random_uuid(),
  nome      text not null check (btrim(nome) <> ''),
  estacao   text,
  ano       smallint,
  unique (nome, ano)
);

create table kiarys.fornecedores (
  id        uuid primary key default gen_random_uuid(),
  nome      text not null check (btrim(nome) <> ''),
  whatsapp  text,
  obs       text
);

create table kiarys.produtos (
  id            uuid primary key default gen_random_uuid(),
  referencia    text not null unique check (btrim(referencia) <> ''),
  nome          text not null check (btrim(nome) <> ''),
  categoria_id  uuid references kiarys.categorias(id),
  colecao_id    uuid references kiarys.colecoes(id),
  fornecedor_id uuid references kiarys.fornecedores(id),
  foto_url      text,
  ativo         boolean not null default true,
  criado_em     timestamptz not null default now()
);

-- Busca "instantânea mesmo com milhares de variações" (seção 8).
create index idx_produtos_nome_trgm on kiarys.produtos using gin (nome gin_trgm_ops);
create index idx_produtos_referencia_trgm on kiarys.produtos using gin (referencia gin_trgm_ops);
create index idx_produtos_categoria on kiarys.produtos (categoria_id);

-- Sequência para código de barras interno (EAN-13 "2" + 11 dígitos + DV é
-- overkill para o MVP; geramos um Code128 numérico próprio quando a peça
-- não vem com código de fábrica). Prefixo 200 evita colidir com EAN
-- comerciais reais, seguindo a convenção de faixa interna 20-29 do GS1.
create sequence kiarys.codigo_barras_seq start 1;

create or replace function kiarys.gerar_codigo_barras()
returns text
language sql
as $$
  select '200' || lpad(nextval('kiarys.codigo_barras_seq')::text, 9, '0')
$$;

create table kiarys.variacoes (
  id                uuid primary key default gen_random_uuid(),
  produto_id        uuid not null references kiarys.produtos(id) on delete cascade,
  tamanho           text not null check (btrim(tamanho) <> ''),
  cor               text not null check (btrim(cor) <> ''),
  codigo_barras     text not null unique,
  preco_venda       numeric(12,2) not null check (preco_venda >= 0),
  preco_promocional numeric(12,2) check (preco_promocional is null or preco_promocional >= 0),
  promo_ate         date,
  custo_medio       numeric(12,2) not null default 0 check (custo_medio >= 0),
  estoque_minimo    integer not null default 0 check (estoque_minimo >= 0),
  ativo             boolean not null default true,
  criado_em         timestamptz not null default now(),
  unique (produto_id, tamanho, cor),
  check (preco_promocional is null or promo_ate is not null)
    -- promoção sem data final não existe (seção 8: "preço promocional com
    -- data final, e não uma sobrescrita").
);

alter table kiarys.variacoes
  alter column codigo_barras set default kiarys.gerar_codigo_barras();

create index idx_variacoes_produto on kiarys.variacoes (produto_id);
create index idx_variacoes_codigo_barras on kiarys.variacoes (codigo_barras);
create index idx_variacoes_ativo on kiarys.variacoes (ativo) where ativo;

-- Preço efetivo no dia local do negócio: promocional só vale enquanto
-- promo_ate >= hoje (America/Fortaleza). É a função que as RPCs de venda
-- usam para não confiar em preço mandado pelo cliente.
create or replace function kiarys.preco_efetivo(p_variacao_id uuid, p_dia date default kiarys.dia_local(now()))
returns numeric(12,2)
language sql
stable
security definer
set search_path = kiarys, public
as $$
  select case
    when v.preco_promocional is not null and v.promo_ate >= p_dia
      then v.preco_promocional
    else v.preco_venda
  end
  from kiarys.variacoes v
  where v.id = p_variacao_id
$$;

comment on function kiarys.preco_efetivo is
  'Preço que vale hoje para a variação, já considerando promoção com data. '
  'Usada dentro de registrar_venda — nunca confiar em preço vindo do cliente.';
