-- 0009_auditoria.sql
-- Tabela de auditoria + trigger genérico para tabelas sensíveis a preço,
-- custo e perfis (princípio 8 do brief).

set search_path = kiarys, public;

create table kiarys.auditoria (
  id          bigint generated always as identity primary key,
  usuario_id  uuid references kiarys.perfis(id), -- null só é possível em ação de sistema (trigger de auth)
  acao        text not null check (btrim(acao) <> ''),
  entidade    text not null check (btrim(entidade) <> ''),
  entidade_id text not null,
  antes       jsonb,
  depois      jsonb,
  criado_em   timestamptz not null default now()
);

create index idx_auditoria_entidade on kiarys.auditoria (entidade, entidade_id);
create index idx_auditoria_usuario_dia on kiarys.auditoria (usuario_id, criado_em desc);

comment on table kiarys.auditoria is
  'Trilha de ações sensíveis. Alimentada pelo trigger genérico abaixo '
  '(preço, custo, perfis) e por INSERTs diretos nas RPCs críticas '
  '(cancelar_venda, ajustar_estoque etc).';

-- Tenta descobrir o usuário atual sem lançar exceção quando não há sessão
-- (o trigger de auth.users, por exemplo, roda sem JWT).
create or replace function kiarys.usuario_atual_ou_null()
returns uuid
language plpgsql
stable
security definer
set search_path = kiarys, public
as $$
begin
  return auth.uid();
exception when others then
  return null;
end;
$$;

create or replace function kiarys.registrar_auditoria_generica()
returns trigger
language plpgsql
security definer
set search_path = kiarys, public
as $$
declare
  v_entidade_id text;
begin
  v_entidade_id := coalesce((new).id::text, (old).id::text);

  insert into kiarys.auditoria (usuario_id, acao, entidade, entidade_id, antes, depois)
  values (
    kiarys.usuario_atual_ou_null(),
    tg_op,
    tg_table_name,
    v_entidade_id,
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('UPDATE', 'INSERT') then to_jsonb(new) else null end
  );

  return coalesce(new, old);
end;
$$;

-- Preço/promoção e custo médio: alterados por admin fora do fluxo de
-- entrada/venda (ex. reajuste manual). Vale para toda a linha da variação,
-- não só preço — mais simples e ainda cobre o que a seção 8 pede.
create trigger trg_auditoria_variacoes
  after update on kiarys.variacoes
  for each row
  when (old.preco_venda is distinct from new.preco_venda
        or old.preco_promocional is distinct from new.preco_promocional
        or old.custo_medio is distinct from new.custo_medio)
  execute function kiarys.registrar_auditoria_generica();

-- Perfis: papel, ativo, comissão e limite de desconto são as mudanças que
-- importam auditar (não precisa em toda edição de nome).
create trigger trg_auditoria_perfis
  after update on kiarys.perfis
  for each row
  when (old.papel is distinct from new.papel
        or old.ativo is distinct from new.ativo
        or old.comissao_pct is distinct from new.comissao_pct
        or old.limite_desconto_pct is distinct from new.limite_desconto_pct)
  execute function kiarys.registrar_auditoria_generica();
