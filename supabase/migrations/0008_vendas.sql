-- 0008_vendas.sql
-- vendas / venda_itens / pagamentos. Custo e taxa de maquininha congelados
-- no momento da venda (princípio 5 do brief) — a margem histórica não se
-- move quando o custo ou a taxa mudam depois.

set search_path = kiarys, public;

create sequence kiarys.venda_numero_seq start 1;

create table kiarys.vendas (
  id                  uuid primary key default gen_random_uuid(),
  numero              bigint not null unique default nextval('kiarys.venda_numero_seq'),
  caixa_id            uuid not null references kiarys.caixas(id),
  vendedora_id        uuid not null references kiarys.perfis(id),
  cliente_id          uuid references kiarys.clientes(id),
  subtotal            numeric(12,2) not null check (subtotal >= 0),
  desconto            numeric(12,2) not null default 0 check (desconto >= 0),
  total               numeric(12,2) not null check (total >= 0),
  status              kiarys.status_venda not null default 'PAGA',
  motivo_cancelamento text,
  cancelada_por       uuid references kiarys.perfis(id),
  cancelada_em        timestamptz,
  nota_ref            text, -- opcional: referência da nota emitida fora deste sistema (brief, seção 1)
  chave_idempotencia  uuid not null unique,
    -- gerada no celular a cada tentativa de "confirmar"; evita venda
    -- duplicada em duplo toque ou reenvio após queda de internet.
  criado_em           timestamptz not null default now(),
  check (total = subtotal - desconto),
  check (status = 'PAGA' or (motivo_cancelamento is not null and cancelada_por is not null and cancelada_em is not null))
);

create index idx_vendas_caixa on kiarys.vendas (caixa_id);
create index idx_vendas_vendedora_dia on kiarys.vendas (vendedora_id, criado_em desc);
create index idx_vendas_cliente on kiarys.vendas (cliente_id) where cliente_id is not null;
create index idx_vendas_status_dia on kiarys.vendas (status, criado_em);

create table kiarys.venda_itens (
  id                bigint generated always as identity primary key,
  venda_id          uuid not null references kiarys.vendas(id) on delete cascade,
  variacao_id       uuid not null references kiarys.variacoes(id),
  quantidade        integer not null check (quantidade > 0),
  preco_unitario    numeric(12,2) not null check (preco_unitario >= 0), -- kiarys.preco_efetivo() no momento da venda
  desconto_item     numeric(12,2) not null default 0 check (desconto_item >= 0),
  custo_unitario    numeric(12,2) not null check (custo_unitario >= 0) -- congelado de variacoes.custo_medio
);

create index idx_venda_itens_venda on kiarys.venda_itens (venda_id);
create index idx_venda_itens_variacao on kiarys.venda_itens (variacao_id);

create table kiarys.pagamentos (
  id          bigint generated always as identity primary key,
  venda_id    uuid not null references kiarys.vendas(id) on delete cascade,
  forma       kiarys.forma_pagamento not null,
  valor       numeric(12,2) not null check (valor > 0),
  parcelas    smallint not null default 1 check (parcelas >= 1),
  taxa_pct    numeric(5,2) not null default 0 check (taxa_pct >= 0) -- congelada de taxas_pagamento
);

create index idx_pagamentos_venda on kiarys.pagamentos (venda_id);
create index idx_pagamentos_forma_dia on kiarys.pagamentos (forma);

comment on column kiarys.vendas.chave_idempotencia is
  'Gerada no cliente (uuid v4) a cada tentativa de confirmar a venda. '
  'registrar_venda faz upsert por ela: reenviar a mesma chave devolve a '
  'venda já criada em vez de duplicar.';

comment on table kiarys.venda_itens is
  'custo_unitario é o custo congelado no momento da venda — nunca revisitar '
  'variacoes.custo_medio para recalcular margem de vendas antigas.';

-- v2 (seção 8 e 11): CREDIARIO e VALE já existem no enum forma_pagamento
-- desde 0001, mas registrar_venda (0011) recusa as duas até as tabelas
-- crediario_parcelas e vales_troca existirem — evita superfície sem regra.
