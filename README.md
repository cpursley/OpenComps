# OpenComps

> An open-source database for property records and comparables:
parcels, ownership, assessments, taxes, debt, and market comps (sales,
leases, listings, unit rents).

## Why

Your property data lives in legacy desktop software, in vendors' web apps,
and in home-grown databases and spreadsheets held together by whoever set
them up years ago. The data is yours: your comps, your research, your
workfiles, your market knowledge. But getting it in or out means logging
into someone else's UI and clicking through screens, and most vendors won't
easily let you or your tools talk to their database directly.

That matters more now than ever. In the age of AI, a vendor app or
spreadsheet is no longer where the work has to happen. AI agents can pull
data out of source
documents, look up records, and file everything into a database without a
human clicking anything. Human verification stays; manual data entry
doesn't. But agents need a database they're allowed to touch, structured the
way real estate actually works. If your software won't let an agent read and
write your own data, ask why a vendor is holding your data hostage.

OpenComps is that database, in the open. A [PostgreSQL](https://postgresisenough.dev) schema you run
yourself, that you and your agents own outright:

- **One property, one record, forever.** Parcel numbers get split, merged,
  and renumbered by counties. Vendors each have their own ID. OpenComps
  keeps a permanent internal record for every property and treats all those
  numbers as labels attached to it.
- **Public records the way they really work.** Counties, parcels,
  assessments (including corrections and appeals), and tax bills. Deed
  transfers are kept apart from market sales, so a quitclaim between family
  members never shows up as a comp.
- **Ownership history built in.** Who owned it, when, and in what
  percentages. "Who owned this in 2021?" and "everything this LLC owns" are
  simple, fast lookups.
- **Comps you can actually filter.** Cap rate, NOI, price per square foot,
  net effective rent, free rent, TI allowance, and deal type are real,
  searchable fields, because those are what you screen on.
- **A paper trail for every fact.** Every number traces back to where it
  came from and whether it's been verified, down to each individual phone
  number, email, and mailing address.
- **Works anywhere.** Addresses, parcel systems, and
  taxing authorities are modeled for any country: a Georgia APN, an Ontario
  PIN, and a German Flurstück all fit. Measurements work in both systems,
  so a comp can be 18,500 square feet at $42.50 per square foot or 850
  square meters at €312 per square meter, side by side in the same database.

## Who it's for

**Appraisers.** Sale, lease, and rent comps with the fields the forms
demand: UAD condition/quality ratings, 1007-style monthly rent comps, and
physical details. Comp sets record what was selected, by whom,
for which subject and effective date.

**Investors and analysts.** Ownership resolution across LLCs, portfolio
queries, assessment and tax history, and debt records with maturity dates.
The "CMBS loans maturing in 18 months" screen is a partial index, not a
data-vendor invoice.

**Brokers.** Lease comps with full deal terms (NER, concessions, transaction
types, brokers on both sides), listing history, owner contact points with
per-item verification, and prospecting surfaces built on public records.

**Lenders and underwriters.** Recorded mortgages with lien position and
lifecycle status, income and expense statements, valuations (appraisal, AVM,
BPO) with confidence ranges, and the transfer chain behind every sale.

**Data teams and researchers.** A stable target for county/assessor ETL with
per-record-kind versioning, change propagation paths (indexed
`source_record_id` on every fact table), and reproducible verification
trails.

## What's inside

SQL migrations in `supabase/migrations/`, targeting PostgreSQL 17+ and
PostGIS 3.5+ (both bundled dev paths run PostgreSQL 18 + PostGIS 3.6).
The full inventory of tables, views, and RPCs is in
[docs/schema.md](docs/schema.md).

## Getting started

Three ways to run OpenComps, lightest first:

1. **tinbase + PGlite (default, no Docker)** — Node 22+, pnpm, and psql.
2. **Docker** — full-fidelity PostgreSQL 18 + PostGIS 3.6 with pgTAP and
   `pg_prove` baked in.
3. **Manual** — your own PostgreSQL 17+ with PostGIS 3.5+ (extensions used:
   `postgis`, `citext`, `pg_trgm`, `btree_gist`; plus `pgtap` for the test
   suite).

### Quick start: tinbase + PGlite (no Docker)

The default dev path runs the whole database in a single Node process on
[tinbase](https://www.tinbase.dev), a Supabase-compatible backend
over [PGlite](https://pglite.dev) (Postgres in WASM) with real PostGIS.
You get the schema served three ways at once: the raw Postgres wire protocol
for psql, a Supabase-compatible REST API, and a Studio dashboard.

Why tinbase instead of `supabase start`? Same wire protocols and migration
conventions, but one Node process at ~tens of MB of RAM instead of a
12-container Docker stack — boots in seconds, resets with `rm -rf .tinbase`,
and your migrations stay portable to hosted Supabase.

This repo uses [pnpm](https://pnpm.io) (preferred over npm here — the
committed lockfile is `pnpm-lock.yaml`, and `package.json` pins the version
via `packageManager`). If you don't have it:

```bash
npm install -g pnpm   # or: corepack enable && corepack prepare pnpm --activate
```

```bash
pnpm install
pnpm dev
#   REST      http://127.0.0.1:54321/rest/v1/
#   Studio    http://127.0.0.1:54321/_/
#   psql      postgres://postgres@127.0.0.1:55432/postgres
```

Migrations run automatically at boot: every `supabase/migrations/*.sql` not
yet recorded in `supabase_migrations.schema_migrations` is applied, then
skipped on later boots.

Then, in another terminal:

```bash
pnpm load-zips   # required first: counties resolve via ZIP
pnpm seed        # deterministic Atlanta-metro dev data
pnpm test        # unit tests + the pgTAP suite on a throwaway instance
```

**Studio:** open <http://127.0.0.1:54321/_/> and sign in with the
`service_role` key from the `pnpm dev` startup output. Copy the whole
token — it's ~200 characters and wraps across terminal lines, and a partial
paste fails with "Invalid API key". (`... | pbcopy` is your friend.)

**Stable API keys:** by default the keys rotate every restart. To keep them
stable, `cp .env.example .env` and set `TINBASE_JWT_SECRET` — `pnpm dev`
loads `.env` automatically.

#### MCP (AI tooling)

With the dev server running, AI clients can query the
database through Supabase's
[PostgREST MCP server](https://www.npmjs.com/package/@supabase/mcp-server-postgrest)
(tools: `postgrestRequest` for CRUD, `sqlToRest` for SQL→REST translation).
It authenticates with the `service_role` key from the `pnpm dev` output.

- **Claude Code** — preconfigured: `.mcp.json` in this repo reads
  `SUPABASE_SERVICE_ROLE_KEY` from `.env`; just approve the `supabase`
  server when prompted.
- **Claude Desktop** — Settings → Developer → Edit Config, add under
  `mcpServers`:

  ```json
  "supabase": {
    "command": "npx",
    "args": ["-y", "@supabase/mcp-server-postgrest",
             "--apiUrl", "http://127.0.0.1:54321/rest/v1",
             "--apiKey", "<service_role key>",
             "--schema", "public"]
  }
  ```

- **Codex CLI** — add to `~/.codex/config.toml`:

  ```toml
  [mcp_servers.supabase]
  command = "npx"
  args = ["-y", "@supabase/mcp-server-postgrest",
          "--apiUrl", "http://127.0.0.1:54321/rest/v1",
          "--apiKey", "<service_role key>",
          "--schema", "public"]
  ```

- **ChatGPT** — connectors only accept remote HTTP MCP servers, so a
  localhost dev database doesn't apply.

Note: querying goes through the Supabase MCP server for now; a dedicated
OpenComps MCP server will replace it once the schema and API stabilize.

#### Agent skill

`.claude/skills/opencomps/SKILL.md` teaches an AI agent the whole surface
in one file: table map, search RPCs, write conventions, common errors,
and worked multi-step examples. To load it:

- **Claude Code** — auto-discovered inside this repo; for other projects,
  copy the directory to `~/.claude/skills/`.
- **Claude Desktop / claude.ai** — upload the skill folder under
  Settings → Capabilities → Skills.
- **Codex CLI / ChatGPT / others** — no skill system: paste the file's
  body into `AGENTS.md`, custom instructions, or the system prompt.

Any generic Postgres MCP server also works, pointed at
`postgres://postgres@127.0.0.1:55432/postgres` — as can any agent that can
run `psql` against that URL directly. One session at a time (PGlite is
single-writer).

#### Example prompts

With the database seeded (`pnpm load-zips && pnpm seed`), ask your AI
client things like:

- `What were the three biggest multifamily sales, and at what price per unit?`
  — filters, joins, and ordering via the REST tools.
- `What are 2-bedroom apartments renting for around Grant Park?`
  — spatial rent comps via `POST /rpc/nearby_unit_rents`.
- `What sold in 30305 over the last few years?`
  — ZIP-anchored search via `POST /rpc/nearby_sales`.
- `Find arms-length multifamily sales since 2023 within 5 miles of Midtown Atlanta, with price per unit and cap rate.`
  — radius comp search via `POST /rpc/nearby_sales`.
- `Pull comps for 14 Waddell Street NE: multifamily sales from the last four years within 5 miles, 30 to 130 units.`
  — subject-anchored selection via `POST /rpc/comps_for_property`.
- `Research current 2-bedroom rents around Grant Park on the web and save
  them to the database as rent comps.`
  — writes work too: REST inserts into `addresses`, `properties`, and
  `property_unit_rents` (set `observed_on`, `source_url`, and leave
  `verification_status` at `unverified` for scraped data); geography
  columns accept `SRID=4326;POINT(lon lat)` strings. Then re-ask the
  Grant Park rent question above — the new comps come back through
  `nearby_unit_rents` alongside the seed data.
- `What's the average cap rate by asset class?`
  — aggregates need SQL, so this goes through `psql` (or a Postgres MCP).

Spatial search ships as database functions, so REST/MCP clients get PostGIS
without raw SQL: `nearby_sales` and `nearby_unit_rents` anchor on
`lat`/`long` or a `zip` centroid (ZIPs need `pnpm load-zips`) with a
`radius_m`; `comps_for_property` anchors on a subject property and adds
appraisal-style culling — recency against an `as_of` effective date,
arms-length-only by default, size and vintage brackets, strict property-type
matching. Ingest gets the same treatment: `find_property` answers "is this
property already in the database?" as a waterfall (normalized APN scoped by
ZIP county, then address trigram similarity, then PostGIS proximity — each
hit labeled `matched_by`), and `bulk_insert` takes
`{"target": "<table>", "rows": [...]}` for multi-row writes from REST
clients that can only send JSON object bodies. `convert_measure` converts
lengths (`m`/`km`/`ft`/`yd`/`mi`), areas (`sqm`/`sqft`/`acre`/`hectare`),
and per-area rates (`per_sqft`↔`per_sqm`) so clients can report
`dist_meters` in miles or feed a miles radius into `radius_m` without
doing the arithmetic. Aggregates still need the SQL path.

The database persists in `.tinbase/pglite/` (gitignored).
`rm -rf .tinbase` resets everything (next boot re-migrates; re-run
`pnpm load-zips && pnpm seed`). `pnpm dev -- --memory` runs an ephemeral
in-memory instance instead. Override ports with `TINBASE_PORT`
(HTTP, default 54321) and `PGLITE_PORT` (Postgres wire, default 55432).

Because the REST API speaks Supabase's wire protocol, the official
`@supabase/supabase-js` SDK works against it unchanged — point it at
`http://127.0.0.1:54321` with the anon key printed at startup.

Two caveats: PGlite is an **experimental WASM build** of Postgres 18 +
PostGIS 3.6 (the Docker path below runs the same versions natively and is
the full-fidelity reference — the same pgTAP suite runs on both, so
divergence surfaces as test failures rather than silent drift), and PGlite
is a single-writer database — fine for dev tools
and one interactive session, not for concurrent load. Bulk loads over the
socket must avoid `\copy`/COPY FROM STDIN (the loaders already do).

### Full-fidelity Docker database

The included Docker setup runs PostgreSQL 18 with PostGIS 3.6, the schema
extensions, pgTAP, and `pg_prove`.

Boot the database, apply the schema, and run the pgTAP test suite:

```bash
docker compose up -d --wait pg
./scripts/migrate.sh
./scripts/test_db.sh
```

The first boot builds the image from source (pgTAP, `pg_prove`) — allow
several minutes. If `127.0.0.1:5432` is already bound, `up` fails
immediately; set `POSTGRES_PORT` on each command as shown below.

Two databases are involved: `migrate.sh` applies the schema to the
`opencomps` dev database, while `test_db.sh` runs against a dedicated
`opencomps_test` database that it recreates from the schema file on every
run — tests always exercise the current schema and never touch dev data.
(`test_db.sh` auto-detects its backend: the running Docker service, then
PGlite, then a local Postgres; force one with
`OPENCOMPS_TEST_BACKEND=docker|pglite|local`.)
To start over completely, `docker compose down -v` destroys the database
volume; repeat the steps above to rebuild.

Default connection:

```bash
postgres://postgres:postgres@localhost:5432/opencomps
psql postgres://postgres:postgres@localhost:5432/opencomps
```

Override with `POSTGRES_PORT`, `POSTGRES_DB`, `POSTGRES_USER`,
`POSTGRES_PASSWORD`, or `DATABASE_URL`.

To use a different host port, set `POSTGRES_PORT` on each command:

```bash
POSTGRES_PORT=55432 docker compose up -d --wait pg
POSTGRES_PORT=55432 ./scripts/migrate.sh
POSTGRES_PORT=55432 ./scripts/test_db.sh
```

### Manual database

```bash
createdb opencomps
psql -d opencomps -v ON_ERROR_STOP=1 -1 -f supabase/migrations/20260709000000_opencomps.sql
```

The `-1` applies the whole schema in a single transaction (the file itself
carries no BEGIN/COMMIT so tinbase's migration runner can wrap it); a failed
apply leaves nothing behind.

### US ZIP geodata

OpenComps ships with a `us_zips` table for US ZIP code reference data
(centroids, cities, counties, population, density, timezones), used for
radius searches, nearest-ZIP lookups, and joining addresses to counties and
taxing jurisdictions. The data comes from the free SimpleMaps US Zips
database and loads with one command:

```bash
./scripts/load_us_zips.sh
```

This downloads the dataset (about 34,000 ZIPs) and loads it in a single
transaction. Re-running it refreshes the table.

The data changes regularly, so the loader detects the newest SimpleMaps
release automatically (pin one with `US_ZIPS_VERSION=1.95.1` if you need
reproducibility), and every load is recorded in `reference_dataset_loads`
with the release version, source, row count, and load time. To see what's
currently loaded:

```sql
SELECT version, row_count, loaded_at
FROM reference_dataset_loads
WHERE dataset = 'us_zips'
ORDER BY loaded_at DESC
LIMIT 1;
```

If SimpleMaps blocks direct `curl` downloads, download the free ZIP from
their site in a browser and run:

```bash
US_ZIPS_FILE=~/Downloads/simplemaps_uszips_basicv1.95.1.zip ./scripts/load_us_zips.sh
```

**Note:** Use of the free database in production requires that you link
back to: <https://simplemaps.com/data/us-zips>

Postal systems differ by country, so geodata tables are per-country by
design. `us_zips` covers the US today; tables for other countries (Canadian
postal codes, UK postcodes) can follow the same pattern later.

### Dev seed data

To explore the schema with realistic data, seed 250 properties built on
real, public-record Atlanta-metro addresses:

```bash
./scripts/load_us_zips.sh   # required first: counties resolve via ZIP
./scripts/seed_dev.sh
```

The addresses and geocodes are real; the records hung on them — parcels,
owners, transfers, comps, assessments, tax bills, mortgages, listings —
are synthetic but plausible, and deterministic: reseeding always produces
identical data.

## Conventions (read before contributing)

- **UUID primary keys** (`gen_random_uuid()`), everywhere. Natural keys are
  unique indexes, never PKs.
- **Typed columns for hot fields, JSONB for the long tail.** If
  professionals filter or sort on it, it's a column. If it's asset-class
  specific (RevPAR, per-bed rent), it goes in `metrics`, governed by
  `comp_types.field_definitions`: trigger-enforced on
  `pending_review`/`verified` rows, lax for raw `unverified` imports.
- **Enums for closed sets, rows for open sets.** Statuses and kinds are PG
  enums; comp types, property types, and taxonomies are data.
- **Money stays as quoted.** Every money-bearing table carries a `currency`
  (ISO 4217, default `'USD'`) that governs all amounts on the row. Amounts
  are stored as quoted in their market, never converted.
- **Measurements in base units.** Each row declares its `unit_system`:
  `'imperial'` means square feet and $/SF, `'metric'` means square meters
  and per-m². Areas are stored in those base units — acres and hectares are
  exact display conversions for the app layer, never stored values.
- **Every fact carries provenance**: `source_record_id`,
  `verification_status`, and (where user-entered) `contributed_by_id`.
- **Temporal semantics**: all `(started_on, ended_on)` pairs are
  `[start, end)`, meaning `ended_on` is exclusive. Constraints protect the
  *verified* timeline only; raw imports may conflict, and reconciliation is
  a pipeline job.
- **Raw before normalized.** Parcel numbers and identifiers are stored
  exactly as issued (per RESO UPI v2), with normalized copies alongside for
  matching, never instead.

## Contributing

1. Open an issue describing the modeling problem before writing DDL. Schema
   debates are cheaper than migrations.
2. Changes must apply cleanly to a fresh database (`ON_ERROR_STOP`) and
   include a scenario test: real-world inserts plus queries proving the
   behavior, and negative tests proving the constraints fire.
3. Follow the conventions above. PRs that add a JSONB blob where a typed
   column belongs, or a natural PK, will be asked to rework.

## License

[MIT](LICENSE)
