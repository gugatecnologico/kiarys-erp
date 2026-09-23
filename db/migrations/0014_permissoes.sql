-- 0014_permissoes.sql
-- RLS default-deny em toda tabela de `kiarys` + revogação de todo GRANT
-- direto, e liberação explícita só do que a API Node (role `kiarys_app`)
-- precisa: SELECT nas views (0013) e EXECUTE nas RPCs. Ver arquitetura
-- em 0001 — sem Supabase, o navegador nunca fala com o Postgres; só a
-- API tem essa connection string, sempre conectada como `kiarys_app`.
-- Um role só (não dois como anon/authenticated do PostgREST) porque
-- quem diferencia visitante-de-usuário-logado agora é a própria API
-- (que só chama `kiarys.autenticar` antes do login, e RPCs normais
-- depois — nunca os dois ao mesmo tempo na mesma conexão).

set search_path = kiarys, public;

-- DO + IF NOT EXISTS porque CREATE ROLE não aceita IF NOT EXISTS nativo,
-- e as migrations precisam poder rodar mais de uma vez sem quebrar
-- (redeploy, `psql -f` repetido) — ver scripts/migrate.sh.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'kiarys_app') then
    create role kiarys_app login password 'trocar_no_deploy_via_env';
  end if;
end $$;

comment on role kiarys_app is
  'Único role de banco que a API Node usa (DATABASE_URL do serviço no '
  'Railway). A senha real é trocada em produção via '
  '`alter role kiarys_app password ''...''` a partir de uma variável de '
  'ambiente no deploy (ver README) — o literal acima nunca deve ir pro ar.';

-- ── RLS default-deny em toda tabela de kiarys ───────────────────────────
-- Ligar RLS sem nenhuma policy = toda linha invisível pra kiarys_app por
-- padrão, mesmo que um GRANT futuro seja adicionado por engano. Isso é a
-- segunda camada de defesa: a primeira (e a que efetivamente barra hoje)
-- são os REVOKE abaixo.
do $$
declare
  v_tabela text;
begin
  for v_tabela in
    select tablename from pg_tables where schemaname = 'kiarys'
  loop
    execute format('alter table kiarys.%I enable row level security', v_tabela);
    execute format('alter table kiarys.%I force row level security', v_tabela);
  end loop;
end $$;

-- FORCE também vale pro dono da tabela — mas quem roda as migrations
-- (o role de admin do Postgres do Railway, tipicamente `postgres`) é
-- superuser, e superuser tem BYPASSRLS implícito, que tem prioridade
-- sobre FORCE e ignora RLS por completo. É por isso que as RPCs
-- (SECURITY DEFINER, donas = quem rodou a migration) continuam
-- escrevendo em vendas/movimentos_estoque/etc. sem precisar de policy de
-- INSERT nelas: quem faz o INSERT de fato é o dono da função, nunca
-- `kiarys_app` direto. Se um dia isso rodar sob um role dono SEM
-- superuser/BYPASSRLS, dê BYPASSRLS a ele explicitamente.

-- ── Revoga tudo do role da API, libera só o que precisa ─────────────────
revoke all on all tables in schema kiarys from kiarys_app;
revoke all on all sequences in schema kiarys from kiarys_app;
revoke all on all functions in schema kiarys from kiarys_app;

grant usage on schema kiarys to kiarys_app;
grant usage on schema public to kiarys_app;

-- ── Views: SELECT ────────────────────────────────────────────────────────
grant select on
  public.v_estoque, public.v_estoque_admin, public.v_produtos_busca,
  public.v_caixa_aberto, public.v_caixas, public.v_minhas_vendas,
  public.v_vendas_dia, public.v_margem
to kiarys_app;

-- Tabelas de cadastro que o admin edita direto por CRUD simples (sem
-- regra de negócio pesada), via rota genérica da API, e não por RPC
-- dedicada: categorias, colecoes, fornecedores, clientes, taxas_pagamento,
-- configuracoes. RLS abaixo restringe por papel.
grant select, insert, update on kiarys.categorias, kiarys.colecoes, kiarys.fornecedores to kiarys_app;
grant select, insert, update on kiarys.clientes to kiarys_app; -- toda venda pode cadastrar cliente rápido
grant select on kiarys.taxas_pagamento to kiarys_app;
grant update on kiarys.taxas_pagamento to kiarys_app; -- restringido a admin via policy
grant select on kiarys.configuracoes to kiarys_app;
grant update on kiarys.configuracoes to kiarys_app; -- restringido a admin via policy

-- perfis: SEM senha_hash no grant — column-level GRANT, não linha. Ler
-- credencial pra comparar é trabalho só de kiarys.autenticar/trocar_senha
-- (SECURITY DEFINER, leem a tabela inteira como dono da função,
-- independente deste GRANT). Mesmo a API tendo acesso total ao Postgres
-- via kiarys_app, não sobra um SELECT * que devolva hash de senha sem
-- querer numa rota genérica de listagem de usuárias.
grant select (id, nome, email, papel, ativo, comissao_pct, limite_desconto_pct, criado_em) on kiarys.perfis to kiarys_app;
grant update (nome, papel, ativo, comissao_pct, limite_desconto_pct) on kiarys.perfis to kiarys_app; -- restringido a admin via policy

-- Leituras que a API faz direto (não passam por view) porque servem
-- telas de detalhe que a lista de views não cobre bem. produtos/variacoes
-- ficam de fora de propósito — só por view (ver nota mais abaixo).
grant select on kiarys.vendas, kiarys.venda_itens, kiarys.pagamentos to kiarys_app;
grant select on kiarys.movimentos_estoque, kiarys.entradas, kiarys.entrada_itens to kiarys_app;
grant select on kiarys.caixa_movimentos to kiarys_app;
grant select on kiarys.auditoria to kiarys_app; -- restringido a admin via policy

-- ── Policies ─────────────────────────────────────────────────────────────

-- perfis: cada um lê o próprio; admin lê e edita todos; ninguém além do
-- admin muda papel/ativo/comissão/limite (o UPDATE em si é liberado pela
-- policy, mas só a rota de admin da API chama isso).
create policy perfis_select on kiarys.perfis for select
  using (id = kiarys.uid() or kiarys.eh_admin());
create policy perfis_update_admin on kiarys.perfis for update
  using (kiarys.eh_admin());

-- categorias/colecoes/fornecedores: toda sessão autenticada lê (precisa
-- pro cadastro e pros filtros); só quem pode_cadastrar() escreve.
create policy categorias_select on kiarys.categorias for select using (true);
create policy categorias_write on kiarys.categorias for insert with check (kiarys.pode_cadastrar());
create policy categorias_update on kiarys.categorias for update using (kiarys.pode_cadastrar());

create policy colecoes_select on kiarys.colecoes for select using (true);
create policy colecoes_write on kiarys.colecoes for insert with check (kiarys.pode_cadastrar());
create policy colecoes_update on kiarys.colecoes for update using (kiarys.pode_cadastrar());

create policy fornecedores_select on kiarys.fornecedores for select using (true);
create policy fornecedores_write on kiarys.fornecedores for insert with check (kiarys.pode_cadastrar());
create policy fornecedores_update on kiarys.fornecedores for update using (kiarys.pode_cadastrar());

-- produtos/variacoes: SEM policy e sem grant de SELECT direto para
-- kiarys_app (nunca concedido — nem revogado precisa ser). custo_medio
-- mora em variacoes, e RLS filtra LINHA, não COLUNA — não dá pra confiar
-- em policy pra esconder uma coluna sensível numa tabela que também tem
-- colunas públicas. Toda leitura de estoque passa pelas views
-- column-safe v_estoque / v_estoque_admin (0013); toda escrita, pelas RPCs.

-- clientes: leitura/escrita livre pra sessão autenticada (toda vendedora
-- cadastra cliente rápido na hora da venda).
create policy clientes_select on kiarys.clientes for select using (true);
create policy clientes_write on kiarys.clientes for insert with check (true);
create policy clientes_update on kiarys.clientes for update using (true);

-- vendas / venda_itens / pagamentos: vendedora vê as próprias, gerente e
-- admin veem todas. Nenhuma policy de INSERT/UPDATE/DELETE — essas
-- tabelas só são escritas pelas RPCs (SECURITY DEFINER, que bypassa RLS
-- por ser dona da tabela + superuser — ver nota acima).
create policy vendas_select on kiarys.vendas for select
  using (vendedora_id = kiarys.uid() or kiarys.eh_gerente_ou_admin());
create policy venda_itens_select on kiarys.venda_itens for select
  using (exists (
    select 1 from kiarys.vendas v where v.id = venda_itens.venda_id
    and (v.vendedora_id = kiarys.uid() or kiarys.eh_gerente_ou_admin())
  ));
create policy pagamentos_select on kiarys.pagamentos for select
  using (exists (
    select 1 from kiarys.vendas v where v.id = pagamentos.venda_id
    and (v.vendedora_id = kiarys.uid() or kiarys.eh_gerente_ou_admin())
  ));

comment on policy vendas_select on kiarys.vendas is
  'Sem custo nesta tabela (fica em venda_itens.custo_unitario), então uma '
  'vendedora lendo vendas direto não vê margem — só o que ela mesma vendeu.';

-- movimentos_estoque: leitura restrita a gerente/admin (é onde custo
-- unitário aparece por movimento). A tela Estoque do Time usa v_estoque,
-- não esta tabela.
create policy movimentos_select on kiarys.movimentos_estoque for select
  using (kiarys.eh_gerente_ou_admin());

-- entradas/entrada_itens: só quem cadastra (mesma regra de produtos).
create policy entradas_select on kiarys.entradas for select using (kiarys.pode_cadastrar());
create policy entrada_itens_select on kiarys.entrada_itens for select using (kiarys.pode_cadastrar());

-- caixa_movimentos: toda sessão autenticada vê (sangria/suprimento não é
-- informação sensível de margem, e a vendedora precisa ver o histórico do
-- caixa único do dia).
create policy caixa_movimentos_select on kiarys.caixa_movimentos for select using (true);

-- auditoria: só admin.
create policy auditoria_select on kiarys.auditoria for select using (kiarys.eh_admin());

-- taxas_pagamento / configuracoes: leitura livre (a tela Vender precisa
-- calcular parcelas), escrita só admin.
create policy taxas_select on kiarys.taxas_pagamento for select using (true);
create policy taxas_update on kiarys.taxas_pagamento for update using (kiarys.eh_admin());
create policy config_select on kiarys.configuracoes for select using (true);
create policy config_update on kiarys.configuracoes for update using (kiarys.eh_admin());

-- ── EXECUTE nas RPCs ─────────────────────────────────────────────────────
grant execute on function
  kiarys.abrir_caixa(numeric),
  kiarys.movimentar_caixa(kiarys.tipo_caixa_movimento, numeric, text),
  kiarys.fechar_caixa(numeric),
  kiarys.registrar_venda(jsonb, jsonb, uuid, uuid, numeric),
  kiarys.cancelar_venda(uuid, text),
  kiarys.criar_produto_com_grade(text, text, uuid, uuid, uuid, numeric, text[], text[], text),
  kiarys.importar_produtos(jsonb),
  kiarys.registrar_entrada(uuid, jsonb, numeric, numeric, text),
  kiarys.ajustar_estoque(uuid, integer, text, kiarys.tipo_movimento),
  kiarys.alterar_precos(uuid, numeric, numeric, date),
  kiarys.autenticar(citext, text),
  kiarys.criar_usuaria(text, citext, text, kiarys.papel, numeric, numeric),
  kiarys.trocar_senha(text, text)
to kiarys_app;

comment on function kiarys.autenticar is
  'EXECUTE liberado pra kiarys_app porque é a própria API quem chama '
  'antes de haver sessão (app.uid ainda não setada) — não é uma porta '
  'aberta pro navegador, que nunca tem essa connection string.';

-- Funções de apoio que a API também chama direto para montar a resposta
-- (ex.: já mandar `pode_ver_custo: true/false` no perfil devolvido no login).
grant execute on function kiarys.pode_ver_custo(), kiarys.pode_cadastrar(), kiarys.eh_admin(), kiarys.eh_gerente_ou_admin()
to kiarys_app;

-- perfil_atual() e as internas (preco_efetivo, calcular_esperado_caixa,
-- dia_local, tz, uid) ficam SEM grant direto: são usadas de dentro das
-- RPCs/views (que rodam como o dono), e não precisam ser chamadas soltas.
