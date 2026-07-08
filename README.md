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

One file, `database/schema/opencomps.sql` (PostgreSQL 17+, PostGIS 3.5+):
41 tables, 3 views.

| Layer | Tables |
|---|---|
| Identity | `properties`, `parcels`, `property_parcels`, `parcel_lineage`, `property_identifiers`, `jurisdictions`, `addresses` |
| Classification | `comp_types`, `property_types`, `property_type_mappings`, `classification_taxonomies` |
| Provenance | `data_providers`, `source_records`, `data_verifications` |
| Reference data | `us_zips`, `reference_dataset_loads` |
| Physical | `residential_details`, `commercial_details`, `land_details`, `structures`, `spaces` |
| Owners | `owners`, `owner_contacts`, `owner_addresses` |
| Public records | `property_transfers`, `ownership_periods`, `ownership_interests`, `assessments`, `tax_bills`, `property_mortgages` |
| Comps | `property_sales`, `property_leases`, `rent_escalations`, `lease_concessions`, `property_unit_rents`, `property_listings`, `valuations`, `income_expense_statements` |
| Workflow | `comp_sets`, `comp_set_items`, `users` (minimal, auth-agnostic) |

## Getting started

Requirements: Docker with Docker Compose for local setup, or PostgreSQL 17+
with PostGIS 3.5+ installed manually (extensions used: `postgis`, `citext`,
`pg_trgm`, `btree_gist`; plus `pgtap` to run the test suite).

### Local Docker database

The included Docker setup runs PostgreSQL 17 with PostGIS 3.5, the schema
extensions, pgTAP, and `pg_prove`.

Boot the database, apply the schema, and run the pgTAP test suite:

```bash
docker compose up -d --wait pg
./scripts/migrate.sh
./scripts/test_db.sh
```

Two databases are involved: `migrate.sh` applies the schema to the
`opencomps` dev database, while `test_db.sh` runs against a dedicated
`opencomps_test` database that it recreates from the schema file on every
run — tests always exercise the current schema and never touch dev data.
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
psql -d opencomps -v ON_ERROR_STOP=1 -f database/schema/opencomps.sql
```

The whole schema applies in a single transaction; a failed apply leaves
nothing behind.

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
  specific (RevPAR, per-bed care level), it goes in `metrics` governed by
  `comp_types.field_definitions`.
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
