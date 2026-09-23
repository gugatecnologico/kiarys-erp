#!/usr/bin/env node
// scripts/create-admin.js
// One-off: cria o primeiro admin direto na tabela (bypassa criar_usuaria,
// que exige um admin já existente pra chamar — ver README "Primeiro
// admin"). Precisa rodar com DATABASE_URL do dono do banco, não do
// kiarys_app (que não tem INSERT em kiarys.perfis, só as RPCs).
import pg from 'pg';

const { DATABASE_URL, ADMIN_NOME, ADMIN_EMAIL, ADMIN_SENHA } = process.env;
if (!DATABASE_URL || !ADMIN_NOME || !ADMIN_EMAIL || !ADMIN_SENHA) {
  console.error('defina DATABASE_URL, ADMIN_NOME, ADMIN_EMAIL, ADMIN_SENHA');
  process.exit(1);
}

const client = new pg.Client({ connectionString: DATABASE_URL });
await client.connect();
await client.query(
  `insert into kiarys.perfis (nome, email, senha_hash, papel)
   values ($1, $2, crypt($3, gen_salt('bf')), 'admin')
   on conflict (email) do nothing`,
  [ADMIN_NOME, ADMIN_EMAIL, ADMIN_SENHA]
);
await client.end();
console.log(`✓ admin ${ADMIN_EMAIL} criado (ou já existia)`);
