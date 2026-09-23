#!/usr/bin/env bash
# scripts/backup.sh
# Exporta o schema kiarys (dados + credenciais de login, já que perfis
# guarda email/senha_hash — ver 0002) pra fora do Railway. Brief, seção 8:
# "Backup: exportação periódica (CSV/SQL) para fora do [banco]". Rodado
# toda segunda pelo workflow backup.yml, ou manualmente:
#
#   DATABASE_URL=postgresql://... bash scripts/backup.sh
#
set -euo pipefail

if [ -z "${DATABASE_URL:-}" ]; then
  echo "defina DATABASE_URL (a connection string do Postgres no Railway — aba Connect do serviço)" >&2
  exit 1
fi

ARQUIVO="backup-$(date -u +%Y%m%d-%H%M%S).sql.gz"

pg_dump "$DATABASE_URL" \
  --schema=kiarys \
  --no-owner --no-privileges \
  | gzip > "$ARQUIVO"

echo "backup salvo em $ARQUIVO"
