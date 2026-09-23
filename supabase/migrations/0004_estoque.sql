-- 0004_estoque.sql
-- O livro de lançamentos (princípio 1 do brief): movimentos_estoque é
-- insert-only, e estoque_saldos é um cache mantido por trigger a partir
-- dele — nunca escrito diretamente por uma tela.

set search_path = kiarys, public;

create table kiarys.movimentos_estoque (
  id              bigint generated always as identity primary key,
  variacao_id     uuid not null references kiarys.variacoes(id),
  tipo            kiarys.tipo_movimento not null,
  quantidade      integer not null check (quantidade <> 0), -- ± conforme o tipo
  custo_unitario  numeric(12,2) not null default 0 check (custo_unitario >= 0),
  ref_tipo        text,     -- 'venda' | 'entrada' | 'caixa' | ... (livre, só rastreio)
  ref_id          uuid,     -- id da venda/entrada/etc. que originou o movimento
  motivo          text,
  usuario_id      uuid not null references kiarys.perfis(id),
  criado_em       timestamptz not null default now()
);

create index idx_movimentos_variacao on kiarys.movimentos_estoque (variacao_id, criado_em desc);
create index idx_movimentos_ref on kiarys.movimentos_estoque (ref_tipo, ref_id);
create index idx_movimentos_tipo_dia on kiarys.movimentos_estoque (tipo, criado_em);

comment on table kiarys.movimentos_estoque is
  'Ledger de estoque. INSERT-only — ver trigger trg_movimentos_imutavel. '
  'O saldo nunca é digitado, só decorre da soma destes lançamentos.';

-- Nada se apaga (princípio 4): nenhuma UPDATE ou DELETE em movimentos,
-- nem por admin. Correção de erro é lançamento novo com motivo.
create or replace function kiarys.bloquear_alteracao_movimento()
returns trigger
language plpgsql
as $$
begin
  raise exception 'movimentos_estoque é insert-only — lance um movimento de correção, nunca altere ou apague um existente'
    using errcode = '0A000';
end;
$$;

create trigger trg_movimentos_imutavel
  before update or delete on kiarys.movimentos_estoque
  for each row execute function kiarys.bloquear_alteracao_movimento();

-- Cache de saldo. CHECK (qtd >= 0) é a última barreira contra vender
-- abaixo de zero mesmo se algum caminho futuro esquecer o FOR UPDATE
-- (ver rpc_venda, 0011) — o brief pede isso explicitamente no critério
-- de aceite de concorrência (seção 10).
create table kiarys.estoque_saldos (
  variacao_id uuid primary key references kiarys.variacoes(id),
  qtd         integer not null default 0 check (qtd >= 0),
  atualizado_em timestamptz not null default now()
);

-- UPDATE-depois-INSERT, e não INSERT ... ON CONFLICT DO UPDATE: o Postgres
-- valida CHECK contra a linha PROPOSTA do INSERT antes de sequer olhar
-- pro conflito — então um INSERT (variacao_id, -1, ...) falharia o
-- CHECK(qtd >= 0) mesmo quando o saldo final (existente 8, menos 1 = 7)
-- seria válido, porque o conflito nunca chega a ser resolvido. Com UPDATE
-- primeiro, o CHECK avalia o valor final (qtd_atual + delta), que é o que
-- realmente importa; o INSERT só roda no primeiro movimento da variação
-- (quando ainda não há linha), e aí validar o delta bruto está correto —
-- o primeiro movimento de uma variação tem que ser não-negativo mesmo
-- (uma venda sem nenhum movimento anterior já é barrada antes disso, na
-- checagem de saldo dentro de registrar_venda).
create or replace function kiarys.aplicar_movimento_no_saldo()
returns trigger
language plpgsql
security definer
set search_path = kiarys, public
as $$
begin
  update kiarys.estoque_saldos
  set qtd = qtd + new.quantidade, atualizado_em = now()
  where variacao_id = new.variacao_id;

  if not found then
    insert into kiarys.estoque_saldos (variacao_id, qtd, atualizado_em)
    values (new.variacao_id, new.quantidade, now());
  end if;

  return new;
end;
$$;

create trigger trg_movimento_atualiza_saldo
  after insert on kiarys.movimentos_estoque
  for each row execute function kiarys.aplicar_movimento_no_saldo();

comment on table kiarys.estoque_saldos is
  'Cache do saldo por variação, mantido só pelo trigger acima. O CHECK '
  '(qtd >= 0) é a segunda trava contra vender abaixo de zero — a primeira '
  'é o SELECT ... FOR UPDATE dentro de registrar_venda.';
