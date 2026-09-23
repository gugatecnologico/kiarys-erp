-- 0012_rpc_estoque.sql
-- criar_produto_com_grade / importar_produtos / registrar_entrada /
-- ajustar_estoque / alterar_precos. Todas exigem pode_cadastrar() (admin,
-- ou gerente se configuracoes.gerente_cadastra = true), exceto
-- ajustar_estoque, que é admin-only (seção 5: "Ajuste de estoque / perda
-- → ❌ vendedora, ❌ gerente, ✅ admin").

set search_path = kiarys, public;

-- Cria o produto e já gera a grade tamanho × cor pedida (seção 6, item 2:
-- "cadastro com geração automática da grade").
create or replace function kiarys.criar_produto_com_grade(
  p_referencia    text,
  p_nome          text,
  p_categoria_id  uuid,
  p_colecao_id    uuid,
  p_fornecedor_id uuid,
  p_preco_venda   numeric,
  p_tamanhos      text[],
  p_cores         text[],
  p_foto_url      text default null
)
returns kiarys.produtos
language plpgsql
security definer
set search_path = kiarys, public
as $$
declare
  v_produto kiarys.produtos;
  v_tamanho text;
  v_cor     text;
begin
  if not kiarys.pode_cadastrar() then
    raise exception 'sem permissão para cadastrar produto' using errcode = '42501';
  end if;
  if array_length(p_tamanhos, 1) is null or array_length(p_cores, 1) is null then
    raise exception 'informe ao menos um tamanho e uma cor' using errcode = '22023';
  end if;

  insert into kiarys.produtos (referencia, nome, categoria_id, colecao_id, fornecedor_id, foto_url)
  values (p_referencia, p_nome, p_categoria_id, p_colecao_id, p_fornecedor_id, p_foto_url)
  returning * into v_produto;

  foreach v_tamanho in array p_tamanhos loop
    foreach v_cor in array p_cores loop
      insert into kiarys.variacoes (produto_id, tamanho, cor, preco_venda)
      values (v_produto.id, v_tamanho, v_cor, p_preco_venda);
    end loop;
  end loop;

  return v_produto;
end;
$$;

-- Importação em massa por CSV (seção 6, item 2). O frontend faz o parse
-- do CSV e manda um jsonb[] já estruturado — a função só valida e grava,
-- não faz parsing de texto solto.
-- Formato de cada elemento:
-- {"referencia","nome","categoria","colecao","fornecedor","tamanho","cor",
--  "preco_venda","codigo_barras"?,"estoque_inicial"?}
-- categoria/colecao/fornecedor são criados sob demanda se não existirem
-- (find-or-create pelo nome), para não travar a carga inicial grande.
create or replace function kiarys.importar_produtos(p_linhas jsonb)
returns table(linha int, ok boolean, erro text)
language plpgsql
security definer
set search_path = kiarys, public
as $$
declare
  v_linha       jsonb;
  v_idx         int := 0;
  v_produto_id  uuid;
  v_categoria_id uuid;
  v_colecao_id  uuid;
  v_fornecedor_id uuid;
  v_variacao_id uuid;
  v_estoque_inicial int;
begin
  if not kiarys.pode_cadastrar() then
    raise exception 'sem permissão para importar produtos' using errcode = '42501';
  end if;

  for v_linha in select * from jsonb_array_elements(p_linhas)
  loop
    v_idx := v_idx + 1;
    begin
      v_categoria_id := null;
      if v_linha ? 'categoria' and btrim(v_linha->>'categoria') <> '' then
        insert into kiarys.categorias (nome) values (btrim(v_linha->>'categoria'))
        on conflict (nome) do update set nome = excluded.nome
        returning id into v_categoria_id;
      end if;

      v_fornecedor_id := null;
      if v_linha ? 'fornecedor' and btrim(v_linha->>'fornecedor') <> '' then
        select id into v_fornecedor_id from kiarys.fornecedores where nome = btrim(v_linha->>'fornecedor');
        if v_fornecedor_id is null then
          insert into kiarys.fornecedores (nome) values (btrim(v_linha->>'fornecedor'))
          returning id into v_fornecedor_id;
        end if;
      end if;

      v_colecao_id := null;
      if v_linha ? 'colecao' and btrim(v_linha->>'colecao') <> '' then
        select id into v_colecao_id from kiarys.colecoes where nome = btrim(v_linha->>'colecao');
        if v_colecao_id is null then
          insert into kiarys.colecoes (nome) values (btrim(v_linha->>'colecao'))
          returning id into v_colecao_id;
        end if;
      end if;

      insert into kiarys.produtos (referencia, nome, categoria_id, colecao_id, fornecedor_id)
      values (v_linha->>'referencia', v_linha->>'nome', v_categoria_id, v_colecao_id, v_fornecedor_id)
      on conflict (referencia) do update set nome = excluded.nome
      returning id into v_produto_id;

      -- coalesce pro gerador explícito, e não deixar NULL cair no INSERT:
      -- passar NULL numa coluna listada no INSERT NÃO aciona o DEFAULT da
      -- coluna (isso só acontece se a coluna for omitida da lista) — sem
      -- o coalesce, toda linha sem código de barras próprio quebraria o
      -- NOT NULL de variacoes.codigo_barras.
      insert into kiarys.variacoes (produto_id, tamanho, cor, preco_venda, codigo_barras)
      values (
        v_produto_id, v_linha->>'tamanho', v_linha->>'cor',
        (v_linha->>'preco_venda')::numeric,
        coalesce(nullif(v_linha->>'codigo_barras', ''), kiarys.gerar_codigo_barras())
      )
      on conflict (produto_id, tamanho, cor) do update set preco_venda = excluded.preco_venda
      returning id into v_variacao_id;

      -- Estoque inicial da carga vira um movimento ENTRADA normal — nunca
      -- um UPDATE direto no saldo (princípio 1 do brief).
      v_estoque_inicial := nullif(v_linha->>'estoque_inicial', '')::int;
      if v_estoque_inicial is not null and v_estoque_inicial > 0 then
        insert into kiarys.movimentos_estoque (variacao_id, tipo, quantidade, custo_unitario, ref_tipo, motivo, usuario_id)
        values (v_variacao_id, 'ENTRADA', v_estoque_inicial, 0, 'importacao_csv', 'carga inicial', (kiarys.perfil_atual()).id);
      end if;

      linha := v_idx; ok := true; erro := null;
      return next;
    exception when others then
      linha := v_idx; ok := false; erro := sqlerrm;
      return next;
    end;
  end loop;
end;
$$;

comment on function kiarys.importar_produtos is
  'Cada linha roda em savepoint próprio (o EXCEPTION dentro do loop faz '
  'isso) — uma linha ruim não derruba a carga inteira. O relatório de '
  'linha/ok/erro é o que a tela de importação mostra.';

create or replace function kiarys.registrar_entrada(
  p_fornecedor_id   uuid,
  p_itens           jsonb, -- [{"variacao_id","quantidade","custo_unitario_nf"}]
  p_frete           numeric default 0,
  p_outras_despesas numeric default 0,
  p_doc_ref         text default null
)
returns kiarys.entradas
language plpgsql
security definer
set search_path = kiarys, public
as $$
declare
  v_perfil kiarys.perfis := kiarys.perfil_atual();
  v_entrada kiarys.entradas;
  v_item jsonb;
  v_valor_total_itens numeric(12,2) := 0;
  v_custo_real numeric(12,2);
  v_saldo_atual integer;
  v_custo_atual numeric(12,2);
  v_novo_custo numeric(12,2);
begin
  if not kiarys.pode_cadastrar() then
    raise exception 'sem permissão para registrar entrada' using errcode = '42501';
  end if;
  if jsonb_array_length(p_itens) = 0 then
    raise exception 'entrada sem itens' using errcode = '22023';
  end if;

  select coalesce(sum((elem->>'quantidade')::numeric * (elem->>'custo_unitario_nf')::numeric), 0)
    into v_valor_total_itens
  from jsonb_array_elements(p_itens) elem;

  if v_valor_total_itens <= 0 then
    raise exception 'valor total dos itens precisa ser maior que zero para ratear frete/despesas' using errcode = '22023';
  end if;

  insert into kiarys.entradas (fornecedor_id, frete, outras_despesas, total_itens, doc_ref, usuario_id)
  values (p_fornecedor_id, p_frete, p_outras_despesas, v_valor_total_itens, p_doc_ref, v_perfil.id)
  returning * into v_entrada;

  for v_item in select * from jsonb_array_elements(p_itens)
  loop
    -- Custo real = custo NF + rateio de (frete + despesas) proporcional ao
    -- valor do item (fórmula da seção 7).
    v_custo_real := (v_item->>'custo_unitario_nf')::numeric
      + (p_frete + p_outras_despesas)
        * ((v_item->>'quantidade')::numeric * (v_item->>'custo_unitario_nf')::numeric / v_valor_total_itens)
        / (v_item->>'quantidade')::numeric;

    insert into kiarys.entrada_itens (entrada_id, variacao_id, quantidade, custo_unitario_nf, custo_unitario_real)
    values (v_entrada.id, (v_item->>'variacao_id')::uuid, (v_item->>'quantidade')::int,
            (v_item->>'custo_unitario_nf')::numeric, v_custo_real);

    select qtd, custo_medio into v_saldo_atual, v_custo_atual
    from kiarys.variacoes v
    left join kiarys.estoque_saldos s on s.variacao_id = v.id
    where v.id = (v_item->>'variacao_id')::uuid
    for update of v;

    v_saldo_atual := coalesce(v_saldo_atual, 0);

    -- Custo médio ponderado (seção 2, princípio 6).
    v_novo_custo := (v_saldo_atual * coalesce(v_custo_atual, 0) + (v_item->>'quantidade')::numeric * v_custo_real)
                    / (v_saldo_atual + (v_item->>'quantidade')::numeric);

    update kiarys.variacoes set custo_medio = v_novo_custo where id = (v_item->>'variacao_id')::uuid;

    insert into kiarys.movimentos_estoque (variacao_id, tipo, quantidade, custo_unitario, ref_tipo, ref_id, usuario_id)
    values ((v_item->>'variacao_id')::uuid, 'ENTRADA', (v_item->>'quantidade')::int, v_custo_real, 'entrada', v_entrada.id, v_perfil.id);
  end loop;

  return v_entrada;
end;
$$;

-- Ajuste/inventário: só admin, sempre com motivo (seção 6, item 4:
-- "mostra as divergências"; seção 5: ajuste é admin-only).
create or replace function kiarys.ajustar_estoque(p_variacao_id uuid, p_nova_qtd_contada integer, p_motivo text, p_tipo kiarys.tipo_movimento default 'AJUSTE')
returns kiarys.movimentos_estoque
language plpgsql
security definer
set search_path = kiarys, public
as $$
declare
  v_perfil kiarys.perfis := kiarys.perfil_atual();
  v_saldo_atual integer;
  v_custo numeric(12,2);
  v_diferenca integer;
  v_mov kiarys.movimentos_estoque;
begin
  if not kiarys.eh_admin() then
    raise exception 'só admin ajusta estoque' using errcode = '42501';
  end if;
  if p_nova_qtd_contada < 0 then
    raise exception 'quantidade contada não pode ser negativa' using errcode = '22023';
  end if;
  if btrim(coalesce(p_motivo, '')) = '' then
    raise exception 'motivo é obrigatório' using errcode = '22023';
  end if;
  if p_tipo not in ('AJUSTE', 'INVENTARIO', 'PERDA') then
    raise exception 'tipo % não é um ajuste válido', p_tipo using errcode = '22023';
  end if;

  select coalesce(qtd, 0), custo_medio into v_saldo_atual, v_custo
  from kiarys.variacoes v
  left join kiarys.estoque_saldos s on s.variacao_id = v.id
  where v.id = p_variacao_id
  for update of v;

  v_diferenca := p_nova_qtd_contada - v_saldo_atual;
  if v_diferenca = 0 then
    raise exception 'quantidade contada é igual ao saldo atual — nada a ajustar' using errcode = '22023';
  end if;

  insert into kiarys.movimentos_estoque (variacao_id, tipo, quantidade, custo_unitario, ref_tipo, motivo, usuario_id)
  values (p_variacao_id, p_tipo, v_diferenca, coalesce(v_custo, 0), 'ajuste_manual', p_motivo, v_perfil.id)
  returning * into v_mov;

  return v_mov;
end;
$$;

create or replace function kiarys.alterar_precos(p_variacao_id uuid, p_preco_venda numeric, p_preco_promocional numeric default null, p_promo_ate date default null)
returns kiarys.variacoes
language plpgsql
security definer
set search_path = kiarys, public
as $$
declare
  v_variacao kiarys.variacoes;
begin
  if not kiarys.pode_cadastrar() then
    raise exception 'sem permissão para alterar preço' using errcode = '42501';
  end if;
  if p_preco_promocional is not null and p_promo_ate is null then
    raise exception 'preço promocional exige data final (promo_ate)' using errcode = '22023';
  end if;

  update kiarys.variacoes
  set preco_venda = p_preco_venda,
      preco_promocional = p_preco_promocional,
      promo_ate = p_promo_ate
  where id = p_variacao_id
  returning * into v_variacao;

  return v_variacao;
end;
$$;
