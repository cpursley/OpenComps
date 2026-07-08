#!/usr/bin/env bash
# Seed the OpenComps database with realistic Atlanta-metro dev data.
#
# Deterministic: reseeding a fresh database always produces identical data.
# Requires the schema applied and us_zips loaded (counties are resolved
# through the ZIP reference table). Refuses to run twice.
#
# Usage:
#   ./scripts/seed_dev.sh
#   ./scripts/seed_dev.sh "postgres://postgres:postgres@localhost:5432/opencomps"
#   DATABASE_URL=postgres://... ./scripts/seed_dev.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DB="${1:-${DATABASE_URL:-postgres://${POSTGRES_USER:-postgres}:${POSTGRES_PASSWORD:-postgres}@${POSTGRES_HOST:-localhost}:${POSTGRES_PORT:-5432}/${POSTGRES_DB:-opencomps}}}"

cd "$ROOT_DIR"   # dev_seed.sql \copy path is repo-relative

echo "Seeding dev data..."
psql "$DB" -v ON_ERROR_STOP=1 -f database/seeds/dev_seed.sql
