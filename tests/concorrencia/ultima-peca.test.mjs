// ultima-peca.test.mjs
//
// Critério de aceite (brief, seção 10):
// "Duas vendedoras vendendo a última unidade ao mesmo tempo: uma conclui,
// a outra recebe 'sem estoque'."
//
// pgTAP roda tudo dentro de UMA transação — não simula duas conexões
// concorrentes de verdade. Este script abre 2 conexões reais ao Postgres
// local (via `supabase start`) e dispara as duas vendas da mesma peça
// literalmente ao mesmo tempo (Promise.all), sem await entre elas.
//
// Uso: node tests/concorrencia/ultima-peca.test.mjs
// Espera um `supabase start` rodando (porta 54322 por padrão).

import pg from 'pg';

const DB_URL = process.env.SUPABASE_DB_URL ?? 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';

const ADMIN_ID = '11111111-1111-1111-1111-111111111111';
const VENDEDORA_A_ID = '33333333-3333-3333-3333-333333333333';
const VENDEDORA_B_ID = '44444444-4444-4444-4444-444444444444';

async function conectarComo(usuarioId) {
  const client = new pg.Client(DB_URL);
  await client.connect();
  await client.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ sub: usuarioId })]);
  await client.query(`set role authenticated`);
  return client;
}

async function main() {
  const admin = new pg.Client(DB_URL);
  await admin.connect();

  console.log('→ preparando fixture: 1 variação com saldo = 1...');
  await admin.query('begin');
  // Fixture roda com o role de conexão (postgres/service_role — bypassa
  // RLS), não como `authenticated`: o teste de concorrência é sobre a
  // trava de estoque em registrar_venda, não sobre GRANT/RLS (isso já
  // tem cobertura em supabase/tests/01_permissoes.sql).

  const produto = await admin.query(
    `insert into kiarys.produtos (referencia, nome) values ('CONC-TEST-' || floor(random()*1000000), 'Produto Concorrência') returning id`
  );
  const variacao = await admin.query(
    `insert into kiarys.variacoes (produto_id, tamanho, cor, preco_venda) values ($1, 'M', 'Preto', 100.00) returning id`,
    [produto.rows[0].id]
  );
  const variacaoId = variacao.rows[0].id;

  await admin.query(
    `insert into kiarys.movimentos_estoque (variacao_id, tipo, quantidade, usuario_id) values ($1, 'ENTRADA', 1, $2)`,
    [variacaoId, ADMIN_ID]
  );

  // Garante que exista um caixa aberto (reaproveita se já houver).
  const caixaAberto = await admin.query(`select id from kiarys.caixas where status = 'ABERTO' limit 1`);
  if (caixaAberto.rows.length === 0) {
    await admin.query(`insert into kiarys.caixas (usuario_abertura, valor_inicial) values ($1, 100.00)`, [ADMIN_ID]);
  }
  await admin.query('commit');

  console.log(`→ variação ${variacaoId} com saldo = 1, disparando 2 vendas concorrentes...`);

  const clienteA = await conectarComo(VENDEDORA_A_ID);
  const clienteB = await conectarComo(VENDEDORA_B_ID);

  const venderSql = `
    select kiarys.registrar_venda(
      jsonb_build_array(jsonb_build_object('variacao_id', $1::uuid, 'quantidade', 1)),
      jsonb_build_array(jsonb_build_object('forma', 'PIX', 'valor', 100.00)),
      gen_random_uuid()
    )
  `;

  const resultados = await Promise.allSettled([
    clienteA.query(venderSql, [variacaoId]),
    clienteB.query(venderSql, [variacaoId]),
  ]);

  await clienteA.end();
  await clienteB.end();

  const sucessos = resultados.filter((r) => r.status === 'fulfilled');
  const falhas = resultados.filter((r) => r.status === 'rejected');

  console.log(`→ sucessos: ${sucessos.length}, falhas: ${falhas.length}`);
  if (falhas.length > 0) {
    console.log(`  motivo da falha: ${falhas[0].reason.message}`);
  }

  const saldoFinal = await admin.query(`select qtd from kiarys.estoque_saldos where variacao_id = $1`, [variacaoId]);
  console.log(`→ saldo final: ${saldoFinal.rows[0].qtd}`);

  await admin.end();

  const ok =
    sucessos.length === 1 &&
    falhas.length === 1 &&
    /sem estoque/i.test(falhas[0].reason.message) &&
    saldoFinal.rows[0].qtd === 0;

  if (!ok) {
    console.error('✗ FALHOU — esperado exatamente 1 sucesso, 1 "sem estoque", saldo final 0');
    process.exit(1);
  }

  console.log('✓ OK — exatamente 1 venda passou, a outra recebeu "sem estoque", saldo final 0');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
