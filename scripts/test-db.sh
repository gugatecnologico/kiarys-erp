#!/usr/bin/env bash
# scripts/test-db.sh
# Roda os testes pgTAP (db/tests/*.sql) contra um Postgres descartável —
# substitui `supabase test db`, que não existe fora do Supabase.
#
# Requer: pgTAP instalado no Postgres alvo (extensão `pgtap`) e `pg_prove`
# (pacote `libtap-parser-sourcehandler-pgtap-perl` no Debian/Ubuntu, junto
# com `postgresql-XX-pgtap`). No CI isso é instalado via apt — ver
# .github/workflows/ci.yml.
#
# Uso: TEST_DATABASE_URL=postgresql://... bash scripts/test-db.sh
# Sem TEST_DATABASE_URL, assume um Postgres local via socket/peer auth
# (como o do container de CI) e cria/derruba o banco `kiarys_test`.
set -euo pipefail
cd "$(dirname "$0")/.."

DB_NAME="${TEST_DB_NAME:-kiarys_test}"
PSQL="${PSQL:-psql}"

echo "→ recriando banco de teste ($DB_NAME)..."
$PSQL -c "drop database if exists $DB_NAME;"
$PSQL -c "create database $DB_NAME;"
$PSQL -d "$DB_NAME" -c "create extension if not exists pgtap;"

echo "→ aplicando migrations..."
for f in db/migrations/*.sql; do
  $PSQL -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$f" > /dev/null
done

echo "→ carregando fixtures (00_setup.sql, fora do pg_prove — não é um TAP test em si)..."
$PSQL -d "$DB_NAME" -v ON_ERROR_STOP=1 -f db/tests/00_setup.sql > /dev/null

echo "→ rodando pgTAP (db/tests/, exceto 00_setup.sql)..."
pg_prove --dbname "$DB_NAME" --ext .sql db/tests/0[1-9]*.sql

echo "→ limpando banco de teste..."
$PSQL -c "drop database if exists $DB_NAME;"
