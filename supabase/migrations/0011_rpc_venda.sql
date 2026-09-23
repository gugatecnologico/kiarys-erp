-- 0011_rpc_venda.sql
-- registrar_venda / cancelar_venda — o coração do sistema.
--
-- itens:      jsonb[] de {"variacao_id": uuid, "quantidade": int, "desconto_item": numeric?}
-- pagamentos: jsonb[] de {"forma": text, "valor": numeric, "parcelas": int?}
--
-- Preço NUNCA vem do cliente: é lido dentro da função via preco_efetivo().
-- Desconto validado contra o limite do perfil. Trava de concorrência via
-- FOR UPDATE em estoque_saldos, em ordem fixa de variacao_id (evita
-- deadlock entre duas vendas que compartilham peças).

set search_path = kiarys, public;

create or replace function kiarys.registrar_venda(
  p_itens             jsonb,
  p_pagamentos        jsonb,
  p_chave_idempotencia uuid,
  p_cliente_id        uuid default null,
  p_desconto_geral    numeric default 0
)
returns kiarys.vendas
language plpgsql
security definer
set search_path = kiarys, public
as $$
declare
  v_perfil        kiarys.perfis := kiarys.perfil_atual();
  v_caixa         kiarys.caixas;
  v_venda         kiarys.vendas;
  v_item          jsonb;
  v_pagamento     jsonb;
  v_variacao_ids  uuid[];
  v_subtotal      numeric(12,2) := 0;
  v_desconto_itens numeric(12,2) := 0;
  v_desconto      numeric(12,2);
  v_total         numeric(12,2);
  v_soma_pagto    numeric(12,2) := 0;
  v_limite        numeric(5,2);
  v_saldo         integer;
  v_preco         numeric(12,2);
  v_custo         numeric(12,2);
  v_taxa          numeric(5,2);
begin
  if p_chave_idempotencia is null then
    raise exception 'chave_idempotencia é obrigatória' using errcode = '22023';
  end if;

  -- Idempotência: reenviar a mesma chave devolve a venda já criada em vez
  -- de duplicar (celular reenviando após queda de rede, duplo toque etc).
  select * into v_venda from kiarys.vendas where chave_idempotencia = p_chave_idempotencia;
  if v_venda.id is not null then
    return v_venda;
  end if;

  if jsonb_array_length(p_itens) = 0 then
    raise exception 'venda sem itens' using errcode = '22023';
  end if;
  if jsonb_array_length(p_pagamentos) = 0 then
    raise exception 'venda sem pagamento' using errcode = '22023';
  end if;

  select * into v_caixa from kiarys.caixas where status = 'ABERTO' for update;
  if v_caixa.id is null then
    raise exception 'não há caixa aberto — abra o caixa antes de vender' using errcode = '55000';
  end if;

  -- Trava as variações em ordem fixa (evita deadlock entre vendas
  -- concorrentes pelas mesmas peças) e confere saldo.
  select array_agg(distinct (elem->>'variacao_id')::uuid order by (elem->>'variacao_id')::uuid)
    into v_variacao_ids
  from jsonb_array_elements(p_itens) elem;

  perform 1 from kiarys.estoque_saldos
  where variacao_id = any(v_variacao_ids)
  order by variacao_id
  for update;

  -- Monta a venda (cabeçalho) primeiro para termos o id/numero nos
  -- movimentos; o total é corrigido no fim, quando já sabemos subtotal
  -- e desconto reais.
  insert into kiarys.vendas (
    caixa_id, vendedora_id, cliente_id, subtotal, desconto, total,
    chave_idempotencia
  ) values (
    v_caixa.id, v_perfil.id, p_cliente_id, 0, 0, 0, p_chave_idempotencia
  ) returning * into v_venda;

  for v_item in select * from jsonb_array_elements(p_itens)
  loop
    if coalesce((v_item->>'quantidade')::int, 0) <= 0 then
      raise exception 'quantidade inválida no item' using errcode = '22023';
    end if;

    select qtd into v_saldo
    from kiarys.estoque_saldos
    where variacao_id = (v_item->>'variacao_id')::uuid;

    if v_saldo is null or v_saldo < (v_item->>'quantidade')::int then
      raise exception 'sem estoque suficiente para a variação %', (v_item->>'variacao_id')
        using errcode = '23514', hint = 'sem_estoque';
    end if;

    select kiarys.preco_efetivo(v.id), v.custo_medio
      into v_preco, v_custo
    from kiarys.variacoes v
    where v.id = (v_item->>'variacao_id')::uuid;

    v_subtotal := v_subtotal + v_preco * (v_item->>'quantidade')::int;
    v_desconto_itens := v_desconto_itens + coalesce((v_item->>'desconto_item')::numeric, 0);

    insert into kiarys.venda_itens (venda_id, variacao_id, quantidade, preco_unitario, desconto_item, custo_unitario)
    values (
      v_venda.id, (v_item->>'variacao_id')::uuid, (v_item->>'quantidade')::int,
      v_preco, coalesce((v_item->>'desconto_item')::numeric, 0), v_custo
    );

    insert into kiarys.movimentos_estoque (variacao_id, tipo, quantidade, custo_unitario, ref_tipo, ref_id, usuario_id)
    values (
      (v_item->>'variacao_id')::uuid, 'VENDA', -1 * (v_item->>'quantidade')::int,
      v_custo, 'venda', v_venda.id, v_perfil.id
    );
  end loop;

  v_desconto := v_desconto_itens + coalesce(p_desconto_geral, 0);
  v_total := v_subtotal - v_desconto;

  if v_total < 0 then
    raise exception 'desconto maior que o subtotal' using errcode = '22023';
  end if;

  -- Limite de desconto do perfil (NULL = livre — só faz sentido para
  -- admin). Para gerente sem limite próprio, cai no limite_desconto_gerente_pct
  -- de configurações; sem nenhum dos dois, gerente também tem desconto livre.
  v_limite := v_perfil.limite_desconto_pct;
  if v_limite is null and v_perfil.papel = 'gerente' then
    select limite_desconto_gerente_pct into v_limite from kiarys.configuracoes limit 1;
  end if;

  if v_limite is not null and v_subtotal > 0 and (v_desconto / v_subtotal * 100) > v_limite then
    raise exception 'desconto de % excede o limite de % do seu perfil',
      round(v_desconto / v_subtotal * 100, 2)::text || '%', v_limite::text || '%'
      using errcode = '22023';
  end if;

  for v_pagamento in select * from jsonb_array_elements(p_pagamentos)
  loop
    if (v_pagamento->>'forma')::kiarys.forma_pagamento in ('CREDIARIO', 'VALE') then
      raise exception 'forma de pagamento % ainda não disponível (v2)', v_pagamento->>'forma'
        using errcode = '0A000';
    end if;
    if coalesce((v_pagamento->>'valor')::numeric, 0) <= 0 then
      raise exception 'valor de pagamento inválido' using errcode = '22023';
    end if;

    select taxa_pct into v_taxa
    from kiarys.taxas_pagamento
    where forma = (v_pagamento->>'forma')::kiarys.forma_pagamento
      and parcelas = coalesce((v_pagamento->>'parcelas')::smallint, 1);

    insert into kiarys.pagamentos (venda_id, forma, valor, parcelas, taxa_pct)
    values (
      v_venda.id, (v_pagamento->>'forma')::kiarys.forma_pagamento,
      (v_pagamento->>'valor')::numeric, coalesce((v_pagamento->>'parcelas')::smallint, 1),
      coalesce(v_taxa, 0)
    );

    v_soma_pagto := v_soma_pagto + (v_pagamento->>'valor')::numeric;
  end loop;

  if abs(v_soma_pagto - v_total) > 0.01 then
    raise exception 'soma dos pagamentos (%) não bate com o total (%)', v_soma_pagto, v_total
      using errcode = '22023';
  end if;

  update kiarys.vendas
  set subtotal = v_subtotal, desconto = v_desconto, total = v_total
  where id = v_venda.id
  returning * into v_venda;

  return v_venda;
end;
$$;

create or replace function kiarys.cancelar_venda(p_venda_id uuid, p_motivo text)
returns kiarys.vendas
language plpgsql
security definer
set search_path = kiarys, public
as $$
declare
  v_perfil    kiarys.perfis := kiarys.perfil_atual();
  v_venda     kiarys.vendas;
  v_item      kiarys.venda_itens;
  v_dinheiro  numeric(12,2);
  v_caixa_aberto kiarys.caixas;
begin
  if v_perfil.papel not in ('gerente', 'admin') then
    raise exception 'só gerente ou admin pode cancelar venda' using errcode = '42501';
  end if;
  if btrim(coalesce(p_motivo, '')) = '' then
    raise exception 'motivo é obrigatório' using errcode = '22023';
  end if;

  select * into v_venda from kiarys.vendas where id = p_venda_id for update;
  if v_venda.id is null then
    raise exception 'venda não encontrada' using errcode = '22023';
  end if;
  if v_venda.status = 'CANCELADA' then
    raise exception 'venda já está cancelada' using errcode = '22023';
  end if;

  for v_item in select * from kiarys.venda_itens where venda_id = v_venda.id
  loop
    insert into kiarys.movimentos_estoque (variacao_id, tipo, quantidade, custo_unitario, ref_tipo, ref_id, motivo, usuario_id)
    values (v_item.variacao_id, 'ESTORNO_VENDA', v_item.quantidade, v_item.custo_unitario, 'venda', v_venda.id, p_motivo, v_perfil.id);
  end loop;

  -- Estorno em dinheiro sai do caixa aberto de quem cancelou (decisão do
  -- dono, ver README) — por isso exige caixa aberto quando há dinheiro
  -- envolvido no pagamento original.
  select coalesce(sum(valor), 0) into v_dinheiro
  from kiarys.pagamentos where venda_id = v_venda.id and forma = 'DINHEIRO';

  if v_dinheiro > 0 then
    select * into v_caixa_aberto from kiarys.caixas where status = 'ABERTO' for update;
    if v_caixa_aberto.id is null then
      raise exception 'venda tem pagamento em dinheiro — abra o caixa antes de cancelar' using errcode = '55000';
    end if;

    insert into kiarys.caixa_movimentos (caixa_id, tipo, valor, motivo, usuario_id)
    values (v_caixa_aberto.id, 'SANGRIA', v_dinheiro, 'Estorno da venda #' || v_venda.numero, v_perfil.id);
  end if;

  update kiarys.vendas
  set status = 'CANCELADA',
      motivo_cancelamento = p_motivo,
      cancelada_por = v_perfil.id,
      cancelada_em = now()
  where id = v_venda.id
  returning * into v_venda;

  insert into kiarys.auditoria (usuario_id, acao, entidade, entidade_id, antes, depois)
  values (v_perfil.id, 'CANCELAR_VENDA', 'vendas', v_venda.id::text,
          jsonb_build_object('status', 'PAGA'),
          jsonb_build_object('status', 'CANCELADA', 'motivo', p_motivo));

  return v_venda;
end;
$$;

comment on function kiarys.registrar_venda is
  'RPC única de venda. Preço sempre lido via preco_efetivo() — nunca '
  'confiar em valor vindo do cliente. Idempotente por chave_idempotencia.';
