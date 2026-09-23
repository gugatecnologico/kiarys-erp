-- 00_setup.sql — fixtures compartilhadas pelos testes pgTAP.
-- Roda antes de cada arquivo de teste (pg_prove carrega em ordem
-- alfabética); mantém IDs fixos para os testes referenciarem por nome.

set search_path = kiarys, public;

insert into kiarys.perfis (id, nome, email, senha_hash, papel, ativo, limite_desconto_pct, comissao_pct)
values
  ('11111111-1111-1111-1111-111111111111', 'Admin Teste', 'admin@test.dev', crypt('x', gen_salt('bf')), 'admin', true, null, 0),
  ('22222222-2222-2222-2222-222222222222', 'Gerente Teste', 'gerente@test.dev', crypt('x', gen_salt('bf')), 'gerente', true, 15, 0),
  ('33333333-3333-3333-3333-333333333333', 'Vendedora 1', 'vendedora1@test.dev', crypt('x', gen_salt('bf')), 'vendedora', true, 10, 5),
  ('44444444-4444-4444-4444-444444444444', 'Vendedora 2', 'vendedora2@test.dev', crypt('x', gen_salt('bf')), 'vendedora', true, 10, 5)
on conflict (id) do nothing;

insert into kiarys.produtos (id, referencia, nome)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'REFTEST01', 'Produto Teste')
on conflict do nothing;

insert into kiarys.variacoes (id, produto_id, tamanho, cor, preco_venda, custo_medio)
values ('bbbbbbbb-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'M', 'Preto', 100.00, 40.00)
on conflict do nothing;

insert into kiarys.movimentos_estoque (variacao_id, tipo, quantidade, custo_unitario, ref_tipo, motivo, usuario_id)
values ('bbbbbbbb-0000-0000-0000-000000000001', 'ENTRADA', 1, 40.00, 'seed_teste', 'estoque para os testes', '11111111-1111-1111-1111-111111111111')
on conflict do nothing;

-- Helper: troca a "sessão" do teste para um dos 4 perfis fixos acima,
-- simulando o que a API faz a cada requisição — troca a ROLE de quem
-- roda os testes (superuser, senão RLS/GRANT nem seriam avaliados) para
-- `kiarys_app`, e seta a GUC `app.uid` que kiarys.uid() lê.
create schema if not exists tests;

create or replace function tests.autenticar_como(p_id uuid)
returns void
language sql
as $$
  select set_config('app.uid', p_id::text, true);
  select set_config('role', 'kiarys_app', true);
$$;

-- Sem isso, a SEGUNDA troca de usuária dentro do mesmo arquivo de teste
-- falha com "permission denied for schema tests": depois da primeira
-- chamada o role corrente já é kiarys_app (baixo privilégio), que não
-- tem USAGE neste schema criado pelo superuser. `tests` só existe no
-- banco de teste, então liberar geral aqui não é risco nenhum.
grant usage on schema tests to public;
grant execute on function tests.autenticar_como(uuid) to public;
