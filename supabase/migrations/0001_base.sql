-- 0001_base.sql
-- Schema `kiarys` (dados) + `public` (a fachada), extensões e funções de apoio.
--
-- Arquitetura de acesso, em duas camadas independentes:
-- 1. `kiarys` PRECISA estar entre os "Exposed schemas" do Supabase
--    (Settings > API — é config de projeto, não SQL, documentada no
--    README) para que o PostgREST encontre as RPCs (`supabase.rpc(...)`
--    resolve o nome de função dentro dos schemas expostos). Se só
--    `public` estivesse exposto, toda chamada a `registrar_venda` etc.
--    devolveria 404 antes mesmo de checar permissão.
-- 2. Expor o schema não é o mesmo que liberá-lo: todo GRANT em toda
--    tabela de `kiarys` para `anon`/`authenticated` é revogado em
--    0014_permissoes.sql, e RLS fica ligado sem nenhuma policy (default
--    deny). Então `/rest/v1/venda_itens` 401/403 mesmo com o schema
--    exposto — só as ~15 RPCs recebem EXECUTE explícito. `public` guarda
--    as views de leitura (mais simples para o frontend do que decorar
--    nome de função para cada consulta).
-- Isso garante o que o brief pede na seção 2 ("Quem faz o quê é garantido
-- no banco, e não só na interface"): mesmo chamando a API direto, sem
-- passar pelas views/RPCs, não há GRANT que libere leitura ou escrita.

create schema if not exists kiarys;

-- Trigram para busca por nome/referência "instantânea mesmo com milhares de
-- variações" (seção 8, Performance) e unaccent para busca sem acento.
create extension if not exists pg_trgm;
create extension if not exists unaccent;
create extension if not exists pgcrypto; -- gen_random_uuid()

set search_path = kiarys, public;

-- ── Tipos ────────────────────────────────────────────────────────────────

create type kiarys.papel as enum ('vendedora', 'gerente', 'admin');

-- Os 10 tipos do brief. CREDIARIO_* e os de condicional/troca já entram
-- aqui (é só um enum) mas as tabelas correspondentes só nascem na v2 —
-- ver nota em 0008_vendas.sql sobre o que a RPC recusa hoje.
create type kiarys.tipo_movimento as enum (
  'ENTRADA',
  'VENDA',
  'ESTORNO_VENDA',
  'TROCA_ENTRADA',
  'TROCA_SAIDA',
  'AJUSTE',
  'PERDA',
  'INVENTARIO',
  'CONDICIONAL_SAIDA',
  'CONDICIONAL_RETORNO'
);

create type kiarys.forma_pagamento as enum (
  'PIX', 'DEBITO', 'CREDITO', 'DINHEIRO', 'CREDIARIO', 'VALE'
);

create type kiarys.status_venda as enum ('PAGA', 'CANCELADA');

create type kiarys.status_caixa as enum ('ABERTO', 'FECHADO');

create type kiarys.tipo_caixa_movimento as enum ('SANGRIA', 'SUPRIMENTO');

-- ── Funções de apoio ─────────────────────────────────────────────────────

-- Fuso fixo do negócio (seção 8: "Fuso horário: America/Fortaleza em todos
-- os relatórios de dia"). Função só para não espalhar a string por todo
-- lugar e poder trocar num único ponto se um dia a loja abrir em outra praça.
create or replace function kiarys.tz()
returns text
language sql
immutable
as $$ select 'America/Fortaleza' $$;

-- Converte um timestamptz para o "dia" local do negócio.
create or replace function kiarys.dia_local(ts timestamptz)
returns date
language sql
stable
as $$ select (ts at time zone kiarys.tz())::date $$;

-- perfil_atual() / eh_admin() / eh_gerente_ou_admin() / pode_ver_custo() /
-- pode_cadastrar() moram em 0002_perfis_config.sql, não aqui: todas
-- retornam ou leem `kiarys.perfis` (e as duas últimas, `kiarys.configuracoes`),
-- e `returns kiarys.perfis` exige o TIPO da tabela já existir no momento
-- do CREATE FUNCTION — ao contrário do corpo de uma função, a assinatura
-- é validada na criação, não só na primeira chamada. Colocar essas 5
-- funções aqui quebra a aplicação das migrations em ordem.

comment on schema kiarys is
  'Schema de dados do Kiarys ERP. Não exposto pela API do Supabase — só '
  'public (views + RPCs) fala com o cliente. Ver README seção "Arquitetura".';
