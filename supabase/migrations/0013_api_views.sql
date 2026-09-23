-- 0013_api_views.sql
-- Views em `public` — a única porta de leitura para o schema `kiarys`.
-- Rodam com o privilégio de quem as criou (dono = postgres), então leem
-- kiarys mesmo sem grant direto; a restrição de linha/coluna é feita
-- dentro de cada view via kiarys.pode_ver_custo() / eh_gerente_ou_admin() /
-- perfil_atual(), não por RLS na view (RLS não filtra coluna, só linha —
-- ver nota em 0001).

set search_path = public;

-- Estoque sem custo — o que a tela "Estoque" do Time consulta.
create view public.v_estoque as
select
  p.id as produto_id, p.referencia, p.nome, p.foto_url, p.ativo as produto_ativo,
  v.id as variacao_id, v.tamanho, v.cor, v.codigo_barras,
  v.preco_venda, v.preco_promocional, v.promo_ate,
  kiarys.preco_efetivo(v.id) as preco_efetivo,
  coalesce(s.qtd, 0) as saldo, v.estoque_minimo, v.ativo as variacao_ativa
from kiarys.variacoes v
join kiarys.produtos p on p.id = v.produto_id
left join kiarys.estoque_saldos s on s.variacao_id = v.id;

comment on view public.v_estoque is
  'Grade tamanho × cor com saldo, sem custo. Índices trgm de produtos/'
  'variacoes seguem valendo em filtros ilike/similaridade sobre esta view.';

-- Um produto por linha, para o campo de busca da tela Vender (passo 1:
-- escolhe o produto; a grade completa vem de v_estoque filtrada por
-- produto_id no passo 2).
create view public.v_produtos_busca as
select
  p.id as produto_id, p.referencia, p.nome, p.foto_url, p.ativo,
  min(v.preco_venda) as preco_min, max(v.preco_venda) as preco_max,
  coalesce(sum(s.qtd), 0) as saldo_total
from kiarys.produtos p
join kiarys.variacoes v on v.produto_id = p.id
left join kiarys.estoque_saldos s on s.variacao_id = v.id
group by p.id;

-- Estoque com custo e valor em estoque — 0 linhas para quem
-- pode_ver_custo() nega (vendedora, ou gerente com o flag desligado).
create view public.v_estoque_admin as
select ve.*, v.custo_medio, ve.saldo * v.custo_medio as valor_em_estoque
from public.v_estoque ve
join kiarys.variacoes v on v.id = ve.variacao_id
where kiarys.pode_ver_custo();

-- O caixa aberto da loja (se houver) — todo papel enxerga, é o que a tela
-- Vender consulta para saber se pode vender e o que "Meu caixa" mostra.
create view public.v_caixa_aberto as
select c.*, ua.nome as aberto_por_nome
from kiarys.caixas c
join kiarys.perfis ua on ua.id = c.usuario_abertura
where c.status = 'ABERTO';

-- Histórico de caixas e diferenças — só gerente/admin (seção 6, item 6).
create view public.v_caixas as
select c.*, ua.nome as aberto_por_nome, uf.nome as fechado_por_nome
from kiarys.caixas c
left join kiarys.perfis ua on ua.id = c.usuario_abertura
left join kiarys.perfis uf on uf.id = c.usuario_fechamento
where kiarys.eh_gerente_ou_admin();

-- "Minhas vendas": a própria vendedora vê as suas; gerente/admin veem
-- todas. Comissão zera sozinha em venda cancelada.
create view public.v_minhas_vendas as
select
  vd.id, vd.numero, vd.criado_em, vd.status, vd.vendedora_id, per.nome as vendedora_nome,
  vd.cliente_id, vd.subtotal, vd.desconto, vd.total,
  case when vd.status = 'PAGA' then round(vd.total * per.comissao_pct / 100, 2) else 0 end as comissao,
  kiarys.dia_local(vd.criado_em) as dia
from kiarys.vendas vd
join kiarys.perfis per on per.id = vd.vendedora_id
where vd.vendedora_id = (kiarys.perfil_atual()).id
   or kiarys.eh_gerente_ou_admin();

-- Painel do admin: vendas por vendedora e por forma de pagamento, no dia
-- local do negócio (seção 6, item 1 e seção 8, fuso horário).
create view public.v_vendas_dia as
select
  kiarys.dia_local(vd.criado_em) as dia,
  vd.vendedora_id, per.nome as vendedora_nome,
  pg.forma,
  count(distinct vd.id) as qtd_vendas,
  sum(pg.valor) as total_recebido
from kiarys.vendas vd
join kiarys.pagamentos pg on pg.venda_id = vd.id
join kiarys.perfis per on per.id = vd.vendedora_id
where vd.status = 'PAGA' and kiarys.eh_gerente_ou_admin()
group by 1, 2, 3, 4;

-- Margem por item de venda — receita, custo e margem bruta (fórmula da
-- seção 7). 0 linhas para quem não pode ver custo.
create view public.v_margem as
select
  vd.id as venda_id, kiarys.dia_local(vd.criado_em) as dia,
  vi.variacao_id, prod.id as produto_id, prod.referencia, prod.nome as produto_nome,
  prod.categoria_id, prod.colecao_id,
  vi.quantidade, vi.preco_unitario, vi.custo_unitario,
  vi.quantidade * vi.preco_unitario as receita,
  vi.quantidade * (vi.preco_unitario - vi.custo_unitario) as margem_bruta
from kiarys.venda_itens vi
join kiarys.vendas vd on vd.id = vi.venda_id
join kiarys.variacoes v on v.id = vi.variacao_id
join kiarys.produtos prod on prod.id = v.produto_id
where vd.status = 'PAGA' and kiarys.pode_ver_custo();
