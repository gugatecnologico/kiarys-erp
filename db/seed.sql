-- seed.sql — só para desenvolvimento local (`npm run db:seed`, ver
-- scripts/migrate.js). Roda como o dono do banco (bypassa RLS), então
-- grava direto nas tabelas em vez de passar pelas RPCs — mais simples e
-- mais rápido para popular dado de desenvolvimento.

set search_path = kiarys, public;

-- ── 3 usuárias de teste ──────────────────────────────────────────────────
-- Senha para as três: "teste123" (só ambiente local — nunca use essa
-- senha em produção; o primeiro admin real é criado como no README).
insert into kiarys.perfis (id, nome, email, senha_hash, papel, ativo, limite_desconto_pct, comissao_pct)
values
  ('00000000-0000-0000-0000-000000000001', 'Admin Dev', 'admin@kiarys.dev', crypt('teste123', gen_salt('bf')), 'admin', true, null, 0),
  ('00000000-0000-0000-0000-000000000002', 'Gerente Dev', 'gerente@kiarys.dev', crypt('teste123', gen_salt('bf')), 'gerente', true, 15, 0),
  ('00000000-0000-0000-0000-000000000003', 'Vendedora Dev', 'vendedora@kiarys.dev', crypt('teste123', gen_salt('bf')), 'vendedora', true, 10, 3)
on conflict (id) do nothing;

-- ── Catálogo ─────────────────────────────────────────────────────────────
insert into kiarys.categorias (nome) values ('Vestidos'), ('Blusas'), ('Calças'), ('Saias'), ('Acessórios');
insert into kiarys.colecoes (nome, estacao, ano) values ('Verão 26', 'Verão', 2026);
insert into kiarys.fornecedores (nome, whatsapp) values ('Confecção Nordeste Ltda', '5588999990000');

do $$
declare
  v_cat_vestido uuid; v_cat_blusa uuid; v_col uuid; v_forn uuid;
  v_produtos text[] := array['Vestido Midi Linho', 'Vestido Curto Floral', 'Blusa Cropped', 'Blusa Manga Longa', 'Saia Jeans'];
  v_nome text;
  v_ref text;
  v_idx int := 0;
  v_produto_id uuid;
  v_variacao_id uuid;
  v_tamanho text;
  v_cor text;
begin
  select id into v_cat_vestido from kiarys.categorias where nome = 'Vestidos';
  select id into v_cat_blusa from kiarys.categorias where nome = 'Blusas';
  select id into v_col from kiarys.colecoes where nome = 'Verão 26';
  select id into v_forn from kiarys.fornecedores limit 1;

  foreach v_nome in array v_produtos loop
    v_idx := v_idx + 1;
    v_ref := 'REF' || lpad(v_idx::text, 4, '0');

    insert into kiarys.produtos (referencia, nome, categoria_id, colecao_id, fornecedor_id)
    values (v_ref, v_nome, coalesce(v_cat_vestido, v_cat_blusa), v_col, v_forn)
    returning id into v_produto_id;

    foreach v_tamanho in array array['P', 'M', 'G', 'GG'] loop
      foreach v_cor in array array['Preto', 'Off White'] loop
        insert into kiarys.variacoes (produto_id, tamanho, cor, preco_venda, custo_medio, estoque_minimo)
        values (v_produto_id, v_tamanho, v_cor, 129.90 + v_idx * 10, 45.00 + v_idx * 3, 2)
        returning id into v_variacao_id;

        insert into kiarys.movimentos_estoque (variacao_id, tipo, quantidade, custo_unitario, ref_tipo, motivo, usuario_id)
        values (v_variacao_id, 'ENTRADA', 8, 45.00 + v_idx * 3, 'seed', 'carga inicial de desenvolvimento', '00000000-0000-0000-0000-000000000001');
      end loop;
    end loop;
  end loop;
end $$;

-- Um cliente de teste.
insert into kiarys.clientes (nome, whatsapp, aceita_marketing)
values ('Maria de Teste', '(88) 99999-1234', true);

-- Caixa aberto de dev, para já poder testar venda na hora. Não dá pra
-- chamar a RPC abrir_caixa() aqui — ela exige kiarys.uid() (perfil_atual()),
-- e o seed roda sem sessão — então insere direto, como a RPC faria.
insert into kiarys.caixas (usuario_abertura, valor_inicial)
values ('00000000-0000-0000-0000-000000000001', 200.00);
