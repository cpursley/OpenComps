#!/usr/bin/env bash
# Apply the OpenComps schema to an empty database.
#
# Usage:
#   ./scripts/migrate.sh
#   ./scripts/migrate.sh "postgres://postgres:postgres@localhost:5432/opencomps"
#   DATABASE_URL=postgres://... ./scripts/migrate.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DB="${1:-${DATABASE_URL:-postgres://${POSTGRES_USER:-postgres}:${POSTGRES_PASSWORD:-postgres}@${POSTGRES_HOST:-localhost}:${POSTGRES_PORT:-5432}/${POSTGRES_DB:-opencomps}}}"

echo "Applying OpenComps schema..."
psql "$DB" -v ON_ERROR_STOP=1 -f "$ROOT_DIR/database/schema/opencomps.sql"
echo "Schema applied."
