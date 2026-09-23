#!/usr/bin/env node
// scripts/set-app-password.js
// One-off: troca a senha do role kiarys_app (a migration 0014 cria com um
// placeholder). Lê a senha nova de NEW_APP_PASSWORD — nunca a devolve, só
// confirma que trocou. Rodar uma vez por ambiente, com DATABASE_URL do
// dono do banco (não do kiarys_app).
import pg from 'pg';

const { DATABASE_URL, NEW_APP_PASSWORD } = process.env;
if (!DATABASE_URL || !NEW_APP_PASSWORD) {
  console.error('defina DATABASE_URL e NEW_APP_PASSWORD');
  process.exit(1);
}

const client = new pg.Client({ connectionString: DATABASE_URL });
await client.connect();
await client.query('alter role kiarys_app password $1', [NEW_APP_PASSWORD]);
await client.end();
console.log('✓ senha do kiarys_app trocada');
