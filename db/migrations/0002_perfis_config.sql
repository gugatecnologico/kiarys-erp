-- 0002_perfis_config.sql
-- Perfis (papel, comissão, limite de desconto), configurações da loja e
-- taxas de maquininha.

set search_path = kiarys, public;

-- perfis É a identidade agora, não só o "perfil de negócio" que
-- completava um auth.users do Supabase — email/senha moram aqui porque
-- não existe mais um serviço de Auth separado (ver decisão no README:
-- "API Node própria em vez de Supabase Auth").
create table kiarys.perfis (
  id                  uuid primary key default gen_random_uuid(),
  nome                text not null check (btrim(nome) <> ''),
  email               citext not null unique,
  senha_hash          text not null, -- crypt(senha, gen_salt('bf')) — nunca senha em texto puro
  papel               kiarys.papel not null default 'vendedora',
  ativo               boolean not null default true,
  comissao_pct        numeric(5,2) not null default 0 check (comissao_pct >= 0 and comissao_pct <= 100),
  limite_desconto_pct numeric(5,2) check (limite_desconto_pct >= 0 and limite_desconto_pct <= 100),
  -- NULL em limite_desconto_pct = desconto livre. Só faz sentido para admin;
  -- validado em rpc_venda (0011), não aqui.
  criado_em           timestamptz not null default now()
);

comment on column kiarys.perfis.senha_hash is
  'bcrypt via pgcrypto (crypt/gen_salt), calculado dentro da RPC '
  'criar_usuaria — a senha em texto puro nunca é armazenada nem passa '
  'pela API sem já virar hash antes de qualquer SELECT/RETURNING.';
comment on column kiarys.perfis.limite_desconto_pct is
  'NULL = desconto livre (só faz sentido para admin). 0 = sem desconto.';

-- Perfil da pessoa autenticada. Lança exceção se não houver sessão (GUC
-- app.uid não setada — ver kiarys.uid() em 0001), se o perfil não existir
-- ou se estiver inativo — todas as RPCs chamam isso primeiro, então uma
-- conta desativada perde acesso imediatamente, mesmo com um JWT ainda
-- válido (a API teria que consultar o banco a cada requisição pra saber
-- disso sozinha; aqui é de graça, dentro da própria checagem).
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
  if kiarys.uid() is null then
    raise exception 'não autenticado' using errcode = '28000';
  end if;

  select * into v_perfil from kiarys.perfis where id = kiarys.uid();

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

-- ── Autenticação própria (substitui o Supabase Auth) ────────────────────

-- Login. Não chama perfil_atual() — é o próprio ponto de entrada, antes
-- de existir qualquer app.uid setado. A API Node chama isso com email+
-- senha em texto puro (só nessa chamada — nunca mais depois), recebe o
-- perfil de volta se bater, e É A API quem emite o JWT de sessão (a
-- senha nunca sai do Postgres, mas o JWT é responsabilidade de fora,
-- porque assinatura/expiração de token não é problema de banco).
-- SECURITY DEFINER pro cliente conseguir ler senha_hash pra comparar sem
-- ter SELECT direto em perfis (ver 0014) — e pra não vazar por timing se
-- o e-mail existe ou não, o crypt() roda mesmo com hash inexistente.
create or replace function kiarys.autenticar(p_email citext, p_senha text)
returns kiarys.perfis
language plpgsql
security definer
set search_path = kiarys, public
as $$
declare
  v_perfil kiarys.perfis;
begin
  select * into v_perfil from kiarys.perfis where email = p_email;

  if v_perfil.id is null or v_perfil.senha_hash <> crypt(p_senha, v_perfil.senha_hash) then
    -- crypt() com hash NULL/vazio ainda roda (evita timing attack óbvio
    -- de "e-mail não existe responde mais rápido"), mas não teria como
    -- bater com nada — cai aqui igual.
    perform crypt(p_senha, coalesce(v_perfil.senha_hash, gen_salt('bf')));
    raise exception 'e-mail ou senha inválidos' using errcode = '28P01';
  end if;

  if not v_perfil.ativo then
    raise exception 'usuário desativado' using errcode = '28000';
  end if;

  return v_perfil;
end;
$$;

comment on function kiarys.autenticar is
  'Chamada só pela rota de login da API — nunca pelo frontend direto. '
  'Devolve o perfil; quem emite e assina o JWT de sessão é a API (Node), '
  'não o banco.';

-- Criação de usuária: sempre pelo admin (nunca autocadastro — não existe
-- rota pública pra isso na API). ativo já nasce true porque não há mais
-- um passo de "confirmar conta" separado; o admin já está deliberando ao
-- chamar isso.
create or replace function kiarys.criar_usuaria(
  p_nome text,
  p_email citext,
  p_senha text,
  p_papel kiarys.papel default 'vendedora',
  p_comissao_pct numeric default 0,
  p_limite_desconto_pct numeric default null
)
returns kiarys.perfis
language plpgsql
security definer
set search_path = kiarys, public
as $$
declare
  v_perfil kiarys.perfis;
begin
  if not kiarys.eh_admin() then
    raise exception 'só admin cria usuária' using errcode = '42501';
  end if;
  if length(p_senha) < 8 then
    raise exception 'senha precisa de pelo menos 8 caracteres' using errcode = '22023';
  end if;

  insert into kiarys.perfis (nome, email, senha_hash, papel, comissao_pct, limite_desconto_pct)
  values (p_nome, p_email, crypt(p_senha, gen_salt('bf')), p_papel, p_comissao_pct, p_limite_desconto_pct)
  returning * into v_perfil;

  return v_perfil;
end;
$$;

-- Troca de senha pela própria pessoa (não precisa ser admin — qualquer
-- perfil ativo troca a própria senha; trocar a de outra pessoa é o admin
-- recriando via painel, não há RPC de "resetar senha de terceiro" no MVP).
create or replace function kiarys.trocar_senha(p_senha_atual text, p_senha_nova text)
returns void
language plpgsql
security definer
set search_path = kiarys, public
as $$
declare
  v_perfil kiarys.perfis := kiarys.perfil_atual();
begin
  if v_perfil.senha_hash <> crypt(p_senha_atual, v_perfil.senha_hash) then
    raise exception 'senha atual incorreta' using errcode = '28P01';
  end if;
  if length(p_senha_nova) < 8 then
    raise exception 'senha precisa de pelo menos 8 caracteres' using errcode = '22023';
  end if;

  update kiarys.perfis set senha_hash = crypt(p_senha_nova, gen_salt('bf')) where id = v_perfil.id;
end;
$$;
