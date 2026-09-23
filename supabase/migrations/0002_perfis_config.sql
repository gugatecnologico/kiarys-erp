-- 0002_perfis_config.sql
-- Perfis (papel, comissão, limite de desconto), configurações da loja e
-- taxas de maquininha.

set search_path = kiarys, public;

create table kiarys.perfis (
  id                  uuid primary key references auth.users(id) on delete cascade,
  nome                text not null check (btrim(nome) <> ''),
  papel               kiarys.papel not null default 'vendedora',
  ativo               boolean not null default false, -- nasce inativo, admin ativa (ver trigger abaixo)
  comissao_pct        numeric(5,2) not null default 0 check (comissao_pct >= 0 and comissao_pct <= 100),
  limite_desconto_pct numeric(5,2) check (limite_desconto_pct >= 0 and limite_desconto_pct <= 100),
  -- NULL em limite_desconto_pct = desconto livre. Só faz sentido para admin;
  -- validado em rpc_venda (0011), não aqui.
  criado_em           timestamptz not null default now()
);

comment on column kiarys.perfis.ativo is
  'Nasce false. O trigger em auth.users cria o registro desativado; o '
  'admin ativa e define o papel pelo painel. Evita que qualquer conta '
  'criada no Supabase Auth vire vendedora com acesso automático.';
comment on column kiarys.perfis.limite_desconto_pct is
  'NULL = desconto livre (só faz sentido para admin). 0 = sem desconto.';

-- Cria o perfil (inativo) assim que uma conta nasce em auth.users.
-- SECURITY DEFINER porque o cliente não tem permissão de escrever em
-- kiarys.perfis diretamente (ver 0014_permissoes.sql).
create or replace function kiarys.criar_perfil_ao_registrar()
returns trigger
language plpgsql
security definer
set search_path = kiarys, public
as $$
begin
  insert into kiarys.perfis (id, nome, ativo)
  values (new.id, coalesce(new.raw_user_meta_data->>'nome', split_part(new.email, '@', 1)), false)
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function kiarys.criar_perfil_ao_registrar();

-- Perfil da pessoa autenticada. Lança exceção se não houver sessão, se o
-- perfil não existir ou se estiver inativo — todas as RPCs chamam isso
-- primeiro, então uma conta desativada perde acesso imediatamente, mesmo
-- com um JWT ainda válido. (Fica aqui, não em 0001, porque `returns
-- kiarys.perfis` exige a tabela já existir — ver nota em 0001_base.sql.)
create or replace function kiarys.perfil_atual()
returns kiarys.perfis
language plpgsql
stable
security definer
set search_path = kiarys, public
as $$
declare
  v_perfil kiarys.perfis;
begin
  if auth.uid() is null then
    raise exception 'não autenticado' using errcode = '28000';
  end if;

  select * into v_perfil from kiarys.perfis where id = auth.uid();

  if v_perfil.id is null then
    raise exception 'perfil não encontrado' using errcode = '28000';
  end if;

  if not v_perfil.ativo then
    raise exception 'usuário desativado' using errcode = '28000';
  end if;

  return v_perfil;
end;
$$;

create or replace function kiarys.eh_admin()
returns boolean
language sql
stable
security definer
set search_path = kiarys, public
as $$ select (kiarys.perfil_atual()).papel = 'admin' $$;

create or replace function kiarys.eh_gerente_ou_admin()
returns boolean
language sql
stable
security definer
set search_path = kiarys, public
as $$ select (kiarys.perfil_atual()).papel in ('gerente', 'admin') $$;

-- Configurações: linha única (id fixo) — mais simples de referenciar e de
-- travar com RLS do que uma tabela chave/valor.
create table kiarys.configuracoes (
  id                  boolean primary key default true check (id), -- garante 1 linha só
  nome_loja           text not null default 'Kiarys Moda Feminina',
  politica_troca      text not null default '',
  gerente_ve_custo    boolean not null default false,
  gerente_cadastra    boolean not null default false,
  limite_desconto_gerente_pct numeric(5,2) check (limite_desconto_gerente_pct >= 0 and limite_desconto_gerente_pct <= 100),
  atualizado_em       timestamptz not null default now()
);

comment on table kiarys.configuracoes is
  'Linha única (id=true). gerente_ve_custo e gerente_cadastra são os '
  '"opcional" da tabela de permissões do brief (seção 5).';

insert into kiarys.configuracoes (id) values (true);

-- Ponto único de decisão "quem vê custo/margem" e "quem cadastra". Leem
-- configuracoes.gerente_ve_custo/gerente_cadastra — os "opcional" da
-- tabela de permissões do brief (seção 5) — por isso ficam depois dela.
create or replace function kiarys.pode_ver_custo()
returns boolean
language plpgsql
stable
security definer
set search_path = kiarys, public
as $$
declare
  v_papel kiarys.papel := (kiarys.perfil_atual()).papel;
  v_gerente_ve boolean;
begin
  if v_papel = 'admin' then
    return true;
  end if;
  if v_papel = 'gerente' then
    select gerente_ve_custo into v_gerente_ve from kiarys.configuracoes limit 1;
    return coalesce(v_gerente_ve, false);
  end if;
  return false;
end;
$$;

create or replace function kiarys.pode_cadastrar()
returns boolean
language plpgsql
stable
security definer
set search_path = kiarys, public
as $$
declare
  v_papel kiarys.papel := (kiarys.perfil_atual()).papel;
  v_gerente_pode boolean;
begin
  if v_papel = 'admin' then
    return true;
  end if;
  if v_papel = 'gerente' then
    select gerente_cadastra into v_gerente_pode from kiarys.configuracoes limit 1;
    return coalesce(v_gerente_pode, false);
  end if;
  return false;
end;
$$;

-- Taxa de maquininha por forma × parcelas, para a margem real (fórmula da
-- seção 7: "Margem de contribuição"). Congelada em pagamentos.taxa_pct
-- (0008) no momento da venda.
create table kiarys.taxas_pagamento (
  forma       kiarys.forma_pagamento not null,
  parcelas    smallint not null default 1 check (parcelas >= 1),
  taxa_pct    numeric(5,2) not null default 0 check (taxa_pct >= 0),
  primary key (forma, parcelas)
);

insert into kiarys.taxas_pagamento (forma, parcelas, taxa_pct) values
  ('PIX', 1, 0),
  ('DINHEIRO', 1, 0),
  ('DEBITO', 1, 0),
  ('CREDITO', 1, 0);
-- as demais parcelas de CREDITO ficam para o admin cadastrar em
-- Configurações (seção 6, item 9) — não chutamos taxa de maquininha.

create or replace function kiarys.set_atualizado_em()
returns trigger language plpgsql as $$
begin
  new.atualizado_em = now();
  return new;
end;
$$;

create trigger trg_configuracoes_atualizado_em
  before update on kiarys.configuracoes
  for each row execute function kiarys.set_atualizado_em();
