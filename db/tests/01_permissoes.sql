-- 01_permissoes.sql
-- Critério de aceite: "Uma vendedora chamando a API direto não consegue
-- ler custo, margem nem vendas de outras pessoas."

begin;
select plan(8);

select tests.autenticar_como('33333333-3333-3333-3333-333333333333'); -- vendedora1

-- v_estoque nunca tem coluna de custo (nem chega a existir a coluna).
select isnt_empty(
  $$ select 1 from information_schema.views where table_name = 'v_estoque' $$,
  'view v_estoque existe'
);
select is(
  (select count(*) from information_schema.columns where table_name = 'v_estoque' and column_name in ('custo_medio', 'custo_unitario')),
  0::bigint,
  'v_estoque não expõe nenhuma coluna de custo'
);

-- v_estoque_admin devolve 0 linhas para vendedora (tem itens de teste com estoque).
select is(
  (select count(*) from public.v_estoque_admin),
  0::bigint,
  'vendedora não vê nenhuma linha de v_estoque_admin'
);

-- v_margem devolve 0 linhas para vendedora.
select is(
  (select count(*) from public.v_margem),
  0::bigint,
  'vendedora não vê nenhuma linha de v_margem'
);

-- produtos/variacoes: SELECT direto é negado (sem grant).
select throws_ok(
  $$ select * from kiarys.variacoes limit 1 $$,
  '42501',
  null,
  'vendedora não tem SELECT direto em kiarys.variacoes'
);

-- v_minhas_vendas só mostra vendas da própria vendedora.
select is(
  (select count(*) from public.v_minhas_vendas where vendedora_id <> '33333333-3333-3333-3333-333333333333'),
  0::bigint,
  'vendedora não vê venda de outra pessoa em v_minhas_vendas'
);

-- Admin, ao contrário, vê tudo.
select tests.autenticar_como('11111111-1111-1111-1111-111111111111'); -- admin
select ok(
  (select kiarys.pode_ver_custo()),
  'admin pode ver custo'
);
select ok(
  (select count(*) from public.v_estoque_admin) >= 0, -- não deve dar exceção
  'admin consegue consultar v_estoque_admin sem erro'
);

select * from finish();
rollback;
