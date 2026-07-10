---
name: property-payload
description: Use when producing or consuming OpenComps research/extraction payloads — the shared contract and data-discipline rules for the property-researcher, property-extractor, assessor-fetcher, and records-writer agents.
user-invocable: false
---

# Property payload contract

Shared rules for agents that gather property data (researcher,
extractor, assessor-fetcher) and the writer that persists it.

## Source trust ladder

When sources disagree, the higher rung wins and the discrepancy goes in
`notes`:

1. **Public entity records** — tax assessor, GIS parcel viewer,
   recorder/deed records, tax commissioner, planning/zoning portals,
   US Census, state GIS, FEMA. Above all other sources.
2. **The user-shared document/URL under extraction** — authoritative for
   everything it states (it is often the only source for deal terms,
   appraisal values, contract rents); only rung 1 may override it.
3. **Broker and listing sites**.
4. **Aggregators, news, search snippets** — leads and corroboration only.

**Assessment ≠ appraisal**: an assessment is a public entity's taxable
value (→ `assessments`, keyed by parcel + tax year); an appraisal is a
professional opinion of value (→ `valuations`,
`valuation_kind: 'appraisal'`). Never conflate them.

## When a public-records lookup fails

A `not_found`/`ambiguous`/error from an assessor lookup (the
assessor-lookup MCP, a county portal search, a GIS query) is a prompt to
escalate, not a dead end. Work the ladder in order; parcel identity
always beats address identity:

1. **Normalize the address** and retry: strip city/state/ZIP, spell
   suffixes the county's way (`Street`↔`ST`), keep directionals
   (`S Nucla St` — Aurora also has a `S Nucla Way`), drop unit markers.
2. **Resolve the APN/parcel independently** — county GIS/ArcGIS parcel
   layer query, county parcel-search site, or a web search for
   `"<address>" parcel OR APN` — then retry the lookup **by parcel**.
3. Record the resolved APN in `parcel_chain.parcel_number` and note in
   `notes` which rung of the ladder resolved it; a repeated failure on a
   well-formed address is worth reporting as a tooling defect, not
   silently working around.

## Existing records: append vs update

Always check first: `POST /rpc/find_property` with the strongest identity
(APN + ZIP beats address beats coordinates). On a hit, carry the
`existing_property_id` and classify each fact:

- **Timeline facts** (sales, transfers, assessments, tax bills, unit
  rents, listings, valuations, ownership periods): new dates/periods
  append as new event rows. Exact duplicates (same date and amount) are
  skipped; near-misses (same date, different value) are flagged in
  `notes`, never overwritten.
- **Identity/physical facts** (details, zoning, name, size): filling a
  NULL is always fine; changing an existing value requires a
  higher-trust source than what's stored, and goes in the payload's
  `updates` with the source — otherwise keep the existing value.

## Data discipline

- Record only what a source states; unknown fields omitted, never
  guessed. No source for a section → omit the section.
- Prefer typed columns (zoning, land_use, frontage, flood_zone, etc. are
  columns on the details tables) — never invent `metrics` keys.
- Money as quoted; areas sq ft or m², never acres (`convert_measure`).
- Everything lands `verification_status: 'unverified'`.
- `source_urls`: ONLY pages a saved fact actually came from (or the
  shared document itself), each as
  `{"url": "...", "retrieved_on": "YYYY-MM-DD"}`. For local files use
  the filename as the `url`. A record whose sources can't be traced is
  a defect.

## Payload shape

One JSON object per property, no prose around it:

```json
{
  "existing_property_id": null,
  "role": "subject | sale_comp | rent_comp | listing | standalone",
  "address": {"street_number": "...", "street_name": "...", "street_suffix": "...",
              "street_post_directional": null, "locality": "...", "region": "..",
              "postal_code": "...", "lat": 0.0, "lon": 0.0},
  "property": {"name": "...", "property_type_code": "MF_MID"},
  "details": {"kind": "commercial_details", "fields": {}},
  "parcel_chain": {"county_fips": "...", "county_name": "...",
                   "parcel_number": "<raw as issued>",
                   "assessments": [], "tax_bills": []},
  "events": [{"table": "property_sales", "fields": {"sale_date": "...",
              "sale_price": 0, "sale_type": "arms_length",
              "source_url": "..."}}],
  "updates": {"details": {"zoning": {"value": "...", "source_url": "..."}}},
  "source_urls": [{"url": "...", "retrieved_on": "YYYY-MM-DD"}],
  "needs_research": false,
  "needs_public_records": false,
  "notes": "conflicts, low confidence, near-miss duplicates"
}
```

Omit `details`/`parcel_chain`/`updates` when nothing sourced them. Set
`needs_research: true` when only thin identity data exists and a web
research pass would materially complete the record. Set
`needs_public_records: true` when the rung-1 baseline (APN + assessment
+ owner of record) is missing or came from a lower rung — the
orchestrator closes it cheapest-door-first: the `assessor-lookup` MCP
inline when connected and covering the county, and a browser-capable
`assessor-fetcher` (one per county) only when the MCP is absent,
uncovered, or fails outright — an MCP success closes the flag even if
some of its fields are null. The rung-1 fragments merge into
the property's payload at the funnel, rung-1 facts winning.
