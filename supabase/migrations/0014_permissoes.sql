-- 0014_permissoes.sql
-- RLS default-deny em toda tabela de `kiarys` + revogação de todo GRANT
-- direto, e liberação explícita só do que public/authenticated precisam:
-- SELECT nas views (0013) e EXECUTE nas RPCs. Ver arquitetura em 0001.
--
-- IMPORTANTE (config de projeto, não SQL — documentado no README):
-- `kiarys` precisa estar em Settings > API > Exposed schemas, senão as
-- RPCs não resolvem via PostgREST.

set search_path = kiarys, public;

-- ── RLS default-deny em toda tabela de kiarys ───────────────────────────
-- Ligar RLS sem nenhuma policy = toda linha invisível para anon/authenticated
-- por padrão, mesmo que um GRANT futuro seja adicionado por engano. Isso é
-- a segunda camada de defesa: a primeira (e a que efetivamente barra hoje)
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

-- FORCE também vale para o dono da tabela — mas o papel `postgres` do
-- Supabase tem o atributo BYPASSRLS, que tem prioridade sobre FORCE e
-- ignora RLS por completo. É por isso que as RPCs (SECURITY DEFINER,
-- donas = postgres) continuam escrevendo em vendas/movimentos_estoque/etc.
-- sem precisar de policy de INSERT nelas: quem faz o INSERT de fato é o
-- dono da função, nunca o `authenticated` direto. Only ligando FORCE
-- não teria efeito nenhum sem isso — deixado explícito para quem for
-- portar este banco pra fora do Supabase (lá, garanta BYPASSRLS na role
-- dona das funções, ou crie policies de INSERT dedicadas).
-- ── Revoga tudo, dos dois papéis do Supabase ────────────────────────────
revoke all on all tables in schema kiarys from anon, authenticated;
revoke all on all sequences in schema kiarys from anon, authenticated;
revoke all on all functions in schema kiarys from anon, authenticated;
revoke all on schema kiarys from anon;

-- `authenticated` precisa de USAGE no schema só para o PostgREST resolver
-- os nomes de função das RPCs — não dá nenhum acesso a tabela.
grant usage on schema kiarys to authenticated;

-- anon não faz nada neste sistema (login é sempre por conta própria,
-- seção 5: "Cada pessoa tem o seu, nunca compartilhado"). Fora do login,
-- zero acesso.
revoke all on schema public from anon;

-- ── Views: SELECT só para authenticated ─────────────────────────────────
grant usage on schema public to authenticated;
grant select on
  public.v_estoque, public.v_estoque_admin, public.v_produtos_busca,
  public.v_caixa_aberto, public.v_caixas, public.v_minhas_vendas,
  public.v_vendas_dia, public.v_margem
to authenticated;

-- Tabelas de cadastro que o admin edita direto por CRUD simples (sem regra
-- de negócio pesada) via REST padrão do Supabase, e não por RPC dedicada:
-- categorias, colecoes, fornecedores, clientes, taxas_pagamento,
-- configuracoes. RLS abaixo restringe por papel.
grant select, insert, update on kiarys.categorias, kiarys.colecoes, kiarys.fornecedores to authenticated;
grant select, insert, update on kiarys.clientes to authenticated; -- toda venda pode cadastrar cliente rápido
grant select on kiarys.taxas_pagamento to authenticated;
grant update on kiarys.taxas_pagamento to authenticated; -- restringido a admin via policy
grant select on kiarys.configuracoes to authenticated;
grant update on kiarys.configuracoes to authenticated; -- restringido a admin via policy
grant select on kiarys.perfis to authenticated; -- restringido por policy (linha 1: a própria; admin: todas)
grant update on kiarys.perfis to authenticated; -- restringido a admin via policy (papel/comissão/limite/ativo)

-- Leituras que o front faz direto (não passam por view) porque servem
-- telas de detalhe que a lista de views não cobre bem. produtos/variacoes
-- ficam de fora de propósito — só por view (ver nota mais abaixo).
grant select on kiarys.vendas, kiarys.venda_itens, kiarys.pagamentos to authenticated;
grant select on kiarys.movimentos_estoque, kiarys.entradas, kiarys.entrada_itens to authenticated;
grant select on kiarys.caixa_movimentos to authenticated;
grant select on kiarys.auditoria to authenticated; -- restringido a admin via policy

-- ── Policies ─────────────────────────────────────────────────────────────

-- perfis: cada um lê o próprio; admin lê e edita todos; ninguém além do
-- admin muda papel/ativo/comissão/limite (o UPDATE em si é liberado pela
-- policy, mas a tela do Time nunca chama isso — é só o admin.js que usa).
create policy perfis_select on kiarys.perfis for select
  using (id = auth.uid() or kiarys.eh_admin());
create policy perfis_update_admin on kiarys.perfis for update
  using (kiarys.eh_admin());

-- categorias/colecoes/fornecedores: todo autenticado lê (precisa pro
-- cadastro e pros filtros); só quem pode_cadastrar() escreve.
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
-- authenticated (revogado logo abaixo, junto do grant genérico da seção
-- de tabelas). custo_medio mora em variacoes, e RLS filtra LINHA, não
-- COLUNA — não dá pra confiar em policy para esconder uma coluna sensível
-- numa tabela que também tem colunas públicas. Toda leitura de estoque
-- passa pelas views column-safe v_estoque / v_estoque_admin (0013); toda
-- escrita, pelas RPCs. Ver revoke explícito mais abaixo.

-- clientes: leitura/escrita livre para autenticado (toda vendedora
-- cadastra cliente rápido na hora da venda).
create policy clientes_select on kiarys.clientes for select using (true);
create policy clientes_write on kiarys.clientes for insert with check (true);
create policy clientes_update on kiarys.clientes for update using (true);

-- vendas / venda_itens / pagamentos: vendedora vê as próprias, gerente e
-- admin veem todas. Nenhuma policy de INSERT/UPDATE/DELETE — essas
-- tabelas só são escritas pelas RPCs (SECURITY DEFINER, que bypassa RLS
-- por definição do dono ser superusuário/postgres — ver nota).
create policy vendas_select on kiarys.vendas for select
  using (vendedora_id = auth.uid() or kiarys.eh_gerente_ou_admin());
create policy venda_itens_select on kiarys.venda_itens for select
  using (exists (
    select 1 from kiarys.vendas v where v.id = venda_itens.venda_id
    and (v.vendedora_id = auth.uid() or kiarys.eh_gerente_ou_admin())
  ));
create policy pagamentos_select on kiarys.pagamentos for select
  using (exists (
    select 1 from kiarys.vendas v where v.id = pagamentos.venda_id
    and (v.vendedora_id = auth.uid() or kiarys.eh_gerente_ou_admin())
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

-- caixa_movimentos: todo autenticado vê (sangria/suprimento não é
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


-- ── EXECUTE nas RPCs (as ~15 portas de escrita) ─────────────────────────
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
  kiarys.alterar_precos(uuid, numeric, numeric, date)
to authenticated;

-- Funções de apoio que o frontend também chama direto para montar a UI
-- (ex.: esconder o botão de custo antes mesmo de a query da view voltar).
grant execute on function kiarys.pode_ver_custo(), kiarys.pode_cadastrar(), kiarys.eh_admin(), kiarys.eh_gerente_ou_admin()
to authenticated;

-- perfil_atual() e as internas (preco_efetivo, calcular_esperado_caixa,
-- dia_local, tz, usuario_atual_ou_null) ficam SEM grant direto: são usadas
-- de dentro das RPCs/views (que rodam como o dono, postgres), e não
-- precisam ser chamadas soltas pelo cliente.
