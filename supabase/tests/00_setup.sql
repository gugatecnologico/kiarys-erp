-- 00_setup.sql — fixtures compartilhadas pelos testes pgTAP.
-- Roda antes de cada arquivo de teste (supabase test db carrega em ordem
-- alfabética); mantém IDs fixos para os testes referenciarem por nome.

set search_path = kiarys, public;

insert into auth.users (id, instance_id, email, encrypted_password, email_confirmed_at, aud, role)
values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'admin@test.dev', crypt('x', gen_salt('bf')), now(), 'authenticated', 'authenticated'),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'gerente@test.dev', crypt('x', gen_salt('bf')), now(), 'authenticated', 'authenticated'),
  ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000000', 'vendedora1@test.dev', crypt('x', gen_salt('bf')), now(), 'authenticated', 'authenticated'),
  ('44444444-4444-4444-4444-444444444444', '00000000-0000-0000-0000-000000000000', 'vendedora2@test.dev', crypt('x', gen_salt('bf')), now(), 'authenticated', 'authenticated')
on conflict (id) do nothing;

update kiarys.perfis set ativo = true, papel = 'admin' where id = '11111111-1111-1111-1111-111111111111';
update kiarys.perfis set ativo = true, papel = 'gerente', limite_desconto_pct = 15 where id = '22222222-2222-2222-2222-222222222222';
update kiarys.perfis set ativo = true, papel = 'vendedora', limite_desconto_pct = 10, comissao_pct = 5 where id = '33333333-3333-3333-3333-333333333333';
update kiarys.perfis set ativo = true, papel = 'vendedora', limite_desconto_pct = 10, comissao_pct = 5 where id = '44444444-4444-4444-4444-444444444444';

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
-- simulando o que o PostgREST faz — troca a ROLE de postgres para
-- `authenticated` (senão RLS/GRANT nem seriam avaliados, já que postgres
-- tem BYPASSRLS) e seta o claim `sub` que kiarys.perfil_atual() lê via
-- auth.uid().
create schema if not exists tests;

create or replace function tests.autenticar_como(p_id uuid)
returns void
language sql
as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_id)::text, true);
  select set_config('role', 'authenticated', true);
$$;
