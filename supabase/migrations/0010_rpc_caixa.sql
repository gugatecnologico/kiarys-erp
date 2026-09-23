-- 0010_rpc_caixa.sql
-- abrir_caixa / movimentar_caixa / fechar_caixa. Caixa único da loja
-- (decisão do dono, ver 0007) — qualquer papel pode abrir, sangrar,
-- suprir e fechar (tabela de permissões da seção 5: "Abrir/fechar o
-- próprio caixa, sangria" ✅ para os três papéis).

set search_path = kiarys, public;

create or replace function kiarys.caixa_aberto_atual()
returns kiarys.caixas
language sql
stable
security definer
set search_path = kiarys, public
as $$
  select * from kiarys.caixas where status = 'ABERTO' limit 1
$$;

create or replace function kiarys.abrir_caixa(p_valor_inicial numeric)
returns kiarys.caixas
language plpgsql
security definer
set search_path = kiarys, public
as $$
declare
  v_perfil kiarys.perfis := kiarys.perfil_atual();
  v_caixa kiarys.caixas;
begin
  if p_valor_inicial < 0 then
    raise exception 'valor inicial não pode ser negativo' using errcode = '22023';
  end if;

  if exists (select 1 from kiarys.caixas where status = 'ABERTO') then
    raise exception 'já existe um caixa aberto — feche-o antes de abrir outro' using errcode = '23505';
  end if;

  insert into kiarys.caixas (usuario_abertura, valor_inicial)
  values (v_perfil.id, p_valor_inicial)
  returning * into v_caixa;

  return v_caixa;
end;
$$;

create or replace function kiarys.movimentar_caixa(p_tipo kiarys.tipo_caixa_movimento, p_valor numeric, p_motivo text)
returns kiarys.caixa_movimentos
language plpgsql
security definer
set search_path = kiarys, public
as $$
declare
  v_perfil kiarys.perfis := kiarys.perfil_atual();
  v_caixa kiarys.caixas;
  v_mov kiarys.caixa_movimentos;
begin
  if p_valor <= 0 then
    raise exception 'valor precisa ser positivo' using errcode = '22023';
  end if;
  if btrim(coalesce(p_motivo, '')) = '' then
    raise exception 'motivo é obrigatório' using errcode = '22023';
  end if;

  select * into v_caixa from kiarys.caixas where status = 'ABERTO' for update;
  if v_caixa.id is null then
    raise exception 'não há caixa aberto' using errcode = '55000';
  end if;

  insert into kiarys.caixa_movimentos (caixa_id, tipo, valor, motivo, usuario_id)
  values (v_caixa.id, p_tipo, p_valor, p_motivo, v_perfil.id)
  returning * into v_mov;

  return v_mov;
end;
$$;

-- Soma o dinheiro esperado na gaveta a partir dos lançamentos — nunca lido
-- pela vendedora antes de informar o valor contado (fechamento às cegas,
-- seção 4 e critério de aceite da seção 10).
create or replace function kiarys.calcular_esperado_caixa(p_caixa_id uuid)
returns numeric
language sql
stable
security definer
set search_path = kiarys, public
as $$
  select
    c.valor_inicial
    + coalesce((
        select sum(p.valor)
        from kiarys.pagamentos p
        join kiarys.vendas v on v.id = p.venda_id
        where v.caixa_id = c.id and v.status = 'PAGA' and p.forma = 'DINHEIRO'
      ), 0)
    + coalesce((
        select sum(cm.valor) from kiarys.caixa_movimentos cm
        where cm.caixa_id = c.id and cm.tipo = 'SUPRIMENTO'
      ), 0)
    - coalesce((
        select sum(cm.valor) from kiarys.caixa_movimentos cm
        where cm.caixa_id = c.id and cm.tipo = 'SANGRIA'
      ), 0)
  from kiarys.caixas c
  where c.id = p_caixa_id
$$;

comment on function kiarys.calcular_esperado_caixa is
  'Sangrias já incluem os estornos em dinheiro lançados por cancelar_venda '
  '(0011) — não somamos venda_itens cancelados aqui de novo, senão contaria '
  'em dobro. Ver decisão "estorno em dinheiro" no README.';

create or replace function kiarys.fechar_caixa(p_valor_contado numeric)
returns kiarys.caixas
language plpgsql
security definer
set search_path = kiarys, public
as $$
declare
  v_perfil kiarys.perfis := kiarys.perfil_atual();
  v_caixa kiarys.caixas;
  v_esperado numeric(12,2);
begin
  if p_valor_contado < 0 then
    raise exception 'valor contado não pode ser negativo' using errcode = '22023';
  end if;

  select * into v_caixa from kiarys.caixas where status = 'ABERTO' for update;
  if v_caixa.id is null then
    raise exception 'não há caixa aberto' using errcode = '55000';
  end if;

  -- às cegas: calculamos o esperado só depois que o contado já está preso
  -- na transação, então quem fecha não teve como consultar antes.
  v_esperado := kiarys.calcular_esperado_caixa(v_caixa.id);

  update kiarys.caixas
  set status = 'FECHADO',
      usuario_fechamento = v_perfil.id,
      fechado_em = now(),
      valor_contado = p_valor_contado,
      valor_esperado = v_esperado,
      diferenca = p_valor_contado - v_esperado
  where id = v_caixa.id
  returning * into v_caixa;

  return v_caixa;
end;
$$;
