---
name: opencomps
description: Use when reading or writing property records and comps — sales, leases, unit rents, listings, parcels, owners, assessments, valuations — in an OpenComps database, via the supabase PostgREST MCP server or psql. Also use when a spatial "comps near X" search, comp pull for a subject property, or scraped-data ingest against OpenComps is needed.
---

# Using OpenComps

OpenComps is an open-source PostgreSQL + PostGIS database for property
records and comparables. Everything below is the actual schema — **never
guess table, column, or function names; they are all listed here.** REST
offers no schema introspection, so guessing burns dozens of failed calls.

## Access

Two paths to the same database (dev server: `pnpm dev` in the OpenComps repo):

| Path | Endpoint | Use for |
|---|---|---|
| `supabase` MCP (`postgrestRequest`) | `http://127.0.0.1:54321/rest/v1` | CRUD, embedded joins, RPC calls |
| psql | `postgres://postgres@127.0.0.1:55432/postgres` | Aggregates (`AVG`/`GROUP BY` — REST can't), transactions, `EXPLAIN`, introspection |

`sqlToRest` translates simple SELECTs only: no INSERT, no PostGIS in
WHERE, no boolean constants. One psql session at a time (PGlite is
single-writer). Docker path instead: `postgres://postgres:postgres@localhost:5432/opencomps`.

The no-aggregates-over-REST rule is a **tinbase limitation**, not a
PostgREST one. Against regular Supabase (hosted or `supabase start`),
real PostgREST v12+ serves `avg`/`sum`/`count`/`max`/`min` directly
(`select=sale_price.avg()`) — use the client/MCP there, no SQL detour.
Everywhere (tinbase or Supabase), medians/percentiles, window functions,
and latest-row-per-group joins (`DISTINCT ON`, CTEs) exceed PostgREST —
those need psql, or a SQL function called via `POST /rpc/...`.

MCP not connected? Setup lives in the repo README ("MCP (AI tooling)":
`@supabase/mcp-server-postgrest` against the tinbase REST endpoint, key
from the `pnpm dev` output); any agent with a shell can use
`psql <url> -c "..."` meanwhile. This skill lives at
`.claude/skills/opencomps/`; copy the directory to `~/.claude/skills/`
to use it from anywhere (for clients without skills, paste the body into
`AGENTS.md`).

## Search & conversion RPCs — never hand-write PostGIS filters

PostGIS is not reachable through REST filters; these functions are.
Spatial searches return nearest-first with `dist_meters` (always meters);
radius arguments are meters; bad anchors/arguments raise SQLSTATE
`22023`. PostgREST filters compose on RPC results:
`POST /rpc/nearby_sales?comp_type=eq.multifamily&sale_date=gte.2023-01-01`.

**Numbers come from Postgres, never model arithmetic.** Unit conversions
(report `dist_meters` in miles for US properties, miles→`radius_m`,
acres→sq ft, `per_sqft`↔`per_sqm`) go through `convert_measure` — the
calls are independent, so fire one per value in a single parallel
message. Derived stats (avg/median/spread) → SQL via psql.

| Function | Arguments (defaults) | Returns |
|---|---|---|
| `nearby_sales` | `lat`, `long` OR `zip` (us_zips centroid); `radius_m` (5000) | sale_id, property_id/name, comp_type, sale_date, sale_price, price_per_area, price_per_unit, unit_count_at_sale, cap_rate, sale_type, verification_status, dist_meters |
| `nearby_unit_rents` | same anchor args | rent_id, property_id/name, comp_type, unit_type, bedrooms, bathrooms, rate_amount, rate_period, rate_basis, rate_type, observed_on, verification_status, dist_meters |
| `comps_for_property` | `subject_property_id` (required); `radius_m` (5000), `max_age_months` (36), `as_of` (today), `same_property_type` (false), `size_tolerance_pct`/`min_size`/`max_size` (null), `year_built_tolerance` (null), `sale_types` (`['arms_length']`), `verified_only` (false), `max_results` (25) | nearby_sales columns + property_type, comp_size, year_built. Matches subject's asset class, excludes the subject's own sales. Size basis: GLA (residential), unit count (multifamily), lot size (land), RBA (other commercial) — metric/imperial normalized |
| `convert_area` | `val`, `from_units`, `to_units` (`'imperial'`/`'metric'`) | sq ft ↔ m² |
| `convert_measure` | `val`, `from_unit`, `to_unit` — length `m`/`km`/`ft`/`yd`/`mi`, area `sqm`/`sqft`/`acre`/`hectare`, rates `per_sqm`/`per_sqft` | converted NUMERIC; cross-dimension or unknown units raise `22023`; NULL in → NULL out |
| `find_property` | `apn` (any formatting; optional `zip` scopes to that county), `address` (free text), OR `lat`+`long`; `radius_m` (50) | property_id/name, full_address, matched_by (`parcel`/`address`/`location`), dist_meters. Waterfall — strongest signal wins, weaker rungs not consulted; ≤5 rows best-first; no rows = not in DB |

## Table map

| Layer | Tables |
|---|---|
| Identity | `properties`, `parcels`, `property_parcels`, `parcel_lineage`, `property_identifiers`, `jurisdictions`, `addresses` |
| Classification | `comp_types`, `property_types`, `property_type_mappings`, `classification_taxonomies` |
| Provenance | `data_providers`, `source_records`, `data_verifications` |
| Reference | `us_zips`, `reference_dataset_loads` |
| Physical | `residential_details`, `commercial_details`, `land_details`, `structures`, `spaces` |
| Owners | `owners`, `owner_contacts`, `owner_addresses` |
| Public records | `property_transfers`, `ownership_periods`, `ownership_interests`, `assessments`, `tax_bills`, `property_mortgages` |
| Comps | `property_sales`, `property_leases`, `rent_escalations`, `lease_concessions`, `property_unit_rents`, `property_listings`, `valuations`, `income_expense_statements` |
| Workflow | `comp_sets`, `comp_set_items`, `users` |

Views: `v_current_sources`, `v_current_ownership`, `v_property_sale_history`.

**Which event table** (the most common mistake):

- `property_sales` — closed sale transactions. Typed columns include
  `sale_price`, `price_per_area`, `price_per_unit`, `unit_count_at_sale`,
  `cap_rate`, `sale_type`, `sale_date`.
- `property_leases` — signed **commercial lease deals** (term, NER, TI,
  concessions).
- `property_unit_rents` — **surveyed/asking unit rents**. An apartment
  "2BR asking $2,150/mo" goes here, never in `property_leases`. Typed
  columns: `unit_type` (required, e.g. `'2BR/2BA'`), `bedrooms`,
  `bathrooms`, `unit_area`, `rate_amount`, `rate_period` (`'monthly'`),
  `rate_basis` (`'per_unit'`), `rate_type`
  (`'asking'|'effective'|'contract'`), `observed_on` (required),
  `source_url`, `concessions_note`.
- `property_listings` — active for-sale/for-lease listings (`listing_kind`).
- `valuations` — appraisal/AVM/BPO opinions, not transactions.
- `property_transfers` — **all** deed transfers including quitclaims;
  never treat as comps. Market sales live in `property_sales`.

**Canonical vocabulary** (fixed UUIDs; reference by code, never insert new):
`comp_types` `30000000-0000-0000-0000-00000000000N`, N = 1 residential,
2 office, 3 retail, 4 multifamily, 5 industrial, 6 land.
`property_types` `31000000-0000-0000-0000-00000000000N`, N = 1 RES_SFD,
2 COM_OFF, 3 COM_RET, 4 MF_MID, 5 COM_IND, 6 LND_COM.

## Reading

Embedded joins work: `GET /properties?select=name,addresses(full_address),property_sales(sale_date,sale_price)&property_sales.order=sale_date.desc`.
Property lookup is `POST /rpc/find_property` with the strongest identity
at hand — APN + ZIP beats address beats coordinates: body
`{"apn": "18-108-01-055", "zip": "30329"}` or
`{"address": "855 Emory Point Dr NE, Atlanta GA"}`. Substring fallback
for a bare fragment:
`GET /addresses?select=id,full_address&full_address=ilike.*366 Altoona*`
then `GET /properties?situs_address_id=eq.<id>`. Aggregates → psql.

## Comp questions: database first, web by consent

"What are X renting/selling for around Y" questions follow this shape:

1. Answer from OpenComps (`nearby_*` / `comps_for_property`), presented
   as what the database holds, with `observed_on`/`sale_date` visible so
   staleness shows.
2. Close with a one-sentence offer to extend the picture via web research
   (and any research tools/MCPs available). Do no web research before
   the user accepts.
3. On yes: research read-only — inline searches for a quick survey, a
   `property-researcher` fan-out for a deep pull. Run `find_property`
   on each candidate (reads parallelize) and present only those not
   already in the database: a separate list, marked unsaved, each with
   its source. Never blend unsaved web findings into database results.
4. Ask which to save — all, some, or none (multi-select where the client
   supports it). Persist only what was chosen, through the normal
   dedup → `bulk_insert` funnel, unverified with `source_url`s.

## US ZIP reference data (`us_zips`)

One row per ZIP (loaded by `pnpm load-zips`; the spatial RPCs' `zip`
argument and county resolution both depend on it). Key columns: `zip`
(PK, 5 chars), `city`, `state_id`, `county_fips`, `county_name`,
`county_weights` (JSONB population share for ZIPs spanning counties),
`location` (centroid geography), `population`, `density`, `timezone`.

- Authoritative over any scraped source: take `city`/`state_id` spelling
  from it (USPS primary city) and resolve counties through it —
  `GET /us_zips?zip=eq.30041&select=county_fips,county_name`
  (`county_fips` is the primary county; check `county_weights` when
  precision matters). Never take county/city from listing sites.
- City → ZIPs: `GET /us_zips?state_id=eq.GA&city=eq.Cumming&select=zip`.
- The `zip` argument on `nearby_sales`/`nearby_unit_rents` anchors at
  this table's centroid — no coordinates needed for "near ZIP X" asks.

## Writing

**Before creating any property, run `find_property` (Reading, above)**.
A hit means reuse that `property_id` — new sales, rents, assessments,
and ownership changes append to the existing property as new event rows,
never as a duplicate property. Insert new identity rows only on a miss.

Insert order: `addresses` → `properties` → event row. Single rows: POST
the object; `?select=...` returns the created row's id. **Multi-row
inserts: `POST /rpc/bulk_insert`** with body
`{"target": "<table>", "rows": [{...}, ...]}` — returns the inserted
rows as jsonb (generated ids and defaults included); columns absent from
the payload keep their DEFAULTs; unknown keys error like the REST path;
vocabulary/reference tables (`comp_types`, `property_types`, `us_zips`,
…) are refused. Never POST a bare top-level JSON **array** to a table
path: the MCP client delivers it as a string and the server rejects it
before PostgREST sees it.
Record only what the source states — leave unknown fields NULL rather
than inventing plausible values (a "2BR" listing with unknown baths is
`unit_type: "2BR"`, `bathrooms: null`). Column lists in this skill are
the load-bearing subset; before inserting into a table not detailed
here, `GET /<table>?limit=1` to see live column names (REST has no
other introspection).

- `addresses`: `address_hash` is required — canonical recipe:
  `md5(lower('<number> <name> <suffix> <post-directional>, <locality>, <region> <postal_code>'))`,
  whitespace collapsed, absent parts skipped. Always this recipe, never an
  improvised one: the UNIQUE constraint only dedups across sessions when
  every writer hashes identically. `full_address` is a
  **generated column — never set it** (error 428C9). Structured components:
  `street_number`, `street_name`, `street_suffix`,
  `street_post_directional`, `locality`, `region`, `postal_code`.
- Geography columns (`location` on addresses/properties) accept EWKT
  strings: `"SRID=4326;POINT(-84.363 33.741)"` (lon first). Geocode free,
  no API key, via US Census: `curl "https://geocoding.geo.census.gov/geocoder/locations/onelineaddress?address=<url-encoded one-line address>&benchmark=Public_AR_Current&format=json"`
  — `addressMatches[0].coordinates` has `x` = longitude, `y` = latitude
  (US addresses only; empty `addressMatches` means no match, not an error).
- Public-records chain, in FK order: `jurisdictions` (one county row:
  `country 'US'`, `region`, `kind 'county'`, `authority_code` = 5-digit
  county FIPS from `us_zips`, above; unique on country+kind+code — GET
  before POST to reuse) →
  `parcels` (`jurisdiction_id`, `country`, `authority_code`,
  `parcel_number` raw exactly as issued plus `normalized_parcel_number`
  (strip spaces/punctuation, matching only);
  `reso_upi` is generated — never set) → `property_parcels`
  (`property_id`, `parcel_id`, `is_primary`) → `assessments` and
  `tax_bills` (both keyed by `parcel_id` + `jurisdiction_id` +
  `tax_year`).
- Provenance on every row, always: events get `observed_on`/event date
  and the primary `source_url`; additional contributing URLs go in the
  event's `metadata.source_urls`. Identity rows created from research
  (`properties`, details, parcels) have no `source_url` column — record
  contributing URLs in their `metadata.source_urls`. Structure:
  `[{"url": "...", "retrieved_on": "YYYY-MM-DD"}]`, listing only pages a
  saved fact actually came from. A saved record whose sources can't be
  traced is a defect. Leave
  `verification_status` at `'unverified'` for scraped/imported data —
  never self-promote to `'verified'` (statuses: unverified,
  pending_review, verified, disputed, rejected). Source hierarchy:
  authoritative public records (county assessor, recorder) beat broker
  sites, which beat aggregator/search snippets — on conflict, store the
  public-record value and note the discrepancy in `metadata`.
- Prefer typed columns. The `metrics` JSONB is governed by
  `comp_types.field_definitions`: undefined keys are rejected (SQLSTATE
  `23514`) once a row reaches `pending_review`/`verified`. Don't invent
  keys like `{"beds": 2}` — `bedrooms` is a column.
- Money: `currency` CHAR(3) per row (default USD), amounts as quoted,
  never converted. Areas: per-row `unit_system`; store sq ft or m², never
  acres.
- Key enums: `sale_type` (`arms_length`, `reo`, `short_sale`, `auction`,
  `related_party`, `portfolio`, `partial_interest`, `land_contract`,
  `new_construction`, `other`); `rent_period` (`daily`, `monthly`,
  `annual`, `per_area_annual`, `per_area_monthly`); `unit_rate_basis`
  (`per_unit`, `per_bed`, `per_area`, `per_room`, `per_key`, `per_slip`,
  `per_stall`, `per_pad`, `other`).

## Bulk & parallel ingest

**Fan out research, funnel writes.** Web research parallelizes: one
read-only `property-researcher` agent per candidate property, all
launched in a single message, each returning a structured payload
(the `property-payload` skill defines the contract; if the agent types
aren't available, general-purpose subagents given the same read-only
rules and contract work identically). Writes
never parallelize: one `records-writer` (or the main loop) persists all
payloads serially — parallel writers race the `find_property` dup check,
double-create shared rows like `jurisdictions`, and fight PGlite's
single-writer socket. Cross-payload dedup (two sources, same property)
only works where all payloads are visible together: at the funnel.

**Baseline public records are vital — always dispatch
`assessor-fetcher`.** Every research/ingest fan-out includes
browser-capable `assessor-fetcher` agents, one per county (group the
properties by `us_zips` county first), launched in the same parallel
message as the researchers. Researchers have no browser and routinely
lose the assessor tier to bot-blocking (qPublic/Beacon 403s); the
fetcher escalates direct API → playwright browser → the user's Chrome
session → computer use and returns rung-1 fragments: APN, assessments,
tax bills, owner, **and the deed/sales history the assessor prints**
(every transfer → `property_transfers`; the qualified/arms-length
priced ones → `property_sales` too). Those recorded sales are baseline
public data, not a researcher's job — save them alongside the
assessments, never drop them. Merge at
the funnel: the fetcher's rung-1 facts win over anything a researcher
or document supplied, per the contract's trust ladder. Skip the
dispatch only when rung-1 baseline is already in the database or the
source itself is an assessor record.

**Shared documents & URLs** (a PDF/XLSX/CSV or a pasted link —
appraisals, comp sheets, rent surveys, offering memos): dispatch a
`property-extractor` agent — it classifies the document, extracts the
subject and every comp as contract payloads (appraisals map approach
values onto `valuations`), and flags gappy payloads `needs_research` /
`needs_public_records`. Then fan out one
`property-researcher` per research-flagged payload plus one
`assessor-fetcher` per county (parallel, single message) to
fill the gaps — the document outranks everything the research finds
except public entity records — and funnel the completed payloads to the
writer. Ambiguity gets one question for the whole document, never per
row.

**Batch geocoding**: >10 addresses, use the Census batch endpoint instead
of per-address calls — CSV with columns `id,street,city,state,zip`, then
`curl -s -F addressFile=@batch.csv -F benchmark=Public_AR_Current
"https://geocoding.geo.census.gov/geocoder/locations/addressbatch"`
returns a CSV of matches (up to 10k rows per call).

## Comp sets (saving a comp selection)

A comp pull worth keeping becomes a `comp_sets` row plus one
`comp_set_items` row per comp. `comp_sets`: `name` (required),
`subject_property_id`, `effective_date`, `purpose`, `notes`, and
`search_criteria` JSONB — record the actual filters you ran so the set
is reproducible. `comp_set_items` is polymorphic: `comp_kind`
(`'sale'|'lease'|'listing'|'unit_rent'`) says which event table
`comp_id` points into (`property_sales.id` for `'sale'`, etc.);
`position` orders the set; `selection_source` is `'user'`,
`'ai_suggested'` (use this when an RPC or agent picked the comp), or
`'imported'`; per-item `notes` hold the rationale.
`(comp_set_id, comp_kind, comp_id)` is unique — no duplicate members.
Read a set back embedded:
`GET /comp_sets?select=name,effective_date,comp_set_items(position,comp_kind,comp_id,notes)&subject_property_id=eq.<id>`.

## Worked examples

**Comps for a subject property** (multi-step):
1. `POST /rpc/find_property` body `{"address": "14 Waddell St NE, Atlanta GA"}`
   → subject's property_id (add `apn`/`zip` when known — stronger signal)
2. `POST /rpc/comps_for_property` body
   `{"subject_property_id": "<id>", "radius_m": 8046.72, "max_age_months": 48, "min_size": 30, "max_size": 130}`

**Web research → ingest → verify**:
1. Research rents/sales on the web; geocode addresses (US Census, above).
2. Dedup check each property: `POST /rpc/find_property` (APN, else
   address, else the geocoded lat/long) — hits keep their existing
   property_id and skip step 3's identity inserts for that row.
3. `POST /rpc/bulk_insert` `{"target": "addresses", "rows": [...]}`
   (rows carry `address_hash`, EWKT `location`) → map returned ids →
   `bulk_insert` into `properties` (link `situs_address_id`, set
   `property_type_id`, EWKT `location`) → `bulk_insert` into
   `property_unit_rents` (link `property_id`, `comp_type_id`,
   `rate_type: "asking"`, `observed_on`, `source_url`, leave unverified).
4. Prove it: `POST /rpc/nearby_unit_rents?bedrooms=eq.2` body
   `{"lat": ..., "long": ..., "radius_m": 3000}` — new rows return
   alongside existing data, nearest first.

**Research a subject property end-to-end → ingest → comp set**
(the full flow; record only what sources state, everything unverified):

1. `POST /rpc/find_property` with the address first — if the subject is
   already in the database, reuse its property_id and skip to step 7.
   Then research the address. Baseline first: authoritative public
   records — the county tax assessor / GIS parcel viewer — for APN,
   assessed values, taxes, and owner. Commercial listing portals often block
   automated fetches (403); search-result snippets and broker sites
   usually still carry the deal facts (price, SF, zoning, status).
2. Geocode via the US Census endpoint above.
3. County: `GET /us_zips?zip=eq.<zip>&select=county_fips,county_name`,
   then `GET /jurisdictions?country=eq.US&kind=eq.county&authority_code=eq.<fips>`
   — POST a new county row only if absent.
4. `POST /addresses` (address_hash, EWKT location) → `POST /properties`
   (`situs_address_id`, `property_type_id`, location) → details row by
   asset class (`commercial_details`/`residential_details`/`land_details`;
   convert acres to sq ft) → one `structures` row per building if the
   source itemizes them.
5. Parcel chain (step 3's jurisdiction id): `POST /parcels` (APN raw as
   issued) → `POST /property_parcels` (`is_primary: true`) →
   `tax_bills`/`assessments` rows for whatever years the source states.
6. Event rows as found: an off-market "was asking $X" is a
   `property_listings` row with `status: "withdrawn"`; a closed sale is
   `property_sales`; never fabricate sale history that wasn't published.
7. Comps: `POST /rpc/comps_for_property`. If the set comes back thin,
   widen `max_age_months`/`radius_m` and say so in the comp set's
   `notes`; put the final filters in `search_criteria`.
8. Save `comp_sets` + `comp_set_items` (`selection_source:
   "ai_suggested"`, position = RPC's nearest-first order), then prove
   the whole graph with one embedded GET on `/properties` selecting
   address, details, structures, listings,
   `property_parcels(parcels(tax_bills(...)))`, and
   `comp_sets(comp_set_items(...))`.

**Aggregates** (psql only):
`psql <url> -c "SELECT ct.code, ROUND(AVG(ps.cap_rate),2) FROM property_sales ps JOIN comp_types ct ON ct.id = ps.comp_type_id WHERE ps.cap_rate IS NOT NULL GROUP BY ct.code"`

## Common errors

| Error | Meaning / fix |
|---|---|
| `PGRST202 Could not find the function` | RPC name wrong — the only RPCs are the ones in the table above |
| `PGRST200` on `avg()`/aggregates | REST aggregates unsupported — use psql |
| `428C9 ... generated column` | You set `full_address` — remove it |
| `22P02 invalid input value for enum` | Check the enum lists above |
| `22023 invalid_parameter_value` from RPC | Bad anchor (need `lat`+`long` or a known `zip`) or unresolvable subject property/size |
| `23514` on insert/update | `metrics` violates `comp_types.field_definitions` governance — use typed columns or the declared keys |
| `ZodError ... expected record/array, received string` on POST | Body was a top-level JSON array — MCP can't deliver those; use `POST /rpc/bulk_insert` `{"target", "rows"}` instead |
| sqlToRest `UnimplementedError` / `UnsupportedError` | It only translates simple SELECTs — write the PostgREST request directly |
