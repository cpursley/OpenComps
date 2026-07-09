# OpenComps — Local Bring-up & Test Evaluation

**Date:** 2026-07-09
**Evaluator:** Chad Ruby (external, appraiser workflow)
**Commit:** `8be146e`-era `main` (fresh `--depth 1` clone)
**Environment:** WSL2 Ubuntu 24.04, Docker Desktop 28.4.0 / Compose v2.39.2

## TL;DR

Fired it up cleanly via the **Docker path** and ran the full pgTAP suite:

> **8 files, 259 tests, 0 failures — PASS.** Deterministic on re-run. Schema applies to a fresh database on every test run.

The schema is substantial and coherent. Only one piece of setup friction (a host port collision, already hinted at in `AGENTS.md`). Nothing blocking.

## What was run

Followed `AGENTS.md` → Docker path (chosen because the host lacked `pnpm`/`psql`/`pg_prove`; the Docker backend runs psql **and** `pg_prove` inside the container, so no host Postgres tooling is required — a nice property):

```bash
git clone --depth 1 https://github.com/cpursley/OpenComps.git
cd OpenComps
POSTGRES_PORT=5433 docker compose up -d --wait pg      # build + boot (see note 1)
POSTGRES_PORT=5433 OPENCOMPS_TEST_BACKEND=docker ./scripts/test_db.sh
```

The image built as specified: **PostgreSQL 18 + PostGIS 3.6.1 + pgTAP (source build) + pg_prove**. Container reached `healthy`.

## Test results

```
/tests/database/test_atlanta_records.sql ....... ok
/tests/database/test_comp_scenarios.sql ........ ok
/tests/database/test_comp_type_governance.sql .. ok
/tests/database/test_comps_for_property.sql .... ok
/tests/database/test_constraints.sql ........... ok
/tests/database/test_global_comps.sql .......... ok
/tests/database/test_proximity.sql ............. ok
/tests/database/test_schema.sql ................ ok
All tests successful.
Files=8, Tests=259
Result: PASS
```

| Test file | Planned tests | Focus |
|---|---:|---|
| `test_schema.sql` | 80 | table/column/index presence |
| `test_constraints.sql` | 57 | CHECK / FK / unique / SQLSTATE negatives |
| `test_atlanta_records.sql` | 38 | realistic end-to-end record fixtures |
| `test_comp_scenarios.sql` | 34 | comp selection scenarios |
| `test_comps_for_property.sql` | 15 | subject-anchored comp RPC |
| `test_comp_type_governance.sql` | 13 | JSONB `metrics` field-definition enforcement |
| `test_proximity.sql` | 12 | spatial nearest-first ordering |
| `test_global_comps.sql` | 10 | cross-jurisdiction comps |
| **Total** | **259** | |

- **Deterministic:** ran the suite twice, 259/259 both times.
- **Isolation confirmed:** each run drops/recreates `opencomps_test` and re-applies both migrations before testing — i.e. the fresh-DB apply that `AGENTS.md` lists as the PR gate is exercised on every run.

## Schema inventory (as built)

Measured against the migrated `opencomps_test` database:

| Object | Count |
|---|---:|
| Base tables | 42 |
| Views | 5 |
| Enum types | 21 |
| Authored functions | 6 |
| Indexes | 148 |
| CHECK constraints | 71 |
| Foreign keys | 82 |
| Unique constraints | 65 |
| Triggers (non-internal) | 3 |
| Extensions | citext 1.8, postgis 3.6.1, pg_trgm 1.6, btree_gist 1.8, plpgsql 1.0 |

Authored functions: `comps_for_property`, `nearby_sales`, `nearby_unit_rents` (the REST/MCP-facing spatial RPCs), plus `convert_area`, `resolve_search_anchor`, and the `validate_comp_event_metrics` trigger backing the JSONB `metrics` governance. (Raw `pg_proc` count is ~1072 — the rest is PostGIS.)

The model covers the full appraisal/comps surface: properties, parcels + lineage (split/merge/renumber), ownership periods & interests, transfers, assessments, tax bills, mortgages, sales, leases with escalations/concessions, unit rents, listings, valuations, and comp sets — each fact table carrying `source_record_id` / `verification_status` / `contributed_by_id` for provenance. This is exactly the normalized store that county-scraper tools feed into; from an appraiser's side the shape looks right.

## Findings / friction

1. **Host port 5432 collision (minor, setup).** `docker compose up --wait pg` hard-fails if `127.0.0.1:5432` is already bound (I had an unrelated `postgres-dev` container there). `AGENTS.md` notes the override exists, but two small improvements would help a first-timer:
   - The Docker **test** backend talks to the container purely via `docker compose exec` and never uses the published host port — so for a test-only bring-up the port publish is dead weight that can still block startup. Consider making the host-port publish opt-in, or defaulting `POSTGRES_PORT` to something less contended.
   - A one-liner in the README quick-start (`POSTGRES_PORT=5433 docker compose up …`) would save the confusion; right now the hint is mid-`AGENTS.md`.
2. **First build is slow (expected, worth a note).** The image source-compiles pgTAP and `cpanm`-installs the Perl TAP handler, so a cold build is several minutes. Fine for a dev image, but a note ("first build ~N min") or a prebuilt/published image would smooth onboarding.
3. **No blocking issues.** Migrations apply atomically, extensions initialize from `database/init`, healthcheck is honest, teardown is clean.

## Not exercised (out of scope for this pass)

- **tinbase / PGlite path** (`pnpm dev`) — host had no `pnpm`; only the Docker reference path was validated.
- **Data loaders** — `load_us_zips.sh` (SimpleMaps download) and `seed_dev.sh` were not run; the pgTAP suite is self-contained via `BEGIN/ROLLBACK` fixtures and needs neither.

## Verdict

Bring-up succeeded and the suite is green, deterministic, and genuinely comprehensive (259 assertions incl. SQLSTATE-level negative constraint tests and spatial ordering). The schema-first focus shows — constraints, provenance, and the JSONB-governance pattern are all tested, not just asserted in prose. For an appraiser's comps use case the data model reads as complete and well-normalized. Recommend only the two setup-ergonomics tweaks above (port publish + build-time note).
