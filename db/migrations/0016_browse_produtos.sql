-- 0016_browse_produtos.sql
-- Views de busca também servem de LISTAGEM (tela abre já mostrando o
-- catálogo, não uma tela em branco esperando digitação) — pra isso
-- v_produtos_busca ganha categoria_id (pra filtrar por categoria no
-- front sem precisar digitar nada) e as duas views passam a vir
-- ordenadas por nome, já que "buscar sem termo" agora é um caso de uso
-- de verdade, não só um acidente de query vazia.

set search_path = public;

create or replace view public.v_produtos_busca as
select
  p.id as produto_id, p.referencia, p.nome, p.foto_url, p.ativo,
  min(v.preco_venda) as preco_min, max(v.preco_venda) as preco_max,
  coalesce(sum(s.qtd), 0) as saldo_total,
  p.categoria_id
from kiarys.produtos p
join kiarys.variacoes v on v.produto_id = p.id
left join kiarys.estoque_saldos s on s.variacao_id = v.id
group by p.id
order by p.nome;

create or replace view public.v_estoque as
select
  p.id as produto_id, p.referencia, p.nome, p.foto_url, p.ativo as produto_ativo,
  v.id as variacao_id, v.tamanho, v.cor, v.codigo_barras,
  v.preco_venda, v.preco_promocional, v.promo_ate,
  kiarys.preco_efetivo(v.id) as preco_efetivo,
  coalesce(s.qtd, 0) as saldo, v.estoque_minimo, v.ativo as variacao_ativa
from kiarys.variacoes v
join kiarys.produtos p on p.id = v.produto_id
left join kiarys.estoque_saldos s on s.variacao_id = v.id
order by p.nome, v.tamanho, v.cor;
