#!/usr/bin/env bash
# scripts/backup.sh
# Exporta o banco (schema kiarys + auth.users, sem incluir dados internos
# de infra do Supabase) para fora do Supabase — brief, seção 8: "Backup:
# exportação periódica (CSV/SQL) para fora do Supabase". Rodado toda
# segunda pelo workflow backup.yml, ou manualmente:
#
#   SUPABASE_DB_URL=postgresql://... bash scripts/backup.sh
#
set -euo pipefail

if [ -z "${SUPABASE_DB_URL:-}" ]; then
  echo "defina SUPABASE_DB_URL (Settings > Database > Connection string, modo 'Session')" >&2
  exit 1
fi

ARQUIVO="backup-$(date -u +%Y%m%d-%H%M%S).sql.gz"

pg_dump "$SUPABASE_DB_URL" \
  --schema=kiarys \
  --no-owner --no-privileges \
  | gzip > "$ARQUIVO"

echo "backup salvo em $ARQUIVO"
