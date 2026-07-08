#!/usr/bin/env bash
# Run the pgTAP suite against a dedicated test database (opencomps_test).
#
# The test database is dropped, recreated, and migrated from
# database/schema/opencomps.sql on every run, so tests always exercise the
# current schema and never touch dev data.
#
# If the Docker database is running, this uses the container's pg_prove. If
# not, it falls back to running test SQL files with local psql.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DB="${POSTGRES_TEST_DB:-opencomps_test}"
POSTGRES_USER_NAME="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD_VALUE="${POSTGRES_PASSWORD:-postgres}"
POSTGRES_HOST_NAME="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT_NUM="${POSTGRES_PORT:-5432}"

if command -v docker >/dev/null 2>&1 && [ -n "$(docker compose ps --status running -q pg 2>/dev/null)" ]; then
  echo "Preparing test database ${TEST_DB}..."
  docker compose exec -T pg psql -U "$POSTGRES_USER_NAME" -d postgres -v ON_ERROR_STOP=1 -q \
    -c "DROP DATABASE IF EXISTS ${TEST_DB};" -c "CREATE DATABASE ${TEST_DB};"
  docker compose exec -T pg psql -U "$POSTGRES_USER_NAME" -d "$TEST_DB" -v ON_ERROR_STOP=1 -q -f - \
    < "$ROOT_DIR/database/schema/opencomps.sql"

  echo "Running pgTAP tests with container pg_prove..."
  docker compose exec -T \
    -e TEST_DB="$TEST_DB" \
    -e POSTGRES_USER="$POSTGRES_USER_NAME" \
    -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD_VALUE" \
    pg sh -lc 'PGPASSWORD="$POSTGRES_PASSWORD" pg_prove -U "$POSTGRES_USER" -d "$TEST_DB" /tests/pgtap/test_*.sql'
else
  ADMIN_DB="postgres://${POSTGRES_USER_NAME}:${POSTGRES_PASSWORD_VALUE}@${POSTGRES_HOST_NAME}:${POSTGRES_PORT_NUM}/postgres"
  DB="postgres://${POSTGRES_USER_NAME}:${POSTGRES_PASSWORD_VALUE}@${POSTGRES_HOST_NAME}:${POSTGRES_PORT_NUM}/${TEST_DB}"

  echo "Preparing test database ${TEST_DB}..."
  psql "$ADMIN_DB" -v ON_ERROR_STOP=1 -q \
    -c "DROP DATABASE IF EXISTS ${TEST_DB};" -c "CREATE DATABASE ${TEST_DB};"
  psql "$DB" -v ON_ERROR_STOP=1 -q -f "$ROOT_DIR/database/schema/opencomps.sql"

  echo "Running pgTAP tests with local psql..."
  for test_file in "$ROOT_DIR"/tests/pgtap/test_*.sql; do
    echo ""
    echo "Running: $test_file"
    psql "$DB" -v ON_ERROR_STOP=1 -f "$test_file"
  done
fi
