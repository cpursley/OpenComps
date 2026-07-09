# Schema inventory

SQL migrations live in `supabase/migrations/`, targeting PostgreSQL 17+ and
PostGIS 3.5+ (both bundled dev paths run PostgreSQL 18 + PostGIS 3.6).

## Tables

| Layer          | Tables                                                                                                                                                              |
|----------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Identity       | `properties`, `parcels`, `property_parcels`, `parcel_lineage`, `property_identifiers`, `jurisdictions`, `addresses`                                                 |
| Classification | `comp_types`, `property_types`, `property_type_mappings`, `classification_taxonomies`                                                                               |
| Provenance     | `data_providers`, `source_records`, `data_verifications`                                                                                                            |
| Reference data | `us_zips`, `reference_dataset_loads`                                                                                                                                |
| Physical       | `residential_details`, `commercial_details`, `land_details`, `structures`, `spaces`                                                                                 |
| Owners         | `owners`, `owner_contacts`, `owner_addresses`                                                                                                                       |
| Public records | `property_transfers`, `ownership_periods`, `ownership_interests`, `assessments`, `tax_bills`, `property_mortgages`                                                  |
| Comps          | `property_sales`, `property_leases`, `rent_escalations`, `lease_concessions`, `property_unit_rents`, `property_listings`, `valuations`, `income_expense_statements` |
| Workflow       | `comp_sets`, `comp_set_items`, `users` (minimal, auth-agnostic)                                                                                                     |
| Views          | `v_current_sources`, `v_current_ownership`, `v_property_sale_history`                                                                                               |

## Functions (RPCs)

Callable from SQL or over REST as `POST /rpc/<name>`. Spatial searches
return nearest-first with `dist_meters`; invalid arguments raise SQLSTATE
`22023`.

| Function             | Purpose                                                                                                                                      |
|----------------------|----------------------------------------------------------------------------------------------------------------------------------------------|
| `nearby_sales`       | Sale comps around a `lat`/`long` or ZIP centroid within `radius_m`                                                                           |
| `nearby_unit_rents`  | Unit rent comps, same anchoring                                                                                                              |
| `comps_for_property` | Subject-anchored sale comps with appraisal-style culling: recency vs `as_of`, arms-length by default, size/vintage brackets, type matching   |
| `find_property`      | Existence check before ingest — waterfall: normalized APN (ZIP-scoped to county) → address trigram → PostGIS proximity; rows say `matched_by` |
| `bulk_insert`        | Multi-row writes as `{"target": "<table>", "rows": [...]}` for REST clients that can only send JSON object bodies                            |
| `convert_area`       | `unit_system`-enum area conversion (sq ft ↔ m²); used internally by the comp search                                                          |
| `convert_measure`    | General converter — length `m`/`km`/`ft`/`yd`/`mi`, area `sqm`/`sqft`/`acre`/`hectare`, rates `per_sqft` ↔ `per_sqm`                          |
