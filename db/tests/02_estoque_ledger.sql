-- 02_estoque_ledger.sql
-- Critérios: "Nenhuma tela permite editar saldo diretamente. Só existem
-- movimentos." / "UPDATE e DELETE em movimentos falham."

begin;
select plan(5);

select throws_ok(
  $$ update kiarys.movimentos_estoque set quantidade = 999 where id = (select id from kiarys.movimentos_estoque limit 1) $$,
  '0A000',
  'movimentos_estoque é insert-only — lance um movimento de correção, nunca altere ou apague um existente',
  'UPDATE em movimentos_estoque é bloqueado pelo trigger'
);

select throws_ok(
  $$ delete from kiarys.movimentos_estoque where id = (select id from kiarys.movimentos_estoque limit 1) $$,
  '0A000',
  'movimentos_estoque é insert-only — lance um movimento de correção, nunca altere ou apague um existente',
  'DELETE em movimentos_estoque é bloqueado pelo trigger'
);

-- CHECK (qtd >= 0): trava mesmo sem passar pela RPC, se algo tentasse
-- lançar um movimento que estourasse o saldo negativo. Roda como o dono
-- do banco (sem trocar de role) — é o CHECK em si que está sob teste,
-- não GRANT/RLS, que já têm teste próprio em 01_permissoes.sql.
select throws_ok(
  format(
    $$ insert into kiarys.movimentos_estoque (variacao_id, tipo, quantidade, usuario_id)
       values ('bbbbbbbb-0000-0000-0000-000000000001', 'AJUSTE', -999999, %L) $$,
    '11111111-1111-1111-1111-111111111111'
  ),
  '23514',
  null,
  'CHECK (qtd >= 0) barra saldo negativo mesmo em INSERT direto de movimento'
);

-- Saldo é sempre a soma dos movimentos (o cache bate com o ledger).
select is(
  (select qtd from kiarys.estoque_saldos where variacao_id = 'bbbbbbbb-0000-0000-0000-000000000001'),
  (select coalesce(sum(quantidade), 0)::int from kiarys.movimentos_estoque where variacao_id = 'bbbbbbbb-0000-0000-0000-000000000001'),
  'estoque_saldos.qtd é exatamente a soma dos movimentos da variação'
);

-- Saldo nunca é digitado: não existe UPDATE direto liberado em
-- estoque_saldos, nem para admin (sem grant nenhum pra kiarys_app).
select tests.autenticar_como('11111111-1111-1111-1111-111111111111'); -- admin
select throws_ok(
  $$ update kiarys.estoque_saldos set qtd = 999 where variacao_id = 'bbbbbbbb-0000-0000-0000-000000000001' $$,
  '42501',
  null,
  'nem admin tem UPDATE direto em estoque_saldos — só o trigger de movimento escreve ali'
);

select * from finish();
rollback;
