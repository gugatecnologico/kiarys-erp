#!/usr/bin/env node
// scripts/migrate.js
//
// Runner de migrations pra Postgres puro (Railway), substituindo o
// `supabase db push`. Idempotente: guarda o que já rodou numa tabela
// `public.schema_migrations` e só aplica o que falta, em ordem de nome
// de arquivo — por isso os arquivos em db/migrations/ são numerados
// (0001_, 0002_, ...).
//
// Uso:
//   DATABASE_URL=postgresql://... node scripts/migrate.js
//   DATABASE_URL=... node scripts/migrate.js --seed   # também roda db/seed.sql (só dev)
//
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import pg from 'pg';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const MIGRATIONS_DIR = path.join(__dirname, '..', 'db', 'migrations');
const SEED_FILE = path.join(__dirname, '..', 'db', 'seed.sql');

const DATABASE_URL = process.env.DATABASE_URL;
if (!DATABASE_URL) {
  console.error('defina DATABASE_URL (a connection string do Postgres do Railway, ou local)');
  process.exit(1);
}

async function main() {
  const client = new pg.Client({ connectionString: DATABASE_URL });
  await client.connect();

  await client.query(`
    create table if not exists public.schema_migrations (
      filename    text primary key,
      applied_at  timestamptz not null default now()
    )
  `);

  const jaAplicadas = new Set(
    (await client.query('select filename from public.schema_migrations')).rows.map((r) => r.filename)
  );

  const arquivos = readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .sort(); // 0001_, 0002_, ... — ordem alfabética = ordem de execução

  let aplicadas = 0;
  for (const arquivo of arquivos) {
    if (jaAplicadas.has(arquivo)) continue;

    const sql = readFileSync(path.join(MIGRATIONS_DIR, arquivo), 'utf8');
    console.log(`→ aplicando ${arquivo}...`);

    await client.query('begin');
    try {
      await client.query(sql);
      await client.query('insert into public.schema_migrations (filename) values ($1)', [arquivo]);
      await client.query('commit');
      aplicadas++;
    } catch (err) {
      await client.query('rollback');
      console.error(`✗ falhou em ${arquivo}:`);
      console.error(err.message);
      await client.end();
      process.exit(1);
    }
  }

  console.log(aplicadas === 0 ? '→ nada novo pra aplicar (banco já está em dia)' : `✓ ${aplicadas} migration(s) aplicada(s)`);

  if (process.argv.includes('--seed')) {
    console.log('→ rodando db/seed.sql (dev)...');
    const seedSql = readFileSync(SEED_FILE, 'utf8');
    await client.query(seedSql);
    console.log('✓ seed aplicado');
  }

  await client.end();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
