-- 04_entrada_fuso.sql
-- Critérios: "entrada com frete mostra o custo real e atualiza o custo
-- médio" / "relatórios usam o fuso America/Fortaleza".

begin;
select plan(3);

-- Fixture criada ANTES de trocar pra kiarys_app: produtos/variacoes não
-- têm nenhum grant direto (só por RPC/view — ver 0014), então um INSERT
-- solto nelas só funciona rodando como o dono do banco.
insert into kiarys.produtos (id, referencia, nome) values ('aaaaaaaa-0000-0000-0000-000000000002', 'REFTEST02', 'Produto Teste 2');
insert into kiarys.variacoes (id, produto_id, tamanho, cor, preco_venda)
values ('bbbbbbbb-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000002', 'M', 'Preto', 150.00);

select tests.autenticar_como('11111111-1111-1111-1111-111111111111'); -- admin

-- Entrada de 10 unidades a R$50 com R$100 de frete (tudo num item só,
-- então 100% do frete vai pra ela): custo real = 50 + 100/10 = 60.

select lives_ok(
  $$ select kiarys.registrar_entrada(
       null,
       jsonb_build_array(jsonb_build_object('variacao_id','bbbbbbbb-0000-0000-0000-000000000002','quantidade',10,'custo_unitario_nf',50.00)),
       100.00, 0, 'NF-TESTE-001'
     ) $$,
  'admin registra entrada com frete'
);

select is(
  (select custo_medio from public.v_estoque_admin where variacao_id = 'bbbbbbbb-0000-0000-0000-000000000002'),
  60.00,
  'custo médio = custo NF (50) + frete rateado (100/10 = 10)'
);

-- dia_local: 23h de 15/03 em Fortaleza (UTC-3) é ainda 15/03 local, mas
-- já seria 16/03 em UTC puro — prova que a conversão de fuso está sendo
-- aplicada, e não um cast direto.
select is(
  kiarys.dia_local('2026-03-15 23:30:00-03'::timestamptz),
  '2026-03-15'::date,
  'dia_local calcula pelo fuso America/Fortaleza, não pelo UTC'
);

select * from finish();
rollback;
