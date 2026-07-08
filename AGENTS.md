# AGENTS.md

OpenComps is a PostgreSQL 17 + PostGIS schema for property records and
comparables. There is no application code yet, and never slop out nextjs: the deliverable is
`database/schema/opencomps.sql` (one file, single transaction), its pgTAP
suite, and the loader/seed scripts.

## Dev environment tips

- Boot the database with `docker compose up -d --wait pg` (Postgres 17,
  PostGIS, pgTAP, pg_prove included).
- Apply the schema to the `opencomps` dev database with
  `./scripts/migrate.sh`. It expects an empty database — there are no
  incremental migrations pre-release. To pick up schema edits, drop and
  recreate the dev database and re-apply, or `docker compose down -v` to
  reset everything.
- Load US ZIP reference data with `./scripts/load_us_zips.sh`, then seed
  deterministic dev data with `./scripts/seed_dev.sh` (requires us_zips;
  refuses to run twice).
- All scripts accept `POSTGRES_PORT`/`POSTGRES_HOST`/`POSTGRES_USER`/
  `POSTGRES_PASSWORD` env vars or a connection URL as `$1`.
- Connect with `psql postgres://postgres:postgres@localhost:5432/opencomps`.

## Testing instructions

- Run the full suite with `./scripts/test_db.sh`. It drops, recreates, and
  migrates a dedicated `opencomps_test` database every run — never prep the
  test database manually and never point tests at dev data.
- Tests live in `tests/pgtap/test_*.sql`. Each file wraps in
  `BEGIN; ... ROLLBACK;`, loads fixtures via `\ir fixtures/...`, and
  declares an exact `plan(N)` — update N when adding tests.
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
  `comp_types.field_definitions`.
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
  the README table count and layer table.

## PR instructions

- Run `./scripts/test_db.sh` and make sure the schema applies to a fresh
  database before committing.
- Open an issue describing the modeling problem before writing DDL.
- Keep dev seeding deterministic: derive every generated value from
  `md5(source_id || ':salt')` (see `database/seeds/dev_seed.sql`), never
  `random()` or `now()`.
- SimpleMaps ZIP data is free-tier: production use requires a link back to
  https://simplemaps.com/data/us-zips. Never commit the dataset itself.
