-- 0005_entradas.sql
-- Entrada de mercadoria: cabeçalho (nota, frete, despesas) + itens, para
-- ratear o custo real por peça (seção 2, princípio 6, e seção 7).

set search_path = kiarys, public;

create table kiarys.entradas (
  id                uuid primary key default gen_random_uuid(),
  fornecedor_id     uuid references kiarys.fornecedores(id),
  data              date not null default kiarys.dia_local(now()),
  doc_ref           text,
  frete             numeric(12,2) not null default 0 check (frete >= 0),
  outras_despesas   numeric(12,2) not null default 0 check (outras_despesas >= 0),
  total_itens       numeric(12,2) not null default 0 check (total_itens >= 0),
  usuario_id        uuid not null references kiarys.perfis(id),
  criado_em         timestamptz not null default now()
);

create table kiarys.entrada_itens (
  id                    bigint generated always as identity primary key,
  entrada_id            uuid not null references kiarys.entradas(id) on delete cascade,
  variacao_id           uuid not null references kiarys.variacoes(id),
  quantidade            integer not null check (quantidade > 0),
  custo_unitario_nf     numeric(12,2) not null check (custo_unitario_nf >= 0),
  custo_unitario_real   numeric(12,2) not null check (custo_unitario_real >= 0)
    -- nf + rateio de frete/despesas proporcional ao valor do item, calculado
    -- dentro de rpc registrar_entrada (0012) — nunca escrito pelo cliente.
);

create index idx_entrada_itens_entrada on kiarys.entrada_itens (entrada_id);
create index idx_entrada_itens_variacao on kiarys.entrada_itens (variacao_id);

comment on table kiarys.entradas is
  'Cabeçalho de nota de entrada. total_itens e os custo_unitario_real dos '
  'itens são calculados pela RPC registrar_entrada, nunca digitados soltos '
  '— é o que garante que frete/despesas sempre entram no custo médio.';
