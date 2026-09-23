-- 0007_caixa.sql
-- Caixa ÚNICO da loja (decisão do dono: a gaveta é física e compartilhada
-- — ver README "Decisões que ajustam o brief"). Não é "um caixa por
-- vendedora": é um caixa por vez, aberto por alguém, com cada venda e
-- cada sangria/suprimento registrando quem mexeu na gaveta.

set search_path = kiarys, public;

create table kiarys.caixas (
  id                  uuid primary key default gen_random_uuid(),
  usuario_abertura    uuid not null references kiarys.perfis(id),
  aberto_em           timestamptz not null default now(),
  valor_inicial       numeric(12,2) not null check (valor_inicial >= 0),
  usuario_fechamento  uuid references kiarys.perfis(id),
  fechado_em          timestamptz,
  valor_contado       numeric(12,2) check (valor_contado >= 0),
  valor_esperado      numeric(12,2),
  diferenca           numeric(12,2),
  status              kiarys.status_caixa not null default 'ABERTO',
  check (status = 'ABERTO' or (fechado_em is not null and valor_contado is not null))
);

-- Um único caixa ABERTO por vez na loja inteira — é a regra "caixa único",
-- não "um por pessoa". Índice único parcial faz o próprio banco recusar
-- abrir um segundo caixa (e a RPC abrir_caixa dá a mensagem amigável antes
-- disso, mas o índice é quem garante de verdade).
create unique index idx_caixa_unico_aberto
  on kiarys.caixas ((true))
  where status = 'ABERTO';

create index idx_caixas_status on kiarys.caixas (status);
create index idx_caixas_aberto_em on kiarys.caixas (aberto_em desc);

create table kiarys.caixa_movimentos (
  id          bigint generated always as identity primary key,
  caixa_id    uuid not null references kiarys.caixas(id),
  tipo        kiarys.tipo_caixa_movimento not null,
  valor       numeric(12,2) not null check (valor > 0),
  motivo      text not null check (btrim(motivo) <> ''),
  usuario_id  uuid not null references kiarys.perfis(id),
  criado_em   timestamptz not null default now()
);

create index idx_caixa_movimentos_caixa on kiarys.caixa_movimentos (caixa_id);

comment on table kiarys.caixas is
  'Caixa único da loja (gaveta física compartilhada) — não um caixa por '
  'vendedora. usuario_abertura/usuario_fechamento registram quem abriu e '
  'quem fechou; vendas.vendedora_id (0008) registra quem vendeu cada peça.';
