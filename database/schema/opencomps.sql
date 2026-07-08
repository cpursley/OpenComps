-- ============================================================================
-- OpenComps open-source property record & comp database schema
-- PostgreSQL 17+ / PostGIS 3.5+
-- ============================================================================
-- Design principles:
--   * properties.id (UUID) is the immutable spine. Parcel numbers,
--     UPIs, and vendor IDs are identifiers ABOUT a property, never its key
--     (APNs split, merge, renumber, and reformat).
--   * Public records are parcel-first: jurisdictions -> parcels -> assessments
--     and tax bills. Properties relate to parcels many-to-many over time.
--   * A comp is an EVENT (sale, lease, listing, rate observation), never a
--     property type. Recorded deed transfers are separate from market sale
--     comps: quitclaims live in property_transfers, not in the comp table.
--   * source_records are immutable, versioned, per-provider, per-record-kind
--     observations. Typed tables hold the reconciled queryable state.
--   * International-ready: ISO country codes, generic locality/region/
--     postal_code addressing, jurisdiction authorities per country.
--   * Temporal semantics: all (started_on, ended_on) pairs are [start, end)
--     -- ended_on is EXCLUSIVE (the transfer/change date), matching
--     PostgreSQL daterange defaults.
--   * Simple users only. Auth, multi-tenancy, billing, and other product
--     concerns belong in downstream layers that build on this schema.
-- ============================================================================

BEGIN;

-- ============================================================================
-- EXTENSIONS
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ============================================================================
-- ENUMS
-- ============================================================================
-- How a provider's data arrives
CREATE TYPE provider_kind AS ENUM ('api', 'bulk_feed', 'user_upload', 'manual');

-- Review workflow state of any fact; constraints treat 'verified' as curated
CREATE TYPE verification_status AS ENUM (
    'unverified', 'pending_review', 'verified', 'disputed', 'rejected'
);

-- Coarse reviewer confidence on a verification
CREATE TYPE confidence_level AS ENUM ('high', 'medium', 'low');

-- Legal form of an owning entity
CREATE TYPE owner_kind AS ENUM (
    'individual', 'llc', 'corporation', 'partnership', 'trust', 'estate',
    'government', 'nonprofit', 'reit', 'fund', 'other'
);

-- Recorded loan lifecycle
CREATE TYPE mortgage_status AS ENUM (
    'active', 'satisfied', 'assigned', 'foreclosure', 'released', 'unknown'
);

-- Market classification of a sale comp; comp screens filter 'arms_length'
CREATE TYPE sale_type AS ENUM (
    'arms_length', 'reo', 'short_sale', 'auction', 'related_party',
    'portfolio', 'partial_interest', 'land_contract', 'new_construction',
    'other'
);

-- Expense responsibility structure of a lease
CREATE TYPE lease_type AS ENUM (
    'gross', 'modified_gross', 'triple_net', 'double_net', 'single_net',
    'absolute_net', 'percentage', 'ground', 'residential', 'other'
);

-- What kind of deal the lease was
CREATE TYPE lease_transaction_type AS ENUM (
    'new_lease', 'renewal', 'expansion', 'relocation', 'blend_extend',
    'sublease', 'other'
);

-- (Money fields follow the same per-row pattern as unit_system: each
-- money-bearing table carries a `currency` CHAR(3) ISO 4217 code, DEFAULT
-- 'USD'. Amounts are stored as quoted in their market, never converted.)

-- Measurement system for a row's area/length/per-area fields:
-- 'imperial' = square feet, feet, $/SF; 'metric' = square meters, meters, $/m².
-- Large-lot display units (acres, hectares) are exact conversions, done in
-- the app layer.
CREATE TYPE unit_system AS ENUM ('imperial', 'metric');

-- How a rent figure is quoted; per-area units come from the row's unit_system.
-- 'daily' supports nightly rate observations (hotel ADR, short-term rentals).
CREATE TYPE rent_period AS ENUM (
    'daily', 'monthly', 'annual', 'per_area_annual', 'per_area_monthly'
);

-- How rent increases over a lease term
CREATE TYPE escalation_type AS ENUM (
    'fixed_amount', 'fixed_percent', 'cpi', 'step_schedule',
    'fair_market_value', 'none'
);

-- Landlord incentives granted in a lease deal
CREATE TYPE concession_type AS ENUM (
    'free_rent', 'ti_allowance', 'moving_allowance', 'reduced_rent',
    'lease_buyout', 'parking', 'signage', 'other'
);

-- What a surveyed unit rate is quoted per (bed, key, slip, pad, ...)
CREATE TYPE unit_rate_basis AS ENUM (
    'per_unit', 'per_bed', 'per_area', 'per_room', 'per_key', 'per_slip',
    'per_stall', 'per_pad', 'other'
);

-- Whether a surveyed rate is advertised, net of concessions, or signed
CREATE TYPE rate_type AS ENUM ('asking', 'effective', 'contract');

-- Which market a listing is on
CREATE TYPE listing_kind AS ENUM ('for_sale', 'for_lease');

-- Listing lifecycle
CREATE TYPE listing_status AS ENUM (
    'active', 'pending', 'sold', 'leased', 'withdrawn', 'expired'
);

-- Who/what produced a value OPINION (appraisals, AVMs, BPOs, user
-- estimates). Official tax-roll values are NOT opinions and live in
-- assessments; a unified value timeline is a UNION query across both.
CREATE TYPE valuation_kind AS ENUM (
    'appraisal', 'avm', 'bpo', 'broker_opinion', 'internal'
);

-- Why one parcel succeeded another
CREATE TYPE parcel_lineage_kind AS ENUM ('split', 'merge', 'renumber');

-- Which comp event table a polymorphic comp_id points at
CREATE TYPE comp_kind AS ENUM ('sale', 'lease', 'listing', 'unit_rent');

-- Who put a comp into a comp set
CREATE TYPE comp_selection_source AS ENUM ('user', 'ai_suggested', 'imported');

-- Licensing class of contact data; 'licensed' must not reach public surfaces
CREATE TYPE data_visibility AS ENUM ('public_record', 'licensed', 'private');

-- ============================================================================
-- 1. USERS (deliberately minimal; real auth lives in the product layer)
-- ============================================================================
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email CITEXT NOT NULL UNIQUE,
    display_name TEXT,
    metadata JSONB NOT NULL DEFAULT '{}',
    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 2. JURISDICTIONS (international authority model)
-- The bodies that assign parcel numbers, assess, and tax. US counties,
-- UK local authorities, German Gemeinden, overlapping taxing districts.
-- ============================================================================
CREATE TABLE jurisdictions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    country CHAR(2) NOT NULL,           -- ISO 3166-1 alpha-2
    region TEXT,                        -- state/province/land code ('GA', 'ON')
    name TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN (
        'county', 'municipality', 'taxing_district', 'assessor',
        'school_district', 'land_registry', 'other'
    )),
    authority_code TEXT,                -- US: FIPS/GEOID; other countries: theirs
    parent_id UUID REFERENCES jurisdictions(id),
    geom GEOMETRY(MULTIPOLYGON, 4326),
    metadata JSONB NOT NULL DEFAULT '{}',

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX jurisdictions_country_kind_code_index
    ON jurisdictions (country, kind, authority_code)
    WHERE authority_code IS NOT NULL;
CREATE INDEX jurisdictions_geom_index ON jurisdictions USING GIST (geom);
CREATE INDEX jurisdictions_parent_id_index ON jurisdictions (parent_id);

-- ============================================================================
-- 2b. US ZIP GEODATA (reference data; loaded by scripts/load_us_zips.sh)
-- Source: SimpleMaps US Zips (free tier). Production use requires a link
-- back to https://simplemaps.com/data/us-zips
--
-- Postal systems differ per country, so geodata reference tables are
-- per-country by design: us_zips now; ca_postal_codes, uk_postcodes, etc.
-- can follow the same pattern later without forcing one global shape.
--
-- Relationships (soft joins; reference data is replaceable, so no hard FKs):
--   addresses(country='US').postal_code  -> us_zips.zip
--   us_zips.county_fips                  -> jurisdictions.authority_code
--                                           WHERE kind='county' AND country='US'
-- location is the ZIP centroid (the free dataset is points, not polygons),
-- which supports radius search, nearest-zip, and distance ordering:
--   SELECT zip FROM us_zips
--   WHERE ST_DWithin(location, $point, 16000)      -- within ~10 miles
--   ORDER BY location <-> $point;
-- ============================================================================
CREATE TABLE us_zips (
    zip TEXT PRIMARY KEY,               -- 5 chars, leading zeros preserved

    city TEXT NOT NULL,                 -- primary USPS city name
    state_id TEXT NOT NULL,             -- 'GA', 'PR', 'DC'
    state_name TEXT,

    is_zcta BOOLEAN,                    -- Census ZCTA (has geographic area)
    parent_zcta TEXT,                   -- for non-ZCTA zips, the containing ZCTA

    population INTEGER,
    density NUMERIC(10,1),              -- people per sq km

    county_fips TEXT,                   -- primary county
    county_name TEXT,
    county_weights JSONB,               -- {"13121": 91.4, ...} population share
    county_fips_all TEXT[] NOT NULL DEFAULT '{}',
    county_names_all TEXT[] NOT NULL DEFAULT '{}',

    is_imprecise BOOLEAN NOT NULL DEFAULT FALSE,
    is_military BOOLEAN NOT NULL DEFAULT FALSE,
    timezone TEXT,

    location GEOGRAPHY(POINT, 4326) NOT NULL,

    CONSTRAINT us_zips_zip_format CHECK (zip ~ '^[0-9]{5}$'),
    CONSTRAINT us_zips_state_id_format CHECK (state_id ~ '^[A-Z]{2}$'),
    CONSTRAINT us_zips_population_nonnegative
        CHECK (population IS NULL OR population >= 0),
    CONSTRAINT us_zips_density_nonnegative
        CHECK (density IS NULL OR density >= 0)
);

CREATE INDEX us_zips_location_index ON us_zips USING GIST (location);
CREATE INDEX us_zips_state_city_index ON us_zips (state_id, city);
CREATE INDEX us_zips_county_fips_index ON us_zips (county_fips);
CREATE INDEX us_zips_county_fips_all_index ON us_zips USING GIN (county_fips_all);

-- ============================================================================
-- 2c. REFERENCE DATASET LOAD TRACKING
-- Append-only audit of bulk reference-data loads (us_zips today; other
-- per-country geodata tables later). Snapshot tables are truncated and
-- reloaded wholesale, so the provider release version and load time are
-- attributes of the LOAD, not of each row. The currently loaded version of
-- a dataset is its most recent load:
--   SELECT DISTINCT ON (dataset) dataset, version, loaded_at
--   FROM reference_dataset_loads ORDER BY dataset, loaded_at DESC;
-- ============================================================================
CREATE TABLE reference_dataset_loads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    dataset TEXT NOT NULL,              -- 'us_zips'; later 'ca_postal_codes', ...
    version TEXT,                       -- provider release, e.g. '1.95.1'
    source_url TEXT,                    -- download URL or local file loaded
    row_count INTEGER NOT NULL CHECK (row_count >= 0),
    metadata JSONB NOT NULL DEFAULT '{}',

    loaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX reference_dataset_loads_dataset_index
    ON reference_dataset_loads (dataset, loaded_at DESC);

-- ============================================================================
-- 3. ADDRESSES (shared, deduplicated, international)
-- ============================================================================
CREATE TABLE addresses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    country CHAR(2) NOT NULL DEFAULT 'US',   -- ISO 3166-1 alpha-2

    -- structured components (generic; US and most Western formats map cleanly)
    street_number TEXT,
    street_pre_directional TEXT,
    street_name TEXT,
    street_suffix TEXT,
    street_post_directional TEXT,
    unit_type TEXT,
    unit_number TEXT,
    sublocality TEXT,                   -- district/borough/neighborhood
    locality TEXT,                      -- city/town
    region TEXT,                        -- state/province/prefecture
    postal_code TEXT,
    postal_code_suffix TEXT,            -- US ZIP+4 etc.
    admin_area TEXT,                    -- county / local admin area
    -- country-specific extras that don't fit the generic components
    components JSONB NOT NULL DEFAULT '{}',

    -- flat, whitespace-normalized rendering of the components, for
    -- trigram search and display
    full_address TEXT GENERATED ALWAYS AS (
        TRIM(BOTH ' ' FROM REGEXP_REPLACE(
            COALESCE(street_number, '') || ' ' ||
            COALESCE(street_pre_directional, '') || ' ' ||
            COALESCE(street_name, '') || ' ' ||
            COALESCE(street_suffix, '') || ' ' ||
            COALESCE(street_post_directional, '') || ' ' ||
            COALESCE(unit_type, '') || ' ' ||
            COALESCE(unit_number, '') || ' ' ||
            COALESCE(locality, '') || ' ' ||
            COALESCE(region, '') || ' ' ||
            COALESCE(postal_code, '') || ' ' ||
            COALESCE(country, ''),
            '\s+', ' ', 'g'
        ))
    ) STORED,

    -- app-computed normalized hash for dedup (includes country)
    address_hash TEXT NOT NULL UNIQUE,
    location GEOGRAPHY(POINT, 4326),

    is_standardized BOOLEAN NOT NULL DEFAULT FALSE,
    standardization_source TEXT,        -- which service standardized it
    standardized_at TIMESTAMPTZ,
    metadata JSONB NOT NULL DEFAULT '{}',

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT addresses_country_format CHECK (country ~ '^[A-Z]{2}$')
);

CREATE INDEX addresses_full_trgm_index
    ON addresses USING GIN (full_address gin_trgm_ops);
CREATE INDEX addresses_location_index ON addresses USING GIST (location);
CREATE INDEX addresses_locality_index ON addresses (country, region, locality);
CREATE INDEX addresses_postal_index ON addresses (country, postal_code);

-- ============================================================================
-- 4. CLASSIFICATION (DB-driven, multi-taxonomy)
-- ============================================================================
CREATE TABLE classification_taxonomies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE,          -- 'uad_36', 'pucs', 'lbcs', ...
    name TEXT NOT NULL,
    version TEXT,
    effective_date DATE,
    documentation_url TEXT,
    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE comp_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE,          -- 'residential', 'office', 'hospitality'
    name TEXT NOT NULL,
    description TEXT,

    required_fields TEXT[] NOT NULL DEFAULT '{}',
    optional_fields TEXT[] NOT NULL DEFAULT '{}',
    field_definitions JSONB NOT NULL DEFAULT '{}',

    primary_unit TEXT NOT NULL,
    secondary_units TEXT[] NOT NULL DEFAULT '{}',

    display_order INTEGER,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE property_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE,          -- 'RES_SFD', 'COM_OFF_HI', 'HOS_HTL_FS'
    name TEXT NOT NULL,
    description TEXT,

    parent_id UUID REFERENCES property_types(id) ON DELETE SET NULL,
    comp_type_id UUID NOT NULL REFERENCES comp_types(id),

    icon TEXT,
    display_order INTEGER,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX property_types_comp_type_id_index ON property_types (comp_type_id);
CREATE INDEX property_types_parent_id_index ON property_types (parent_id);

CREATE TABLE property_type_mappings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_type_id UUID NOT NULL REFERENCES property_types(id) ON DELETE CASCADE,
    taxonomy_id UUID NOT NULL REFERENCES classification_taxonomies(id) ON DELETE CASCADE,
    external_code TEXT NOT NULL,
    external_label TEXT,
    metadata JSONB NOT NULL DEFAULT '{}',

    UNIQUE (property_type_id, taxonomy_id, external_code)
);

CREATE INDEX property_type_mappings_taxonomy_lookup
    ON property_type_mappings (taxonomy_id, external_code);

-- ============================================================================
-- 5. DATA PROVIDERS
-- ============================================================================
CREATE TABLE data_providers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    -- open vocabulary: 'public_records', 'mls', 'parcel_geometry',
    -- 'valuation', 'ownership', 'user_contributed', ...
    category TEXT NOT NULL,
    kind provider_kind NOT NULL,

    api_base_url TEXT,
    documentation_url TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    metadata JSONB NOT NULL DEFAULT '{}',

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 6. PROPERTIES (immutable UUID spine) & PARCELS (public-record identity)
-- ============================================================================
CREATE TABLE properties (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    name TEXT,                          -- 'Peachtree Tower' (CRE assets)
    property_type_id UUID REFERENCES property_types(id),
    situs_address_id UUID REFERENCES addresses(id),
    location GEOGRAPHY(POINT, 4326),

    metadata JSONB NOT NULL DEFAULT '{}',

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX properties_location_index ON properties USING GIST (location);
CREATE INDEX properties_property_type_id_index ON properties (property_type_id);
CREATE INDEX properties_situs_address_id_index ON properties (situs_address_id);

-- Jurisdictional parcel records. Parcels retire on split/merge/renumber;
-- the property UUID persists across parcel churn.
CREATE TABLE parcels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    jurisdiction_id UUID NOT NULL REFERENCES jurisdictions(id),

    -- denormalized from jurisdiction for the generated UPI
    country CHAR(2) NOT NULL,
    authority_code TEXT NOT NULL,       -- US: county GEOID/FIPS

    parcel_number TEXT NOT NULL,        -- RAW, exactly as issued (UPI v2 rule)
    normalized_parcel_number TEXT,      -- app-normalized, for matching only
    unit_designator TEXT,               -- condo/unit sub-parcel

    -- RESO Universal Parcel Identifier v2.0 (interchange ID, not a key)
    reso_upi TEXT GENERATED ALWAYS AS (
        'urn:reso:upi:2.0:' || country || ':' || authority_code || ':' ||
        parcel_number ||
        CASE WHEN unit_designator IS NOT NULL
             THEN ':sub:' || unit_designator ELSE '' END
    ) STORED,

    legal_description TEXT,
    unit_system unit_system NOT NULL DEFAULT 'imperial',
    land_area NUMERIC(14,2),
    geom GEOMETRY(MULTIPOLYGON, 4326),

    retired_on DATE,                    -- set when split/merged/renumbered
    metadata JSONB NOT NULL DEFAULT '{}',

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- one ACTIVE parcel per number+unit per jurisdiction (retired numbers may recur)
CREATE UNIQUE INDEX parcels_active_number_index
    ON parcels (jurisdiction_id, parcel_number, unit_designator)
    NULLS NOT DISTINCT
    WHERE retired_on IS NULL;
CREATE UNIQUE INDEX parcels_reso_upi_index
    ON parcels (reso_upi) WHERE retired_on IS NULL;
CREATE INDEX parcels_normalized_index
    ON parcels (jurisdiction_id, normalized_parcel_number);
CREATE INDEX parcels_geom_index ON parcels USING GIST (geom);

-- Property <-> parcel over time: multi-parcel assets, condo master parcels,
-- splits/merges. [started_on, ended_on) -- ended_on exclusive.
CREATE TABLE property_parcels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
    parcel_id UUID NOT NULL REFERENCES parcels(id),

    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    started_on DATE,
    ended_on DATE,
    CHECK (ended_on IS NULL OR started_on IS NULL OR ended_on > started_on),

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (property_id, parcel_id)
);

CREATE INDEX property_parcels_parcel_id_index ON property_parcels (parcel_id);
CREATE UNIQUE INDEX property_parcels_one_current_primary_index
    ON property_parcels (property_id)
    WHERE is_primary = TRUE AND ended_on IS NULL;

CREATE TABLE parcel_lineage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    predecessor_parcel_id UUID NOT NULL REFERENCES parcels(id),
    successor_parcel_id UUID NOT NULL REFERENCES parcels(id),
    kind parcel_lineage_kind NOT NULL,
    effective_on DATE,
    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (predecessor_parcel_id, successor_parcel_id),
    CHECK (predecessor_parcel_id <> successor_parcel_id)
);

CREATE INDEX parcel_lineage_successor_index
    ON parcel_lineage (successor_parcel_id);

-- Namespaced external identifiers: vendor property IDs, MLS listing keys,
-- alternate parcel IDs. namespace scopes the value (provider code,
-- jurisdiction code, MLS system); APNs and MLS keys collide across systems
-- without it.
CREATE TABLE property_identifiers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,

    scheme TEXT NOT NULL,               -- e.g. 'mls_listing_key', vendor ID schemes
    namespace TEXT NOT NULL DEFAULT '', -- e.g. MLS system code, jurisdiction code
    value TEXT NOT NULL,

    provider_id UUID REFERENCES data_providers(id),
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (scheme, namespace, value)
);

CREATE INDEX property_identifiers_property_id_index
    ON property_identifiers (property_id);
CREATE INDEX property_identifiers_provider_id_index
    ON property_identifiers (provider_id);

-- ============================================================================
-- 7. SOURCE RECORDS (immutable, versioned, per record kind)
-- A provider has MANY concurrent current records for one property: parcel,
-- assessment, tax bill, deed, owner, geometry. record_kind distinguishes them.
-- ============================================================================
CREATE TABLE source_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    provider_id UUID NOT NULL REFERENCES data_providers(id),
    record_kind TEXT NOT NULL,          -- 'property','parcel','assessment',
                                        -- 'tax_bill','deed','owner','listing',
                                        -- 'geometry','avm','contact', ...
    dataset TEXT,                       -- provider-side dataset/feed name
    jurisdiction_id UUID REFERENCES jurisdictions(id),

    property_id UUID REFERENCES properties(id),   -- NULL until matched
    parcel_id UUID REFERENCES parcels(id),
    provider_record_id TEXT,

    version INTEGER NOT NULL DEFAULT 1,
    is_current BOOLEAN NOT NULL DEFAULT TRUE,
    superseded_by_id UUID REFERENCES source_records(id),
    valid_from TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    valid_to TIMESTAMPTZ,

    raw_payload JSONB NOT NULL,
    normalized_fields JSONB NOT NULL DEFAULT '{}',

    -- open vocabulary: 'exact_parcel', 'address_geocode', 'fuzzy_address',
    -- 'upi_match', 'manual', 'mls_match', ...
    match_method TEXT,
    match_confidence NUMERIC(3,2) CHECK (match_confidence BETWEEN 0.00 AND 1.00),
    completeness_score INTEGER CHECK (completeness_score BETWEEN 0 AND 100),
    confidence_score INTEGER CHECK (confidence_score BETWEEN 0 AND 100),

    changed_fields TEXT[] NOT NULL DEFAULT '{}',
    change_summary JSONB,

    fetched_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    provider_timestamp TIMESTAMPTZ,
    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- one current VERSION per provider record (per kind); multiple kinds coexist
CREATE UNIQUE INDEX source_records_current_index
    ON source_records (provider_id, record_kind, provider_record_id)
    WHERE is_current = TRUE AND provider_record_id IS NOT NULL;

CREATE INDEX source_records_property_index
    ON source_records (property_id, provider_id, record_kind)
    WHERE is_current = TRUE;
CREATE INDEX source_records_parcel_id_index ON source_records (parcel_id);
CREATE INDEX source_records_fetched_at_index ON source_records (fetched_at DESC);
CREATE INDEX source_records_normalized_fields_index
    ON source_records USING GIN (normalized_fields jsonb_path_ops);

-- ============================================================================
-- 8. PHYSICAL ASSET MODEL (typed current-state details)
-- Current reconciled facts as typed columns. History lives in source_records;
-- as-of-event state is captured on the comp events themselves.
-- ============================================================================
CREATE TABLE residential_details (
    property_id UUID PRIMARY KEY REFERENCES properties(id) ON DELETE CASCADE,

    unit_system unit_system NOT NULL DEFAULT 'imperial',
    gla INTEGER CHECK (gla > 0),        -- gross living area
    bedrooms INTEGER,
    bathrooms NUMERIC(4,1),             -- total as quoted (2.5); source data
    bathrooms_full INTEGER,             --   often gives only one form, so both
    bathrooms_half INTEGER,             --   the total and the split are kept
    total_rooms INTEGER,
    unit_count INTEGER,                 -- 2-4 unit properties (duplex/triplex)
    stories NUMERIC(4,1),
    attachment TEXT,                    -- 'detached', 'attached', 'townhouse', ...
    year_built INTEGER CHECK (year_built BETWEEN 1600 AND 2200),
    year_renovated INTEGER,

    basement_area INTEGER,
    basement_finished_area INTEGER,
    garage_spaces INTEGER,
    carport_spaces INTEGER,
    heating_type TEXT,                  -- 'forced_air', 'heat_pump', ...
    cooling_type TEXT,                  -- 'central', 'none', ...
    fireplaces INTEGER,
    has_pool BOOLEAN,
    has_adu BOOLEAN,

    lot_size NUMERIC(14,2),
    style TEXT,
    construction TEXT,
    condition_rating TEXT,              -- UAD C1-C6
    quality_rating TEXT,                -- UAD Q1-Q6

    -- overflow + user-defined fields (roof, exterior, septic/well, garage
    -- type, basement exposure, ...): anything not screened on stays here
    extras JSONB NOT NULL DEFAULT '{}',

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT residential_details_nonnegative_counts CHECK (
        (bedrooms IS NULL OR bedrooms >= 0)
        AND (bathrooms IS NULL OR bathrooms >= 0)
        AND (bathrooms_full IS NULL OR bathrooms_full >= 0)
        AND (bathrooms_half IS NULL OR bathrooms_half >= 0)
        AND (total_rooms IS NULL OR total_rooms >= 0)
        AND (unit_count IS NULL OR unit_count > 0)
        AND (stories IS NULL OR stories > 0)
        AND (basement_area IS NULL OR basement_area >= 0)
        AND (basement_finished_area IS NULL OR basement_finished_area >= 0)
        AND (garage_spaces IS NULL OR garage_spaces >= 0)
        AND (carport_spaces IS NULL OR carport_spaces >= 0)
        AND (fireplaces IS NULL OR fireplaces >= 0)
        AND (lot_size IS NULL OR lot_size >= 0)
    ),

    CONSTRAINT residential_details_renovation_after_build CHECK (
        year_renovated IS NULL OR year_built IS NULL
        OR year_renovated >= year_built
    )
);

CREATE TABLE commercial_details (
    property_id UUID PRIMARY KEY REFERENCES properties(id) ON DELETE CASCADE,

    unit_system unit_system NOT NULL DEFAULT 'imperial',
    rentable_building_area INTEGER CHECK (rentable_building_area > 0),
    gross_building_area INTEGER,
    land_area NUMERIC(14,2),
    stories INTEGER,
    year_built INTEGER CHECK (year_built BETWEEN 1600 AND 2200),
    year_renovated INTEGER,

    unit_count INTEGER,
    occupancy_pct NUMERIC(5,2) CHECK (occupancy_pct BETWEEN 0 AND 100),
    parking_spaces INTEGER,
    parking_ratio NUMERIC(6,2),        -- spaces per 1,000 area units

    clear_height NUMERIC(5,1),
    dock_doors INTEGER,
    drive_in_doors INTEGER,
    has_sprinkler BOOLEAN,

    tenancy TEXT,                       -- 'single_tenant', 'multi_tenant'
    construction_class TEXT,
    building_class TEXT,
    zoning TEXT,
    submarket TEXT,

    -- overflow + user-defined fields (power, rail access, office buildout
    -- pct, floor plate, FAR, HVAC, ...): anything not screened on stays here
    extras JSONB NOT NULL DEFAULT '{}',

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT commercial_details_nonnegative_counts CHECK (
        (gross_building_area IS NULL OR gross_building_area > 0)
        AND (land_area IS NULL OR land_area >= 0)
        AND (stories IS NULL OR stories > 0)
        AND (unit_count IS NULL OR unit_count >= 0)
        AND (parking_spaces IS NULL OR parking_spaces >= 0)
        AND (parking_ratio IS NULL OR parking_ratio >= 0)
        AND (clear_height IS NULL OR clear_height > 0)
        AND (dock_doors IS NULL OR dock_doors >= 0)
        AND (drive_in_doors IS NULL OR drive_in_doors >= 0)
    ),

    CONSTRAINT commercial_details_renovation_after_build CHECK (
        year_renovated IS NULL OR year_built IS NULL
        OR year_renovated >= year_built
    )
);

CREATE TABLE land_details (
    property_id UUID PRIMARY KEY REFERENCES properties(id) ON DELETE CASCADE,

    unit_system unit_system NOT NULL DEFAULT 'imperial',
    lot_size NUMERIC(14,2),
    zoning TEXT,
    land_use TEXT,
    frontage NUMERIC(8,1),
    depth NUMERIC(8,1),
    topography TEXT,
    utilities TEXT[] NOT NULL DEFAULT '{}',
    flood_zone TEXT,
    entitlement_status TEXT,
    buildable_units INTEGER,
    is_corner BOOLEAN,

    -- overflow + user-defined fields (easements, wetlands, rail, shape,
    -- road access class, ...)
    extras JSONB NOT NULL DEFAULT '{}',

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Physical improvements on a property: office towers and apartment
-- buildings, but also barns, silos, detached garages, sheds, guest houses.
-- Agricultural and residential properties routinely have several.
CREATE TABLE structures (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,

    kind TEXT,                          -- 'building', 'barn', 'silo',
                                        -- 'detached_garage', 'shed',
                                        -- 'guest_house', ...
    name TEXT,                          -- 'North Tower', 'Main Barn'
    structure_number TEXT,
    unit_system unit_system NOT NULL DEFAULT 'imperial',
    gross_area INTEGER,
    rentable_area INTEGER,
    floors INTEGER,
    year_built INTEGER CHECK (year_built BETWEEN 1600 AND 2200),
    year_renovated INTEGER,
    construction_type TEXT,
    elevators INTEGER,
    metadata JSONB NOT NULL DEFAULT '{}',

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT structures_positive_dimensions CHECK (
        (gross_area IS NULL OR gross_area > 0)
        AND (rentable_area IS NULL OR rentable_area > 0)
        AND (floors IS NULL OR floors > 0)
        AND (elevators IS NULL OR elevators >= 0)
    ),

    CONSTRAINT structures_renovation_after_build CHECK (
        year_renovated IS NULL OR year_built IS NULL
        OR year_renovated >= year_built
    )
);

CREATE INDEX structures_property_id_index ON structures (property_id);

CREATE TABLE spaces (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
    structure_id UUID REFERENCES structures(id) ON DELETE SET NULL,

    space_identifier TEXT NOT NULL,
    floor_number INTEGER,
    space_use TEXT,
    unit_system unit_system NOT NULL DEFAULT 'imperial',
    rentable_area INTEGER,
    usable_area INTEGER,
    bedrooms INTEGER,
    bathrooms NUMERIC(4,1),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    metadata JSONB NOT NULL DEFAULT '{}',

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (property_id, space_identifier),
    CONSTRAINT spaces_positive_dimensions CHECK (
        (rentable_area IS NULL OR rentable_area > 0)
        AND (usable_area IS NULL OR usable_area > 0)
        AND (bedrooms IS NULL OR bedrooms >= 0)
        AND (bathrooms IS NULL OR bathrooms >= 0)
    )
);

CREATE INDEX spaces_structure_id_index ON spaces (structure_id);

-- ============================================================================
-- 9. OWNERS & CONTACT POINTS
-- ============================================================================
CREATE TABLE owners (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    name TEXT NOT NULL,
    normalized_name TEXT NOT NULL,
    kind owner_kind NOT NULL DEFAULT 'other',
    metadata JSONB NOT NULL DEFAULT '{}',

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX owners_normalized_name_index ON owners (normalized_name);
CREATE INDEX owners_name_trgm_index ON owners USING GIN (name gin_trgm_ops);

-- Contact points as rows. visibility marks licensing class: mailing addresses
-- are public record; phones/emails are typically licensed skip-trace data
-- and must not leak into public/community surfaces.
CREATE TABLE owner_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID NOT NULL REFERENCES owners(id) ON DELETE CASCADE,

    kind TEXT NOT NULL CHECK (kind IN ('phone', 'email', 'linkedin', 'other')),
    value TEXT NOT NULL,
    label TEXT,
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    do_not_contact BOOLEAN NOT NULL DEFAULT FALSE,
    visibility data_visibility NOT NULL DEFAULT 'licensed',
    confidence_score INTEGER CHECK (confidence_score BETWEEN 0 AND 100),

    verification_status verification_status NOT NULL DEFAULT 'unverified',
    verified_at TIMESTAMPTZ,
    source_record_id UUID REFERENCES source_records(id),

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (owner_id, kind, value)
);

CREATE INDEX owner_contacts_value_index ON owner_contacts (kind, value);
CREATE INDEX owner_contacts_source_record_id_index
    ON owner_contacts (source_record_id);

CREATE TABLE owner_addresses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID NOT NULL REFERENCES owners(id) ON DELETE CASCADE,
    address_id UUID NOT NULL REFERENCES addresses(id),

    kind TEXT NOT NULL DEFAULT 'mailing' CHECK (kind IN
        ('mailing', 'physical', 'registered_agent', 'previous', 'other')),
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    visibility data_visibility NOT NULL DEFAULT 'public_record',

    verification_status verification_status NOT NULL DEFAULT 'unverified',
    verified_at TIMESTAMPTZ,
    source_record_id UUID REFERENCES source_records(id),

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (owner_id, address_id, kind)
);

CREATE INDEX owner_addresses_address_id_index ON owner_addresses (address_id);
CREATE INDEX owner_addresses_source_record_id_index
    ON owner_addresses (source_record_id);

-- ============================================================================
-- 10. RECORDED TRANSFERS (ownership-chain events; NOT comps)
-- Every deed/instrument, market or not. Quitclaims, foreclosure transfers,
-- and intra-entity moves live HERE. Market transactions get a sale comp row
-- referencing the transfer.
-- ============================================================================
CREATE TABLE property_transfers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID NOT NULL REFERENCES properties(id),
    parcel_id UUID REFERENCES parcels(id),

    -- open vocabulary; instrument names vary by jurisdiction and country:
    -- 'warranty_deed', 'grant_deed', 'quitclaim', 'trustee_deed',
    -- 'foreclosure', 'tax_deed', 'gift_inheritance', 'intra_entity', ...
    transfer_kind TEXT NOT NULL,
    recorded_on DATE,
    effective_on DATE,
    currency CHAR(3) NOT NULL DEFAULT 'USD',  -- ISO 4217; applies to all money fields on the row
    consideration NUMERIC(14,2)         -- stated; $0/nominal for many deeds
        CHECK (consideration >= 0),
    document_number TEXT,
    book_page TEXT,

    grantor_name TEXT,
    grantee_name TEXT,
    grantor_owner_id UUID REFERENCES owners(id),
    grantee_owner_id UUID REFERENCES owners(id),

    source_record_id UUID REFERENCES source_records(id),
    verification_status verification_status NOT NULL DEFAULT 'unverified',
    metadata JSONB NOT NULL DEFAULT '{}',

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX property_transfers_property_index
    ON property_transfers (property_id, recorded_on DESC);
CREATE INDEX property_transfers_parcel_id_index
    ON property_transfers (parcel_id);
CREATE INDEX property_transfers_grantee_owner_id_index
    ON property_transfers (grantee_owner_id);
CREATE INDEX property_transfers_grantor_owner_id_index
    ON property_transfers (grantor_owner_id);
CREATE INDEX property_transfers_source_record_id_index
    ON property_transfers (source_record_id);

-- ============================================================================
-- 11. OWNERSHIP: PERIODS + INTERESTS
-- One ownership REGIME per property at a time (periods); the members of the
-- regime and their percentages are interests (TIC, JV partners).
-- [started_on, ended_on): ended_on is the disposing transfer date, exclusive.
-- ============================================================================
CREATE TABLE ownership_periods (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID NOT NULL REFERENCES properties(id),

    started_on DATE,
    ended_on DATE,
    CHECK (ended_on IS NULL OR started_on IS NULL OR ended_on > started_on),
    -- range form of the period for @> point-in-time and && overlap queries
    valid_period DATERANGE GENERATED ALWAYS AS
        (daterange(started_on, ended_on)) STORED,

    acquired_via_transfer_id UUID REFERENCES property_transfers(id),
    disposed_via_transfer_id UUID REFERENCES property_transfers(id),

    source_record_id UUID REFERENCES source_records(id),
    contributed_by_id UUID REFERENCES users(id),
    verification_status verification_status NOT NULL DEFAULT 'unverified',

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX ownership_periods_property_index
    ON ownership_periods (property_id, started_on DESC);
-- hot path: current regime lookups (NULL ended_on = current)
CREATE INDEX ownership_periods_current_index
    ON ownership_periods (property_id) WHERE ended_on IS NULL;
CREATE INDEX ownership_periods_period_index
    ON ownership_periods USING GIST (property_id, valid_period);
CREATE INDEX ownership_periods_source_record_id_index
    ON ownership_periods (source_record_id);
-- The CURATED timeline cannot have two overlapping regimes on one property;
-- raw/unverified imports may (reconciliation is a pipeline job, not an
-- ingest-time constraint violation).
ALTER TABLE ownership_periods ADD CONSTRAINT ownership_periods_no_verified_overlap
    EXCLUDE USING GIST (property_id WITH =, valid_period WITH &&)
    WHERE (verification_status = 'verified');

CREATE TABLE ownership_interests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ownership_period_id UUID NOT NULL
        REFERENCES ownership_periods(id) ON DELETE CASCADE,
    owner_id UUID NOT NULL REFERENCES owners(id),

    ownership_pct NUMERIC(6,3)
        CHECK (ownership_pct > 0 AND ownership_pct <= 100),
    vesting TEXT,                       -- 'joint tenants', 'tenants in common'
    role TEXT,                          -- 'owner', 'trustee', 'gp', 'lp'
    is_owner_occupied BOOLEAN,

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (ownership_period_id, owner_id)
);

CREATE INDEX ownership_interests_owner_id_index
    ON ownership_interests (owner_id);

-- ============================================================================
-- 12. ASSESSMENTS & TAX BILLS (parcel-first, jurisdiction-aware)
-- Multiple rolls per year (original/corrected/appeal), multiple overlapping
-- taxing jurisdictions, and separate billing.
-- ============================================================================
CREATE TABLE assessments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parcel_id UUID NOT NULL REFERENCES parcels(id),
    jurisdiction_id UUID NOT NULL REFERENCES jurisdictions(id),

    tax_year INTEGER NOT NULL CHECK (tax_year BETWEEN 1800 AND 2200),
    -- open vocabulary; roll names vary by jurisdiction: 'original',
    -- 'corrected', 'appeal', 'supplemental', 'tentative', 'final', ...
    roll_type TEXT NOT NULL DEFAULT 'original',

    currency CHAR(3) NOT NULL DEFAULT 'USD',  -- ISO 4217; applies to all money fields on the row
    assessed_land NUMERIC(14,2),
    assessed_improvements NUMERIC(14,2),
    assessed_total NUMERIC(14,2),
    market_value NUMERIC(14,2),
    taxable_value NUMERIC(14,2),
    exemptions JSONB NOT NULL DEFAULT '[]',
    metadata JSONB NOT NULL DEFAULT '{}',

    source_record_id UUID REFERENCES source_records(id),
    verification_status verification_status NOT NULL DEFAULT 'unverified',

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (parcel_id, jurisdiction_id, tax_year, roll_type),

    CONSTRAINT assessments_nonnegative_amounts CHECK (
        (assessed_land IS NULL OR assessed_land >= 0)
        AND (assessed_improvements IS NULL OR assessed_improvements >= 0)
        AND (assessed_total IS NULL OR assessed_total >= 0)
        AND (market_value IS NULL OR market_value >= 0)
        AND (taxable_value IS NULL OR taxable_value >= 0)
    )
);

CREATE INDEX assessments_year_index ON assessments (tax_year);
CREATE INDEX assessments_jurisdiction_id_index ON assessments (jurisdiction_id);
CREATE INDEX assessments_source_record_id_index ON assessments (source_record_id);

CREATE TABLE tax_bills (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parcel_id UUID NOT NULL REFERENCES parcels(id),
    jurisdiction_id UUID NOT NULL REFERENCES jurisdictions(id),

    tax_year INTEGER NOT NULL CHECK (tax_year BETWEEN 1800 AND 2200),
    bill_number TEXT,

    currency CHAR(3) NOT NULL DEFAULT 'USD',  -- ISO 4217; applies to all money fields on the row
    amount_billed NUMERIC(14,2),
    amount_paid NUMERIC(14,2),
    is_delinquent BOOLEAN NOT NULL DEFAULT FALSE,
    delinquent_amount NUMERIC(14,2),
    due_dates JSONB NOT NULL DEFAULT '[]',      -- installments
    line_items JSONB NOT NULL DEFAULT '[]',     -- levies/millage breakdown

    source_record_id UUID REFERENCES source_records(id),

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- one bill per parcel/jurisdiction/year (+number); NULLS NOT DISTINCT
    -- so an unnumbered bill can't be inserted twice
    UNIQUE NULLS NOT DISTINCT (parcel_id, jurisdiction_id, tax_year, bill_number),

    CONSTRAINT tax_bills_nonnegative_amounts CHECK (
        (amount_billed IS NULL OR amount_billed >= 0)
        AND (amount_paid IS NULL OR amount_paid >= 0)
        AND (delinquent_amount IS NULL OR delinquent_amount >= 0)
    )
);

CREATE INDEX tax_bills_delinquent_index
    ON tax_bills (parcel_id) WHERE is_delinquent = TRUE;
CREATE INDEX tax_bills_source_record_id_index ON tax_bills (source_record_id);

-- ============================================================================
-- 13. DEBT (recorded mortgages / deeds of trust)
-- ============================================================================
CREATE TABLE property_mortgages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID NOT NULL REFERENCES properties(id),
    parcel_id UUID REFERENCES parcels(id),

    recording_date DATE,
    document_number TEXT,
    currency CHAR(3) NOT NULL DEFAULT 'USD',  -- ISO 4217; applies to all money fields on the row
    loan_amount NUMERIC(14,2) CHECK (loan_amount >= 0),
    lender_name TEXT,
    borrower_owner_id UUID REFERENCES owners(id),

    loan_type TEXT,
    interest_rate NUMERIC(6,3) CHECK (interest_rate >= 0),
    is_variable_rate BOOLEAN,
    term_months INTEGER CHECK (term_months > 0),
    maturity_date DATE,
    lien_position INTEGER CHECK (lien_position >= 1),

    status mortgage_status NOT NULL DEFAULT 'unknown',
    satisfied_on DATE,

    related_transfer_id UUID REFERENCES property_transfers(id),
    metadata JSONB NOT NULL DEFAULT '{}',

    source_record_id UUID REFERENCES source_records(id),
    verification_status verification_status NOT NULL DEFAULT 'unverified',

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX property_mortgages_property_index
    ON property_mortgages (property_id, recording_date DESC);
CREATE INDEX property_mortgages_active_index
    ON property_mortgages (property_id) WHERE status = 'active';
CREATE INDEX property_mortgages_maturity_index
    ON property_mortgages (maturity_date) WHERE status = 'active';
CREATE INDEX property_mortgages_borrower_owner_id_index
    ON property_mortgages (borrower_owner_id);
CREATE INDEX property_mortgages_source_record_id_index
    ON property_mortgages (source_record_id);

-- ============================================================================
-- 14. COMP EVENTS (market observations -- the "Comps" in OpenComps)
-- Headline financials are typed columns (the professional query surface);
-- `metrics` JSONB carries only the asset-class long tail defined by
-- comp_types.field_definitions. Hot residual JSONB numerics should get
-- expression indexes, e.g.:
--   CREATE INDEX ... ON property_sales ((( metrics->>'revpar')::numeric));
-- ============================================================================
CREATE TABLE property_sales (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID NOT NULL REFERENCES properties(id),
    transfer_id UUID REFERENCES property_transfers(id),  -- the recorded deed

    comp_type_id UUID REFERENCES comp_types(id),

    sale_date DATE NOT NULL,
    currency CHAR(3) NOT NULL DEFAULT 'USD',  -- ISO 4217; applies to all money fields on the row
    sale_price NUMERIC(14,2) CHECK (sale_price >= 0),
    sale_type sale_type NOT NULL DEFAULT 'arms_length',

    buyer_name TEXT,
    seller_name TEXT,
    buyer_type TEXT,
    seller_type TEXT,
    buyer_broker TEXT,
    seller_broker TEXT,

    financing TEXT,
    concessions_amount NUMERIC(14,2),

    unit_system unit_system NOT NULL DEFAULT 'imperial',
    price_per_area NUMERIC(10,2),
    cap_rate NUMERIC(5,2) CHECK (cap_rate BETWEEN 0 AND 100),
    noi NUMERIC(14,2),
    noi_per_area NUMERIC(10,2),
    opex NUMERIC(14,2),
    opex_per_area NUMERIC(10,2),
    occupancy_at_sale_pct NUMERIC(5,2)
        CHECK (occupancy_at_sale_pct BETWEEN 0 AND 100),

    metrics JSONB NOT NULL DEFAULT '{}',

    source_record_id UUID REFERENCES source_records(id),
    contributed_by_id UUID REFERENCES users(id),
    verification_status verification_status NOT NULL DEFAULT 'unverified',

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT property_sales_nonnegative_amounts CHECK (
        (concessions_amount IS NULL OR concessions_amount >= 0)
        AND (price_per_area IS NULL OR price_per_area >= 0)
        AND (noi_per_area IS NULL OR noi_per_area >= 0)
        AND (opex IS NULL OR opex >= 0)
        AND (opex_per_area IS NULL OR opex_per_area >= 0)
    )
);

CREATE INDEX property_sales_property_date_index
    ON property_sales (property_id, sale_date DESC);
CREATE INDEX property_sales_comp_type_id_index ON property_sales (comp_type_id);
CREATE INDEX property_sales_transfer_id_index ON property_sales (transfer_id);
CREATE INDEX property_sales_cap_rate_index
    ON property_sales (cap_rate)
    WHERE sale_type = 'arms_length' AND cap_rate IS NOT NULL;
CREATE INDEX property_sales_metrics_index
    ON property_sales USING GIN (metrics jsonb_path_ops);
CREATE INDEX property_sales_source_record_id_index
    ON property_sales (source_record_id);

CREATE TABLE property_leases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID NOT NULL REFERENCES properties(id),

    comp_type_id UUID REFERENCES comp_types(id),

    lessee_name TEXT,
    lessee_industry TEXT,
    landlord_name TEXT,
    tenant_broker TEXT,
    landlord_broker TEXT,

    space_id UUID REFERENCES spaces(id) ON DELETE SET NULL,
    suite TEXT,
    floor_number INTEGER,
    is_entire_property BOOLEAN NOT NULL DEFAULT FALSE,

    lease_type lease_type,
    transaction_type lease_transaction_type,
    execution_date DATE,
    commencement_date DATE,
    expiration_date DATE,
    CHECK (expiration_date IS NULL OR commencement_date IS NULL
           OR expiration_date > commencement_date),
    term_months INTEGER CHECK (term_months > 0),

    unit_system unit_system NOT NULL DEFAULT 'imperial',
    currency CHAR(3) NOT NULL DEFAULT 'USD',  -- ISO 4217; also governs child
                                              -- escalation/concession amounts
    leased_area INTEGER CHECK (leased_area > 0),

    rent_amount NUMERIC(14,2) CHECK (rent_amount >= 0),
    rent_period rent_period,
    starting_rent_per_area NUMERIC(10,2),
    effective_rent_per_area NUMERIC(10,2),
    net_effective_rent_per_area NUMERIC(10,2),
    annual_rent NUMERIC(14,2),

    free_rent_months NUMERIC(5,1),
    ti_allowance_per_area NUMERIC(10,2),

    expense_structure JSONB NOT NULL DEFAULT '{}',
    metrics JSONB NOT NULL DEFAULT '{}',

    source_record_id UUID REFERENCES source_records(id),
    contributed_by_id UUID REFERENCES users(id),
    verification_status verification_status NOT NULL DEFAULT 'unverified',

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT property_leases_nonnegative_amounts CHECK (
        (starting_rent_per_area IS NULL OR starting_rent_per_area >= 0)
        AND (effective_rent_per_area IS NULL OR effective_rent_per_area >= 0)
        AND (net_effective_rent_per_area IS NULL OR net_effective_rent_per_area >= 0)
        AND (annual_rent IS NULL OR annual_rent >= 0)
        AND (free_rent_months IS NULL OR free_rent_months >= 0)
        AND (ti_allowance_per_area IS NULL OR ti_allowance_per_area >= 0)
    )
);

CREATE INDEX property_leases_property_index
    ON property_leases (property_id, commencement_date DESC);
CREATE INDEX property_leases_comp_type_id_index ON property_leases (comp_type_id);
CREATE INDEX property_leases_space_id_index ON property_leases (space_id);
CREATE INDEX property_leases_metrics_index
    ON property_leases USING GIN (metrics jsonb_path_ops);
CREATE INDEX property_leases_source_record_id_index
    ON property_leases (source_record_id);

CREATE TABLE rent_escalations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lease_id UUID NOT NULL REFERENCES property_leases(id) ON DELETE CASCADE,

    escalation_type escalation_type NOT NULL,
    escalation_value NUMERIC(10,4),
    escalation_frequency_months INTEGER NOT NULL DEFAULT 12,
    cpi_index TEXT,
    cpi_floor NUMERIC(6,3),
    cpi_cap NUMERIC(6,3),
    step_schedule JSONB,
    effective_from DATE,
    effective_until DATE,

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT rent_escalations_frequency_positive
        CHECK (escalation_frequency_months > 0),
    CONSTRAINT rent_escalations_dates_ordered
        CHECK (effective_until IS NULL OR effective_from IS NULL
               OR effective_until > effective_from),
    CONSTRAINT rent_escalations_cpi_bounds_ordered
        CHECK (cpi_cap IS NULL OR cpi_floor IS NULL OR cpi_cap >= cpi_floor)
);

CREATE INDEX rent_escalations_lease_id_index ON rent_escalations (lease_id);

CREATE TABLE lease_concessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lease_id UUID NOT NULL REFERENCES property_leases(id) ON DELETE CASCADE,

    concession_type concession_type NOT NULL,
    concession_value NUMERIC(14,2),
    concession_unit TEXT,
    abatement_months INTEGER,
    abatement_percent NUMERIC(5,2),
    ti_allowance_per_area NUMERIC(10,2),
    ti_cap_total NUMERIC(14,2),
    effective_date DATE,
    expiration_date DATE,
    notes TEXT,
    conditions JSONB,

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT lease_concessions_nonnegative_amounts CHECK (
        (concession_value IS NULL OR concession_value >= 0)
        AND (abatement_months IS NULL OR abatement_months >= 0)
        AND (abatement_percent IS NULL OR abatement_percent BETWEEN 0 AND 100)
        AND (ti_allowance_per_area IS NULL OR ti_allowance_per_area >= 0)
        AND (ti_cap_total IS NULL OR ti_cap_total >= 0)
    ),
    CONSTRAINT lease_concessions_dates_ordered
        CHECK (expiration_date IS NULL OR effective_date IS NULL
               OR expiration_date > effective_date)
);

CREATE INDEX lease_concessions_lease_id_index ON lease_concessions (lease_id);

-- Survey observations of advertised/going unit rates (NOT executed leases):
-- multifamily floorplans, senior-housing beds, storage units, marina slips
CREATE TABLE property_unit_rents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID NOT NULL REFERENCES properties(id),

    comp_type_id UUID REFERENCES comp_types(id),

    unit_type TEXT NOT NULL,            -- '1BR/1BA', 'AL Studio Bed', '10x10'
    unit_system unit_system NOT NULL DEFAULT 'imperial',
    unit_area INTEGER,
    bedrooms INTEGER,
    bathrooms NUMERIC(4,1),
    unit_count INTEGER,
    units_available INTEGER,

    currency CHAR(3) NOT NULL DEFAULT 'USD',  -- ISO 4217; applies to all money fields on the row
    rate_amount NUMERIC(14,2) NOT NULL CHECK (rate_amount >= 0),
    rate_period rent_period NOT NULL DEFAULT 'monthly',
    rate_basis unit_rate_basis NOT NULL DEFAULT 'per_unit',
    rate_type rate_type NOT NULL DEFAULT 'asking',

    observed_on DATE NOT NULL,
    source_url TEXT,
    concessions_note TEXT,
    metrics JSONB NOT NULL DEFAULT '{}',

    source_record_id UUID REFERENCES source_records(id),
    contributed_by_id UUID REFERENCES users(id),
    verification_status verification_status NOT NULL DEFAULT 'unverified',

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT property_unit_rents_nonnegative_counts CHECK (
        (unit_area IS NULL OR unit_area > 0)
        AND (bedrooms IS NULL OR bedrooms >= 0)
        AND (bathrooms IS NULL OR bathrooms >= 0)
        AND (unit_count IS NULL OR unit_count >= 0)
        AND (units_available IS NULL OR units_available >= 0)
    )
);

CREATE INDEX property_unit_rents_property_index
    ON property_unit_rents (property_id, observed_on DESC);
CREATE INDEX property_unit_rents_comp_type_id_index
    ON property_unit_rents (comp_type_id);
CREATE INDEX property_unit_rents_unit_type_index
    ON property_unit_rents (unit_type);
CREATE INDEX property_unit_rents_metrics_index
    ON property_unit_rents USING GIN (metrics jsonb_path_ops);
CREATE INDEX property_unit_rents_source_record_id_index
    ON property_unit_rents (source_record_id);

CREATE TABLE property_listings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID NOT NULL REFERENCES properties(id),

    listing_kind listing_kind NOT NULL,
    status listing_status NOT NULL DEFAULT 'active',

    currency CHAR(3) NOT NULL DEFAULT 'USD',  -- ISO 4217; applies to all money fields on the row
    list_price NUMERIC(14,2),
    list_rent_amount NUMERIC(14,2),
    list_rent_period rent_period,

    listed_on DATE,
    status_changed_on DATE,
    close_price NUMERIC(14,2),
    mls_number TEXT,
    listing_brokerage TEXT,
    listing_agent TEXT,
    metadata JSONB NOT NULL DEFAULT '{}',

    source_record_id UUID REFERENCES source_records(id),
    verification_status verification_status NOT NULL DEFAULT 'unverified',

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT property_listings_nonnegative_amounts CHECK (
        (list_price IS NULL OR list_price >= 0)
        AND (list_rent_amount IS NULL OR list_rent_amount >= 0)
        AND (close_price IS NULL OR close_price >= 0)
    ),
    CONSTRAINT property_listings_status_date_ordered
        CHECK (status_changed_on IS NULL OR listed_on IS NULL
               OR status_changed_on >= listed_on)
);

CREATE INDEX property_listings_property_index
    ON property_listings (property_id, listed_on DESC);
CREATE INDEX property_listings_active_index
    ON property_listings (listing_kind) WHERE status = 'active';
CREATE INDEX property_listings_source_record_id_index
    ON property_listings (source_record_id);

-- Value opinions over time: vendor-fed (AVMs, via source_record_id) and
-- user-entered (appraisals, internal estimates, via contributed_by_id).
-- The assessor's official values are public record, not opinion: see
-- assessments.
CREATE TABLE valuations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID NOT NULL REFERENCES properties(id),

    valuation_kind valuation_kind NOT NULL,

    -- what the value IS (USPAP: definition of value, interest, premise)
    value_type TEXT NOT NULL DEFAULT 'market_value',
                                        -- 'market_value', 'liquidation_value',
                                        -- 'disposition_value', 'insurable_value',
                                        -- 'investment_value', ...
    interest_appraised TEXT,            -- 'fee_simple', 'leased_fee', 'leasehold'
    value_premise TEXT,                 -- 'as_is', 'as_completed', 'as_stabilized'

    currency CHAR(3) NOT NULL DEFAULT 'USD',  -- ISO 4217; applies to all money fields on the row
    -- value_amount is the final (for appraisals: reconciled) opinion;
    -- approach indications sit alongside when developed
    value_amount NUMERIC(14,2) NOT NULL CHECK (value_amount >= 0),
    indicated_value_sales_comparison NUMERIC(14,2),
    indicated_value_cost NUMERIC(14,2),
    indicated_value_income NUMERIC(14,2),
    value_low NUMERIC(14,2),
    value_high NUMERIC(14,2),
    CHECK (value_low IS NULL OR value_low <= value_amount),
    CHECK (value_high IS NULL OR value_high >= value_amount),
    unit_system unit_system NOT NULL DEFAULT 'imperial',
    value_per_area NUMERIC(10,2),
    confidence_score INTEGER CHECK (confidence_score BETWEEN 0 AND 100),

    as_of_date DATE NOT NULL,           -- effective date of value; may be
                                        -- retrospective or prospective
    report_date DATE,                   -- date of the report, if different
    -- long tail (exposure time, cost approach detail, cap rate used, ...)
    metadata JSONB NOT NULL DEFAULT '{}',

    source_record_id UUID REFERENCES source_records(id),
    contributed_by_id UUID REFERENCES users(id),

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX valuations_property_index ON valuations (property_id, as_of_date DESC);
CREATE INDEX valuations_source_record_id_index ON valuations (source_record_id);

CREATE TABLE income_expense_statements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID NOT NULL REFERENCES properties(id),

    statement_year INTEGER NOT NULL CHECK (statement_year BETWEEN 1900 AND 2200),
    is_actual BOOLEAN NOT NULL DEFAULT TRUE,

    currency CHAR(3) NOT NULL DEFAULT 'USD',  -- ISO 4217; applies to all money fields on the row
    pgi NUMERIC(14,2),
    vacancy_loss NUMERIC(14,2),
    vacancy_pct NUMERIC(5,2) CHECK (vacancy_pct BETWEEN 0 AND 100),
    egi NUMERIC(14,2),
    opex_total NUMERIC(14,2),
    noi NUMERIC(14,2),
    capex NUMERIC(14,2),
    reimbursements NUMERIC(14,2),
    line_items JSONB NOT NULL DEFAULT '{}',

    source_record_id UUID REFERENCES source_records(id),
    contributed_by_id UUID REFERENCES users(id),
    verification_status verification_status NOT NULL DEFAULT 'unverified',

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- noi is deliberately unconstrained: it can legitimately be negative
    CONSTRAINT income_expense_statements_nonnegative_amounts CHECK (
        (pgi IS NULL OR pgi >= 0)
        AND (vacancy_loss IS NULL OR vacancy_loss >= 0)
        AND (egi IS NULL OR egi >= 0)
        AND (opex_total IS NULL OR opex_total >= 0)
        AND (capex IS NULL OR capex >= 0)
        AND (reimbursements IS NULL OR reimbursements >= 0)
    )
);

CREATE INDEX income_expense_statements_property_index
    ON income_expense_statements (property_id, statement_year DESC);
CREATE INDEX income_expense_statements_source_record_id_index
    ON income_expense_statements (source_record_id);

-- ============================================================================
-- 15. COMP SETS (saved subject-property comp selections)
-- ============================================================================
CREATE TABLE comp_sets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_by_id UUID REFERENCES users(id),

    name TEXT NOT NULL,
    subject_property_id UUID REFERENCES properties(id),
    effective_date DATE,
    purpose TEXT,
    search_criteria JSONB NOT NULL DEFAULT '{}',
    notes TEXT,

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX comp_sets_subject_property_id_index
    ON comp_sets (subject_property_id);
CREATE INDEX comp_sets_created_by_id_index ON comp_sets (created_by_id);

CREATE TABLE comp_set_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    comp_set_id UUID NOT NULL REFERENCES comp_sets(id) ON DELETE CASCADE,

    comp_kind comp_kind NOT NULL,
    comp_id UUID NOT NULL,

    position INTEGER,
    selection_source comp_selection_source NOT NULL DEFAULT 'user',
    notes TEXT,
    metadata JSONB NOT NULL DEFAULT '{}',

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (comp_set_id, comp_kind, comp_id)
);

-- ============================================================================
-- 16. VERIFICATION EVIDENCE TRAIL (polymorphic, record- or field-level)
-- ============================================================================
CREATE TABLE data_verifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    verifiable_type TEXT NOT NULL CHECK (verifiable_type IN (
        'property', 'parcel', 'property_sale', 'property_lease',
        'property_unit_rent', 'property_listing', 'property_transfer',
        'ownership_period', 'ownership_interest', 'assessment', 'tax_bill',
        'property_mortgage', 'income_expense_statement', 'valuation',
        'rent_escalation', 'lease_concession', 'source_record',
        'owner', 'owner_contact', 'owner_address', 'address'
    )),
    verifiable_id UUID NOT NULL,
    field_name TEXT,

    verification_status verification_status NOT NULL DEFAULT 'pending_review',
    -- open vocabulary: 'owner_confirmed', 'broker_provided',
    -- 'lease_abstract', 'public_filing', 'on_site_observation',
    -- 'calculated', 'market_analysis', 'appraiser_workfile', ...
    verification_method TEXT NOT NULL,
    verification_date DATE,

    confidence_level confidence_level NOT NULL DEFAULT 'medium',
    confidence_score INTEGER CHECK (confidence_score BETWEEN 0 AND 100),

    evidence_type TEXT,
    evidence_url TEXT,
    evidence_notes TEXT,

    verified_by_id UUID NOT NULL REFERENCES users(id),
    verified_at TIMESTAMPTZ,
    reviewer_id UUID REFERENCES users(id),
    reviewed_at TIMESTAMPTZ,
    review_notes TEXT,
    expires_at TIMESTAMPTZ,

    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX data_verifications_verifiable_index
    ON data_verifications (verifiable_type, verifiable_id);

-- ============================================================================
-- 17. VIEWS
-- ============================================================================
CREATE VIEW v_current_sources AS
SELECT
    sr.property_id,
    sr.parcel_id,
    sr.id AS source_record_id,
    dp.code AS provider_code,
    dp.category AS provider_category,
    sr.record_kind,
    sr.normalized_fields,
    sr.confidence_score,
    sr.fetched_at
FROM source_records sr
JOIN data_providers dp ON dp.id = sr.provider_id
WHERE sr.is_current = TRUE;

CREATE VIEW v_current_ownership AS
SELECT
    op.property_id,
    op.id AS ownership_period_id,
    op.started_on,
    o.id AS owner_id,
    o.name AS owner_name,
    o.kind AS owner_kind,
    oi.ownership_pct,
    oi.vesting,
    op.verification_status
FROM ownership_periods op
JOIN ownership_interests oi ON oi.ownership_period_id = op.id
JOIN owners o ON o.id = oi.owner_id
WHERE op.ended_on IS NULL;

CREATE VIEW v_property_sale_history AS
SELECT
    ps.property_id,
    ps.id AS sale_id,
    ps.sale_date,
    ps.sale_price,
    ps.sale_type,
    ps.cap_rate,
    ps.price_per_area,
    ps.verification_status,
    pt.transfer_kind,
    pt.document_number
FROM property_sales ps
LEFT JOIN property_transfers pt ON pt.id = ps.transfer_id;

COMMIT;
