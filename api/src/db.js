// db.js
// Pool de conexão + o padrão único de acesso ao banco: toda consulta ou
// RPC roda dentro de UMA transação que primeiro seta `app.uid` (a GUC que
// kiarys.uid() lê — ver db/migrations/0001_base.sql) e só depois faz o
// trabalho de verdade. Isso é o que faz RLS enxergar "quem está pedindo",
// já que a API se conecta sempre com o mesmo role (kiarys_app).

import pg from 'pg';

const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
  max: 10,
});

pool.on('error', (err) => {
  // Erro numa conexão ociosa do pool — não derruba o processo, só loga
  // (emoji de prefixo pra achar fácil no log do Railway, convenção do GVA).
  console.error('🔴 erro no pool do Postgres:', err.message);
});

/**
 * Roda `fn(client)` dentro de uma transação com `app.uid` já setada pro
 * usuário autenticado (ou sem setar nada, se `uid` for null — chamadas
 * antes do login, como kiarys.autenticar).
 *
 * `fn` recebe um `pg.Client` já dentro da transação; NUNCA usar `pool.query`
 * direto numa rota autenticada, porque cada chamada do pool pode pegar uma
 * conexão física diferente, perdendo a GUC que acabou de ser setada.
 */
export async function comoUsuario(uid, fn) {
  const client = await pool.connect();
  try {
    await client.query('begin');
    if (uid) {
      await client.query(`select set_config('app.uid', $1, true)`, [uid]);
    }
    const resultado = await fn(client);
    await client.query('commit');
    return resultado;
  } catch (err) {
    await client.query('rollback').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

export default pool;
