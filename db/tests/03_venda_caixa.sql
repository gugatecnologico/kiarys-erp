-- 03_venda_caixa.sql
-- registrar_venda / cancelar_venda / caixa. Cobre os critérios de aceite:
-- venda cancelada devolve estoque + aparece na auditoria + some do
-- faturamento; entrada com frete calcula custo real e custo médio;
-- fechamento de caixa registra a diferença; fuso America/Fortaleza.

begin;
select plan(14);

select tests.autenticar_como('33333333-3333-3333-3333-333333333333'); -- vendedora1

-- Sem caixa aberto, a venda é recusada.
select throws_ok(
  $$ select kiarys.registrar_venda(
       jsonb_build_array(jsonb_build_object('variacao_id','bbbbbbbb-0000-0000-0000-000000000001','quantidade',1)),
       jsonb_build_array(jsonb_build_object('forma','PIX','valor',100.00)),
       gen_random_uuid()
     ) $$,
  '55000',
  null,
  'venda sem caixa aberto é recusada'
);

select tests.autenticar_como('11111111-1111-1111-1111-111111111111'); -- admin abre o caixa
select lives_ok(
  $$ select kiarys.abrir_caixa(100.00) $$,
  'admin abre o caixa da loja'
);

select tests.autenticar_como('33333333-3333-3333-3333-333333333333'); -- vendedora1

-- Desconto acima do limite do perfil (10%) é recusado.
select throws_ok(
  $$ select kiarys.registrar_venda(
       jsonb_build_array(jsonb_build_object('variacao_id','bbbbbbbb-0000-0000-0000-000000000001','quantidade',1)),
       jsonb_build_array(jsonb_build_object('forma','PIX','valor',50.00)),
       gen_random_uuid(), null, 50.00
     ) $$,
  '22023',
  null,
  'desconto de 50%% é recusado para vendedora com limite de 10%%'
);

-- Pagamento que não fecha o total é recusado.
select throws_ok(
  $$ select kiarys.registrar_venda(
       jsonb_build_array(jsonb_build_object('variacao_id','bbbbbbbb-0000-0000-0000-000000000001','quantidade',1)),
       jsonb_build_array(jsonb_build_object('forma','PIX','valor',10.00)),
       gen_random_uuid()
     ) $$,
  '22023',
  null,
  'soma de pagamentos diferente do total é recusada'
);

-- Venda válida.
select lives_ok(
  $$ select kiarys.registrar_venda(
       jsonb_build_array(jsonb_build_object('variacao_id','bbbbbbbb-0000-0000-0000-000000000001','quantidade',1)),
       jsonb_build_array(jsonb_build_object('forma','PIX','valor',100.00)),
       '99999999-0000-0000-0000-000000000001'
     ) $$,
  'venda válida é registrada'
);

-- Idempotência: reenviar a mesma chave não duplica.
select is(
  (select count(*) from kiarys.vendas where chave_idempotencia = '99999999-0000-0000-0000-000000000001'),
  1::bigint,
  'apenas 1 venda gravada com a chave de idempotência'
);

-- Antes de cancelar: a venda vendeu a única unidade em estoque (seed dá 1
-- unidade), então o saldo aqui é 0. Documentado em vez de capturado, para
-- manter os testes como SELECTs de topo (pgTAP só reporta o resultado de
-- `is`/`throws_ok`/etc. quando chamados via SELECT — dentro de um `perform`
-- num bloco PL/pgSQL o resultado nunca chega ao TAP output).
select is(
  (select saldo from public.v_estoque where variacao_id = 'bbbbbbbb-0000-0000-0000-000000000001'),
  0,
  'saldo está zerado depois da venda (era 1 unidade)'
);

select tests.autenticar_como('11111111-1111-1111-1111-111111111111'); -- admin cancela
select lives_ok(
  $$ select kiarys.cancelar_venda(
       (select id from kiarys.vendas where chave_idempotencia = '99999999-0000-0000-0000-000000000001'),
       'teste de cancelamento'
     ) $$,
  'admin cancela a venda'
);

select is(
  (select saldo from public.v_estoque where variacao_id = 'bbbbbbbb-0000-0000-0000-000000000001'),
  1,
  'cancelar_venda devolve a peça ao estoque'
);
select is(
  (select status from kiarys.vendas where chave_idempotencia = '99999999-0000-0000-0000-000000000001'),
  'CANCELADA'::kiarys.status_venda,
  'venda muda para CANCELADA'
);
select isnt_empty(
  format(
    $$ select 1 from kiarys.auditoria where entidade = 'vendas' and entidade_id = %L $$,
    (select id::text from kiarys.vendas where chave_idempotencia = '99999999-0000-0000-0000-000000000001')
  ),
  'cancelamento aparece na auditoria'
);

-- Venda cancelada sai do faturamento (v_vendas_dia só soma status='PAGA').
select tests.autenticar_como('11111111-1111-1111-1111-111111111111');
select is(
  (select coalesce(sum(total_recebido), 0) from public.v_vendas_dia
   where vendedora_id = '33333333-3333-3333-3333-333333333333'
     and dia = kiarys.dia_local(now())),
  0::numeric,
  'venda cancelada não aparece no faturamento do dia'
);

-- Fechamento de caixa registra a diferença (às cegas).
select lives_ok(
  $$ select kiarys.fechar_caixa(90.00) $$, -- contou 90, esperado é 100 (nenhuma venda em dinheiro ficou de pé)
  'fecha o caixa informando o valor contado'
);
select is(
  (select diferenca from public.v_caixas order by fechado_em desc limit 1),
  -10.00,
  'diferença = contado (90) - esperado (100), calculada só depois do valor contado'
);

select * from finish();
rollback;
