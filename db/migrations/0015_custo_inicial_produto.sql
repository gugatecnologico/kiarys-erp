-- 0015_custo_inicial_produto.sql
-- Custo inicial opcional no cadastro de produto — só pra quem
-- pode_ver_custo() (admin, ou gerente se o flag estiver ligado). Sem
-- estoque ainda (saldo 0 até a primeira entrada), então isso não é uma
-- gravação no ledger: só um valor de referência guardado direto na
-- variação. O primeiro registrar_entrada() já SOBRESCREVE esse valor com
-- o custo médio ponderado de verdade (ver a fórmula em 0012: com
-- saldo_atual=0, o resultado é sempre o custo_real da entrada) — este
-- número existe só pra não deixar custo_medio="0" mentindo enquanto a
-- peça ainda não teve entrada formal.

set search_path = kiarys, public;

create or replace function kiarys.criar_produto_com_grade(
  p_referencia    text,
  p_nome          text,
  p_categoria_id  uuid,
  p_colecao_id    uuid,
  p_fornecedor_id uuid,
  p_preco_venda   numeric,
  p_tamanhos      text[],
  p_cores         text[],
  p_foto_url      text default null,
  p_custo_medio   numeric default null
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
  if p_custo_medio is not null and not kiarys.pode_ver_custo() then
    raise exception 'sem permissão para definir custo' using errcode = '42501';
  end if;

  insert into kiarys.produtos (referencia, nome, categoria_id, colecao_id, fornecedor_id, foto_url)
  values (p_referencia, p_nome, p_categoria_id, p_colecao_id, p_fornecedor_id, p_foto_url)
  returning * into v_produto;

  foreach v_tamanho in array p_tamanhos loop
    foreach v_cor in array p_cores loop
      insert into kiarys.variacoes (produto_id, tamanho, cor, preco_venda, custo_medio)
      values (v_produto.id, v_tamanho, v_cor, p_preco_venda, coalesce(p_custo_medio, 0));
    end loop;
  end loop;

  return v_produto;
end;
$$;
