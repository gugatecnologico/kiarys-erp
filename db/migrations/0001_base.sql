-- 0001_base.sql
-- Schema `kiarys` (dados) + `public` (a fachada), extensões e funções de apoio.
--
-- Arquitetura de acesso (Postgres do Railway, sem Supabase): o navegador
-- nunca fala com o Postgres direto — só a API Node do repositório
-- (`api/`, serviço próprio no Railway) tem a connection string. Isso
-- move a fronteira de confiança pra dentro da API. Mesmo assim, a regra
-- do brief (seção 2: "Quem faz o quê é garantido no banco, e não só na
-- interface") continua valendo por dois motivos:
-- 1. A API sempre se conecta com UM ÚNICO role de banco (`kiarys_app`,
--    criado em 0014_permissoes.sql) — não existe um role "admin" e outro
--    "vendedora" no Postgres. Quem diferencia é RLS lendo `kiarys.uid()`,
--    que a API seta por requisição (`select set_config('app.uid', ...)`)
--    depois de validar o JWT — exatamente o mesmo mecanismo que o
--    Supabase faria com `auth.uid()`, só que a verificação do JWT agora
--    é código Node (`api/lib/auth.js`), não um serviço GoTrue separado.
-- 2. Isso é defesa em profundidade, não só estética: um bug de rota na
--    API (esqueceu de filtrar `WHERE vendedora_id = ...`) ainda esbarra
--    em RLS. Um SQL solto por engano em alguma rota ainda esbarra nos
--    GRANT revogados de `kiarys_app` nas tabelas sensíveis (0014).
create schema if not exists kiarys;

-- Trigram para busca por nome/referência "instantânea mesmo com milhares de
-- variações" (seção 8, Performance) e unaccent para busca sem acento.
create extension if not exists pg_trgm;
create extension if not exists unaccent;
create extension if not exists pgcrypto; -- gen_random_uuid() + crypt()/gen_salt() do hash de senha
create extension if not exists citext;   -- email case-insensitive (perfis.email, 0002)

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

-- Identidade da requisição atual. Substitui o `auth.uid()` do Supabase:
-- a API Node seta `app.uid` como GUC LOCAL da transação
-- (`select set_config('app.uid', p_perfil_id::text, true)`) logo depois
-- de validar o JWT e antes de rodar qualquer RPC/consulta — mesma técnica
-- de sempre (era assim que os testes de concorrência já simulavam sessão),
-- só que agora é a API quem seta, não mais o PostgREST a partir do JWT
-- do navegador.
create or replace function kiarys.uid()
returns uuid
language sql
stable
as $$ select nullif(current_setting('app.uid', true), '')::uuid $$;

-- perfil_atual() / eh_admin() / eh_gerente_ou_admin() / pode_ver_custo() /
-- pode_cadastrar() moram em 0002_perfis_config.sql, não aqui: todas
-- retornam ou leem `kiarys.perfis` (e as duas últimas, `kiarys.configuracoes`),
-- e `returns kiarys.perfis` exige o TIPO da tabela já existir no momento
-- do CREATE FUNCTION — ao contrário do corpo de uma função, a assinatura
-- é validada na criação, não só na primeira chamada. Colocar essas 5
-- funções aqui quebra a aplicação das migrations em ordem.

comment on schema kiarys is
  'Schema de dados do Kiarys ERP, no Postgres do Railway. Só a API Node '
  'do repositório fala com ele — ver README seção "Arquitetura".';
