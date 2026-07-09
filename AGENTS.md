# AGENTS.md

OpenComps is a PostgreSQL + PostGIS schema (PostgreSQL 17+; dev runs 18) for property records and
comparables. There is no application code yet, and never slop out nextjs: the deliverable is
the migrations in `supabase/migrations/` (each applied atomically in
timestamp order — tinbase wraps each in a transaction, the psql paths use
`-1`; never add BEGIN/COMMIT to migration files), their pgTAP suite, and
the loader/seed scripts.

## Dev environment tips

Two dev paths. Default is tinbase + PGlite (no Docker); Docker remains the
full-fidelity reference (both run Postgres 18 + PostGIS 3.6; PGlite is
an experimental WASM build).

| Port | What |
|---|---|
| 54321 | tinbase HTTP: REST `/rest/v1/`, Studio `/_/` (`TINBASE_PORT`) |
| 55432 | tinbase Postgres wire for psql (`PGLITE_PORT`) |
| 55433 | throwaway pgTAP test server (`PGLITE_TEST_PORT`) |
| 5432 | Docker Postgres (`POSTGRES_PORT`; often overridden to 55432 — stop one stack before running the other on a shared port) |

- **tinbase path:** `pnpm install`, then `pnpm dev`. Boot applies any
  untracked `supabase/migrations/*.sql` (recorded in
  `supabase_migrations.schema_migrations`, skipped thereafter), persists in
  `.tinbase/pglite/`; `--memory` for ephemeral; schema edits require
  `rm -rf .tinbase` and restart, then re-run seeds. Then `pnpm load-zips`,
  `pnpm seed`, `pnpm test`. Connect with
  `psql postgres://postgres@127.0.0.1:55432/postgres`.
- **Studio:** http://127.0.0.1:54321/_/ — sign in with the full ~200-char
  `service_role` key from the `pnpm dev` startup output (partial paste →
  "Invalid API key"; pipe through `pbcopy` rather than hand-selecting).
- **Stable keys / MCP:** `cp .env.example .env`, set `TINBASE_JWT_SECRET`
  (else keys rotate per restart) and `SUPABASE_SERVICE_ROLE_KEY` (from the
  `pnpm dev` output). `.mcp.json` runs `@supabase/mcp-server-postgrest`
  against the REST API using that key.
- **Docker path:** `docker compose up -d --wait pg`, then
  `./scripts/migrate.sh` (applies every migration in timestamp order; it
  expects an empty database and does not track what has been applied). To
  pick up schema edits, drop and recreate the dev database and re-apply,
  or `docker compose down -v` to reset everything. Connect with
  `psql postgres://postgres:postgres@localhost:5432/opencomps`. If host
  port 5432 is already bound, `up` fails immediately — set
  `POSTGRES_PORT=<free port>` on the compose command and every script
  call that follows.
- Load US ZIP reference data with `./scripts/load_us_zips.sh`, then seed
  deterministic dev data with `./scripts/seed_dev.sh` (requires us_zips;
  refuses to run twice).
- All scripts accept `POSTGRES_PORT`/`POSTGRES_HOST`/`POSTGRES_USER`/
  `POSTGRES_PASSWORD` env vars or a connection URL as `$1` (the `pnpm`
  wrappers pass the tinbase URL).
- **Never use `\copy`/COPY FROM STDIN in seeds or loaders** — it
  desynchronizes the pglite-socket protocol. Bulk loads are generated
  multi-row INSERTs (see `scripts/lib/csv_to_inserts.mjs`).
- PGlite is single-writer and has no `CREATE DATABASE`; run psql sessions
  against it one at a time, sequentially.

## Testing instructions

- Run the full suite with `./scripts/test_db.sh`. Backend auto-detected
  (running Docker service → PGlite → local Postgres); force with
  `OPENCOMPS_TEST_BACKEND=docker|pglite|local`. Docker/local drop,
  recreate, and migrate a dedicated `opencomps_test` database every run;
  the pglite backend boots a fresh in-memory instance instead (PGlite has
  no `CREATE DATABASE`) — same isolation guarantee. Never prep the test
  database manually and never point tests at dev data.
- Tests live in `supabase/tests/database/*.sql` (the Supabase CLI's
  directory convention; `supabase test db` works against Docker/hosted
  Supabase but NOT against the PGlite socket — the CLI's connection
  handling wedges pglite-socket. Use `./scripts/test_db.sh`). Each file wraps in
  `BEGIN; ... ROLLBACK;`, loads fixtures via `\ir fixtures/...`, and
  declares an exact `plan(N)` — update N when adding tests.
- Fixtures use the `.psql` extension (`supabase/tests/database/fixtures/`),
  NOT `.sql`: `supabase test db` runs pg_prove recursively over every
  `.sql`/`.pg` file under `supabase/tests`, and a fixture executed as a
  test would fail. Keep it `.psql` so only real test files are collected.
- Write the failing test first and watch it fail for the right reason
  (`throws_ok` reporting "no exception" means the constraint is missing);
  then change the schema and watch it pass.
- Assert errors by SQLSTATE (`'23505'`, `'23514'`, `'23P01'`, `'22P02'`),
  never by message text.
- Tests must pass with or without the full SimpleMaps dataset loaded: scope
  `us_zips` queries to fixture ZIPs and use synthetic dataset names in
  `reference_dataset_loads` tests.
- Give spatial assertions safe margins (kilometers, not meters) so centroid
  updates don't flip results.

## Schema rules

- UUID PKs via `gen_random_uuid()`; natural keys are unique indexes, never
  PKs. Fixtures use fixed, prefix-grouped UUIDs.
- Typed columns for anything professionals filter or sort on; asset-class
  long tail goes in `metrics` JSONB governed by
  `comp_types.field_definitions` (per event table, per field
  `{type, unit, label, required}`) — trigger-enforced on
  `pending_review`/`verified` rows via SQLSTATE `23514`, lax on
  `unverified`.
- Canonical `comp_types`/`property_types` ship in the migration with fixed
  UUIDs; reference them by code, never re-create them. New asset classes
  are new rows declaring their own `field_definitions`.
- Spatial search is exposed to REST/MCP clients as RPC functions
  (`nearby_sales`, `nearby_unit_rents`: `lat`/`long` or `zip` + `radius_m`;
  `comps_for_property`: subject-anchored with as_of/sale-type/size/vintage
  filters; nearest-first, `22023` on bad arguments) — extend these rather
  than expecting PostGIS in PostgREST filters.
- Duplicate prevention: `find_property(apn, zip, address, lat, long)`
  is the waterfall existence check (parcel → address trigram → location;
  `matched_by` reports the rung) — call it before creating identity rows;
  time-series facts append to the matched property.
- Multi-row writes for object-only REST clients go through the
  `bulk_insert(target, rows)` RPC (payload-keyed column list so absent
  columns keep DEFAULTs; vocabulary/reference tables refused, `22023`) —
  clients that can send a top-level JSON array body may also POST it to
  the table path directly.
- Enums for closed sets (statuses, kinds); rows for open sets (comp types,
  property types, taxonomies). Comment open-vocabulary TEXT columns with
  example values.
- Every fact table carries `source_record_id`, `verification_status`, and
  (where user-entered) `contributed_by_id`, all indexed.
- Temporal pairs `(started_on, ended_on)` are `[start, end)` — `ended_on`
  exclusive. Constraints protect only the `verified` timeline; raw imports
  may conflict.
- Money: per-row `currency` CHAR(3) ISO 4217, amounts stored as quoted,
  never converted. Measurements: per-row `unit_system`, areas in base units
  (sq ft / m²); acres and hectares are app-layer display conversions.
- Store identifiers raw exactly as issued, with normalized copies alongside
  for matching, never instead.
- Add NULL-tolerant CHECKs (`col IS NULL OR col >= 0`) for bounds and date
  ordering; name multi-column constraints (`<table>_nonnegative_amounts`).
- Use partial indexes for hot screens (`WHERE status = 'active'`), GIST for
  geography/ranges, GIN for JSONB/trigram/arrays.
- When adding a table: add `has_table` (plus column/index checks) to
  `test_schema.sql`, a scenario test, negative constraint tests, and update
  the README layer table.

## PR instructions

- Run `./scripts/test_db.sh` and make sure the schema applies to a fresh
  database before committing.
- Open an issue describing the modeling problem before writing DDL.
- Keep dev seeding deterministic: derive every generated value from
  `md5(source_id || ':salt')` (see `supabase/seed.sql`), never
  `random()` or `now()`.
- SimpleMaps ZIP data is free-tier: production use requires a link back to
  https://simplemaps.com/data/us-zips. Never commit the dataset itself.
