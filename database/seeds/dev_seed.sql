-- ============================================================================
-- OpenComps dev seed: realistic Atlanta-metro dev data
-- Apply with scripts/seed_dev.sh (or: psql -f database/seeds/dev_seed.sql
-- from the repo root -- the \copy path is relative to the working directory).
--
-- Built from a curated sample of 250 real, public-record Atlanta-metro
-- addresses (database/seeds/dev/atlanta_addresses.csv). Everything else is
-- SYNTHETIC but deterministic: every random choice is hash-derived from the
-- address source_id, so reseeding always produces byte-identical data.
--
-- Requires: schema applied, us_zips loaded (counties come from the ZIP join).
-- ============================================================================
\set ON_ERROR_STOP true

BEGIN;

DO $guard$
BEGIN
    IF (SELECT COUNT(*) FROM us_zips) = 0 THEN
        RAISE EXCEPTION 'us_zips is empty -- run ./scripts/load_us_zips.sh first';
    END IF;
    IF EXISTS (SELECT 1 FROM data_providers WHERE code = 'dev_seed_bulk') THEN
        RAISE EXCEPTION 'dev seed already applied (provider dev_seed_bulk exists)';
    END IF;
END
$guard$;

-- deterministic pseudo-random in [0, 1), keyed on any text
CREATE FUNCTION pg_temp.hrand(key TEXT) RETURNS DOUBLE PRECISION
LANGUAGE SQL IMMUTABLE AS $$
    SELECT ((('x' || SUBSTR(MD5(key), 1, 8))::BIT(32)::INT::BIGINT & 2147483647))::DOUBLE PRECISION
           / 2147483647.0
$$;

-- deterministic UUID, keyed on a salt + id
CREATE FUNCTION pg_temp.duuid(salt TEXT, key TEXT) RETURNS UUID
LANGUAGE SQL IMMUTABLE AS $$
    SELECT MD5('opencomps-dev:' || salt || ':' || key)::UUID
$$;

-- ---------------------------------------------------------------------------
-- Staging: real addresses
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE _seed_addresses (
    source_id TEXT PRIMARY KEY,
    street_number TEXT, street_name TEXT, locality TEXT, region TEXT,
    postal_code TEXT, lon DOUBLE PRECISION, lat DOUBLE PRECISION
);

\copy _seed_addresses FROM 'database/seeds/dev/atlanta_addresses.csv' WITH (FORMAT csv, HEADER true)

-- ---------------------------------------------------------------------------
-- Deterministic per-address plan: type, dimensions, sale, owner
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE _seed AS
SELECT s2.*,
    ROUND(CASE s2.pt_code
        WHEN 'RES_SFD' THEN s2.gla * (180 + 220 * pg_temp.hrand(s2.source_id || ':psf'))
        WHEN 'MF_MID'  THEN s2.unit_count * (120000 + 180000 * pg_temp.hrand(s2.source_id || ':ppu'))
        WHEN 'COM_OFF' THEN s2.rba * (140 + 260 * pg_temp.hrand(s2.source_id || ':psf'))
        WHEN 'COM_RET' THEN s2.rba * (120 + 200 * pg_temp.hrand(s2.source_id || ':psf'))
        WHEN 'COM_IND' THEN s2.rba * (70 + 120 * pg_temp.hrand(s2.source_id || ':psf'))
        ELSE                s2.land_sqft * (3 + 12 * pg_temp.hrand(s2.source_id || ':psf'))
    END::NUMERIC, -3) AS est_value
FROM (
    SELECT s1.*,
        CASE WHEN s1.pt_code = 'RES_SFD'
             THEN (900 + FLOOR(3600 * pg_temp.hrand(s1.source_id || ':gla')))::INT
        END AS gla,
        CASE WHEN s1.pt_code IN ('MF_MID', 'COM_OFF', 'COM_RET', 'COM_IND')
             THEN (8000 + FLOOR(120000 * pg_temp.hrand(s1.source_id || ':rba')))::INT
        END AS rba,
        CASE WHEN s1.pt_code = 'MF_MID'
             THEN (40 + FLOOR(260 * pg_temp.hrand(s1.source_id || ':units')))::INT
        END AS unit_count,
        CASE WHEN s1.pt_code = 'COM_IND'
             THEN (18 + FLOOR(18 * pg_temp.hrand(s1.source_id || ':clear')))::NUMERIC(5,1)
        END AS clear_height,
        CASE
            WHEN s1.pt_code = 'RES_SFD' THEN (6000 + FLOOR(39000 * pg_temp.hrand(s1.source_id || ':lot')))::NUMERIC
            WHEN s1.pt_code = 'LND_COM' THEN (40000 + FLOOR(400000 * pg_temp.hrand(s1.source_id || ':lot')))::NUMERIC
            ELSE (20000 + FLOOR(200000 * pg_temp.hrand(s1.source_id || ':lot')))::NUMERIC
        END AS land_sqft,
        CASE WHEN s1.pt_code = 'RES_SFD'
             THEN (1925 + FLOOR(95 * pg_temp.hrand(s1.source_id || ':yb')))::INT
             ELSE (1960 + FLOOR(60 * pg_temp.hrand(s1.source_id || ':yb')))::INT
        END AS year_built,
        pg_temp.hrand(s1.source_id || ':sale') < 0.70 AS has_sale,
        (DATE '2019-01-01' + FLOOR(2500 * pg_temp.hrand(s1.source_id || ':saledate'))::INT) AS sale_date,
        pg_temp.hrand(s1.source_id || ':verified') < 0.35 AS is_verified,
        pg_temp.hrand(s1.source_id || ':listing') < 0.06 AS has_listing,
        pg_temp.hrand(s1.source_id || ':mortgage') < 0.50 AS has_mortgage,
        pg_temp.hrand(s1.source_id || ':delinquent') < 0.08 AS is_delinquent,
        FLOOR(60 * pg_temp.hrand(s1.source_id || ':owner'))::INT AS owner_bucket
    FROM (
        SELECT a.*, z.county_fips, z.county_name,
            CASE
                WHEN pg_temp.hrand(a.source_id || ':type') < 0.72 THEN 'RES_SFD'
                WHEN pg_temp.hrand(a.source_id || ':type') < 0.82 THEN 'MF_MID'
                WHEN pg_temp.hrand(a.source_id || ':type') < 0.88 THEN 'COM_OFF'
                WHEN pg_temp.hrand(a.source_id || ':type') < 0.93 THEN 'COM_RET'
                WHEN pg_temp.hrand(a.source_id || ':type') < 0.97 THEN 'COM_IND'
                ELSE 'LND_COM'
            END AS pt_code
        FROM _seed_addresses a
        JOIN us_zips z ON z.zip = a.postal_code
        WHERE z.county_fips IS NOT NULL
    ) s1
) s2;

-- ---------------------------------------------------------------------------
-- Providers, users, classification, jurisdictions
-- ---------------------------------------------------------------------------
INSERT INTO data_providers (id, code, name, category, kind)
VALUES (pg_temp.duuid('provider', 'dev_seed_bulk'),
        'dev_seed_bulk', 'OpenComps Dev Seed', 'user_contributed', 'bulk_feed');

INSERT INTO users (id, email, display_name)
VALUES
    (pg_temp.duuid('user', 'dev'), 'dev@opencomps.local', 'Dev Seeder'),
    (pg_temp.duuid('user', 'reviewer'), 'reviewer@opencomps.local', 'Dev Reviewer')
ON CONFLICT (email) DO NOTHING;

INSERT INTO comp_types (id, code, name, primary_unit, secondary_units)
VALUES
    (pg_temp.duuid('comp_type', 'residential'), 'residential', 'Residential', 'square_feet', ARRAY['bedrooms', 'bathrooms']),
    (pg_temp.duuid('comp_type', 'office'), 'office', 'Office', 'rentable_square_feet', ARRAY['cap_rate', 'noi']),
    (pg_temp.duuid('comp_type', 'retail'), 'retail', 'Retail', 'rentable_square_feet', ARRAY['frontage']),
    (pg_temp.duuid('comp_type', 'multifamily'), 'multifamily', 'Multifamily', 'unit', ARRAY['bedrooms', 'monthly_rent']),
    (pg_temp.duuid('comp_type', 'industrial'), 'industrial', 'Industrial', 'rentable_square_feet', ARRAY['clear_height']),
    (pg_temp.duuid('comp_type', 'land'), 'land', 'Land', 'acre', ARRAY['price_per_acre'])
ON CONFLICT (code) DO NOTHING;

INSERT INTO property_types (id, code, name, comp_type_id)
SELECT pg_temp.duuid('property_type', v.code), v.code, v.name,
       (SELECT id FROM comp_types WHERE code = v.comp_code)
FROM (VALUES
    ('RES_SFD', 'Single Family Detached', 'residential'),
    ('MF_MID', 'Mid-Rise Multifamily', 'multifamily'),
    ('COM_OFF', 'Office Building', 'office'),
    ('COM_RET', 'Retail Storefront', 'retail'),
    ('COM_IND', 'Industrial Flex', 'industrial'),
    ('LND_COM', 'Commercial Land', 'land')
) AS v(code, name, comp_code)
ON CONFLICT (code) DO NOTHING;

-- real counties, resolved through the us_zips reference table
INSERT INTO jurisdictions (id, country, region, name, kind, authority_code)
SELECT DISTINCT pg_temp.duuid('jurisdiction', s.county_fips),
       'US', s.region, s.county_name || ' County', 'county', s.county_fips
FROM _seed s
ON CONFLICT (country, kind, authority_code) WHERE authority_code IS NOT NULL
DO NOTHING;

-- ---------------------------------------------------------------------------
-- Owners: 60 recurring entities so portfolio queries have something to find
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE _owners AS
SELECT b.bucket,
       pg_temp.duuid('owner', b.bucket::TEXT) AS id,
       CASE WHEN b.is_person THEN b.first_name || ' ' || b.last_name
            ELSE b.stem || ' ' || b.noun || ' LLC'
       END AS name,
       CASE WHEN b.is_person THEN 'individual'::owner_kind ELSE 'llc'::owner_kind END AS kind
FROM (
    SELECT i AS bucket,
        pg_temp.hrand('owner-kind:' || i) < 0.55 AS is_person,
        (ARRAY['James','Maria','Robert','Aisha','David','Wei','Sarah','Miguel',
               'Karen','Samuel','Nia','Thomas','Grace','Andre','Linda','Marcus'])
            [1 + FLOOR(16 * pg_temp.hrand('owner-first:' || i))::INT] AS first_name,
        (ARRAY['Walker','Johnson','Chen','Patel','Nguyen','Garcia','Smith','Brooks',
               'Kim','Okafor','Ramirez','Thompson','Lee','Jackson','Alvarez','Wright'])
            [1 + FLOOR(16 * pg_temp.hrand('owner-last:' || i))::INT] AS last_name,
        (ARRAY['Peachtree','Piedmont','Chattahoochee','Buckhead','Ansley',
               'Vinings','Midtown','Westside','Ponce','Decatur'])
            [1 + FLOOR(10 * pg_temp.hrand('owner-stem:' || i))::INT] AS stem,
        (ARRAY['Capital','Holdings','Partners','Properties','Ventures','Realty'])
            [1 + FLOOR(6 * pg_temp.hrand('owner-noun:' || i))::INT] AS noun
    FROM GENERATE_SERIES(0, 59) AS i
) b;

INSERT INTO owners (id, name, normalized_name, kind)
SELECT id, name, LOWER(name), kind FROM _owners;

-- ---------------------------------------------------------------------------
-- Addresses, properties, identifiers, parcels
-- ---------------------------------------------------------------------------
INSERT INTO addresses (
    id, country, street_number, street_name, locality, region, postal_code,
    admin_area, address_hash, location, is_standardized, standardization_source
)
SELECT pg_temp.duuid('address', s.source_id),
       'US', NULLIF(s.street_number, ''), s.street_name, s.locality, s.region,
       s.postal_code, s.county_name || ' County',
       'dev-seed:' || s.source_id,
       ST_SetSRID(ST_MakePoint(s.lon, s.lat), 4326)::GEOGRAPHY,
       TRUE, 'dev_seed'
FROM _seed s;

INSERT INTO properties (id, name, property_type_id, situs_address_id, location, metadata)
SELECT pg_temp.duuid('property', s.source_id),
       TRIM(s.street_number || ' ' || s.street_name),
       (SELECT id FROM property_types WHERE code = s.pt_code),
       pg_temp.duuid('address', s.source_id),
       ST_SetSRID(ST_MakePoint(s.lon, s.lat), 4326)::GEOGRAPHY,
       JSONB_BUILD_OBJECT('seed_source_id', s.source_id, 'dev_seed', TRUE)
FROM _seed s;

INSERT INTO property_identifiers (property_id, scheme, namespace, value, provider_id)
SELECT pg_temp.duuid('property', s.source_id),
       'dev_seed_address_id', 'dev_seed', s.source_id,
       pg_temp.duuid('provider', 'dev_seed_bulk')
FROM _seed s;

INSERT INTO parcels (
    id, jurisdiction_id, country, authority_code, parcel_number,
    normalized_parcel_number, land_area, legal_description
)
SELECT pg_temp.duuid('parcel', s.source_id),
       j.id, 'US', s.county_fips,
       'DEV-' || UPPER(SUBSTR(s.source_id, 1, 10)),
       'DEV' || UPPER(SUBSTR(s.source_id, 1, 10)),
       s.land_sqft,
       'Dev seed parcel for ' || TRIM(s.street_number || ' ' || s.street_name)
FROM _seed s
JOIN jurisdictions j
  ON j.authority_code = s.county_fips AND j.kind = 'county' AND j.country = 'US';

INSERT INTO property_parcels (property_id, parcel_id, is_primary, started_on)
SELECT pg_temp.duuid('property', s.source_id),
       pg_temp.duuid('parcel', s.source_id),
       TRUE,
       DATE '2010-01-01' + FLOOR(3000 * pg_temp.hrand(s.source_id || ':pp'))::INT
FROM _seed s;

-- ---------------------------------------------------------------------------
-- Physical details by asset class
-- ---------------------------------------------------------------------------
INSERT INTO residential_details (
    property_id, gla, bedrooms, bathrooms, bathrooms_full, bathrooms_half,
    stories, year_built, garage_spaces, lot_size, condition_rating, quality_rating
)
SELECT pg_temp.duuid('property', s.source_id),
       s.gla,
       (2 + FLOOR(4 * pg_temp.hrand(s.source_id || ':bed')))::INT,
       (1 + FLOOR(3 * pg_temp.hrand(s.source_id || ':bathf')))::INT
           + CASE WHEN pg_temp.hrand(s.source_id || ':bathh') < 0.4 THEN 0.5 ELSE 0 END,
       (1 + FLOOR(3 * pg_temp.hrand(s.source_id || ':bathf')))::INT,
       CASE WHEN pg_temp.hrand(s.source_id || ':bathh') < 0.4 THEN 1 ELSE 0 END,
       CASE WHEN pg_temp.hrand(s.source_id || ':story') < 0.5 THEN 1.0 ELSE 2.0 END,
       s.year_built,
       FLOOR(4 * pg_temp.hrand(s.source_id || ':garage'))::INT,
       s.land_sqft,
       'C' || (2 + FLOOR(4 * pg_temp.hrand(s.source_id || ':cond')))::INT,
       'Q' || (2 + FLOOR(4 * pg_temp.hrand(s.source_id || ':qual')))::INT
FROM _seed s
WHERE s.pt_code = 'RES_SFD';

INSERT INTO commercial_details (
    property_id, rentable_building_area, land_area, stories, year_built,
    unit_count, occupancy_pct, clear_height, tenancy, building_class
)
SELECT pg_temp.duuid('property', s.source_id),
       s.rba, s.land_sqft,
       (1 + FLOOR(12 * pg_temp.hrand(s.source_id || ':floors')))::INT,
       s.year_built,
       s.unit_count,
       ROUND((70 + 30 * pg_temp.hrand(s.source_id || ':occ'))::NUMERIC, 1),
       s.clear_height,
       CASE WHEN pg_temp.hrand(s.source_id || ':tenancy') < 0.6
            THEN 'multi_tenant' ELSE 'single_tenant' END,
       (ARRAY['A','B','C'])[1 + FLOOR(3 * pg_temp.hrand(s.source_id || ':class'))::INT]
FROM _seed s
WHERE s.pt_code IN ('MF_MID', 'COM_OFF', 'COM_RET', 'COM_IND');

INSERT INTO land_details (property_id, lot_size, zoning, land_use, topography, utilities)
SELECT pg_temp.duuid('property', s.source_id),
       s.land_sqft,
       (ARRAY['C-1','C-2','M-1','MU-2','R-4'])[1 + FLOOR(5 * pg_temp.hrand(s.source_id || ':zone'))::INT],
       'vacant',
       (ARRAY['level','sloping','rolling'])[1 + FLOOR(3 * pg_temp.hrand(s.source_id || ':topo'))::INT],
       ARRAY['water', 'sewer', 'electric']
FROM _seed s
WHERE s.pt_code = 'LND_COM';

-- ---------------------------------------------------------------------------
-- Transfers, ownership, sale comps (for the ~70% that traded)
-- ---------------------------------------------------------------------------
INSERT INTO property_transfers (
    id, property_id, parcel_id, transfer_kind, recorded_on, effective_on,
    consideration, document_number, grantee_owner_id, verification_status
)
SELECT pg_temp.duuid('transfer', s.source_id),
       pg_temp.duuid('property', s.source_id),
       pg_temp.duuid('parcel', s.source_id),
       'warranty_deed', s.sale_date + 2, s.sale_date,
       s.est_value,
       'WD-' || EXTRACT(YEAR FROM s.sale_date) || '-DEV-' || UPPER(SUBSTR(s.source_id, 1, 8)),
       pg_temp.duuid('owner', s.owner_bucket::TEXT),
       CASE WHEN s.is_verified THEN 'verified' ELSE 'unverified' END::verification_status
FROM _seed s
WHERE s.has_sale;

INSERT INTO ownership_periods (
    id, property_id, started_on, acquired_via_transfer_id,
    contributed_by_id, verification_status
)
SELECT pg_temp.duuid('op', s.source_id),
       pg_temp.duuid('property', s.source_id),
       CASE WHEN s.has_sale THEN s.sale_date
            ELSE DATE '2012-01-01' + FLOOR(3600 * pg_temp.hrand(s.source_id || ':acq'))::INT
       END,
       CASE WHEN s.has_sale THEN pg_temp.duuid('transfer', s.source_id) END,
       pg_temp.duuid('user', 'dev'),
       CASE WHEN s.is_verified THEN 'verified' ELSE 'unverified' END::verification_status
FROM _seed s;

INSERT INTO ownership_interests (ownership_period_id, owner_id, ownership_pct, vesting, role)
SELECT pg_temp.duuid('op', s.source_id),
       pg_temp.duuid('owner', s.owner_bucket::TEXT),
       100.000, 'fee simple', 'owner'
FROM _seed s;

INSERT INTO property_sales (
    id, property_id, transfer_id, comp_type_id, sale_date, sale_price,
    sale_type, buyer_name, price_per_area, cap_rate, metrics,
    contributed_by_id, verification_status
)
SELECT pg_temp.duuid('sale', s.source_id),
       pg_temp.duuid('property', s.source_id),
       pg_temp.duuid('transfer', s.source_id),
       (SELECT ct.id FROM comp_types ct
        JOIN property_types pt ON pt.comp_type_id = ct.id
        WHERE pt.code = s.pt_code),
       s.sale_date, s.est_value,
       CASE WHEN pg_temp.hrand(s.source_id || ':saletype') < 0.90
            THEN 'arms_length' ELSE 'reo' END::sale_type,
       o.name,
       CASE WHEN s.pt_code = 'RES_SFD' THEN ROUND(s.est_value / s.gla, 2)
            WHEN s.rba IS NOT NULL THEN ROUND(s.est_value / s.rba, 2)
       END,
       CASE WHEN s.pt_code IN ('MF_MID', 'COM_OFF', 'COM_RET', 'COM_IND')
            THEN ROUND((4.5 + 4 * pg_temp.hrand(s.source_id || ':cap'))::NUMERIC, 2)
       END,
       CASE WHEN s.pt_code = 'MF_MID'
            THEN JSONB_BUILD_OBJECT('price_per_unit', ROUND(s.est_value / s.unit_count),
                                    'unit_count', s.unit_count)
            ELSE '{}'::JSONB
       END,
       pg_temp.duuid('user', 'dev'),
       CASE WHEN s.is_verified THEN 'verified' ELSE 'unverified' END::verification_status
FROM _seed s
JOIN _owners o ON o.bucket = s.owner_bucket
WHERE s.has_sale;

-- ---------------------------------------------------------------------------
-- Assessments and tax bills for every parcel (2024 roll)
-- ---------------------------------------------------------------------------
INSERT INTO assessments (
    id, parcel_id, jurisdiction_id, tax_year, roll_type, assessed_land,
    assessed_improvements, assessed_total, market_value, taxable_value,
    verification_status
)
SELECT pg_temp.duuid('assessment', s.source_id),
       pg_temp.duuid('parcel', s.source_id),
       j.id, 2024, 'original',
       ROUND(mv.market * 0.4 * 0.3, 2),
       ROUND(mv.market * 0.4 * 0.7, 2),
       ROUND(mv.market * 0.4, 2),
       ROUND(mv.market, 2),
       ROUND(mv.market * 0.4, 2),
       'unverified'
FROM _seed s
JOIN jurisdictions j
  ON j.authority_code = s.county_fips AND j.kind = 'county' AND j.country = 'US'
CROSS JOIN LATERAL (
    SELECT (s.est_value * (0.90 + 0.15 * pg_temp.hrand(s.source_id || ':mv')))::NUMERIC AS market
) mv;

INSERT INTO tax_bills (
    id, parcel_id, jurisdiction_id, tax_year, amount_billed, amount_paid,
    is_delinquent, delinquent_amount
)
SELECT pg_temp.duuid('tax_bill', s.source_id),
       pg_temp.duuid('parcel', s.source_id),
       j.id, 2024,
       bill.amount,
       CASE WHEN s.is_delinquent THEN 0 ELSE bill.amount END,
       s.is_delinquent,
       CASE WHEN s.is_delinquent THEN ROUND(bill.amount * 1.06, 2) END
FROM _seed s
JOIN jurisdictions j
  ON j.authority_code = s.county_fips AND j.kind = 'county' AND j.country = 'US'
CROSS JOIN LATERAL (
    SELECT ROUND(s.est_value * 0.4 * 0.033, 2) AS amount
) bill;

-- ---------------------------------------------------------------------------
-- Debt on about half the traded properties
-- ---------------------------------------------------------------------------
INSERT INTO property_mortgages (
    id, property_id, parcel_id, recording_date, loan_amount, lender_name,
    borrower_owner_id, loan_type, interest_rate, term_months, maturity_date,
    lien_position, status, related_transfer_id, verification_status
)
SELECT pg_temp.duuid('mortgage', s.source_id),
       pg_temp.duuid('property', s.source_id),
       pg_temp.duuid('parcel', s.source_id),
       s.sale_date + 2,
       ROUND((s.est_value * (0.55 + 0.20 * pg_temp.hrand(s.source_id || ':ltv')))::NUMERIC, -3),
       (ARRAY['Peachtree Bank','Truist','Synovus','Ameris Bank','Regions',
              'BANK5 CMBS Trust'])[1 + FLOOR(6 * pg_temp.hrand(s.source_id || ':lender'))::INT],
       pg_temp.duuid('owner', s.owner_bucket::TEXT),
       CASE WHEN s.pt_code = 'RES_SFD' THEN 'conventional' ELSE 'commercial' END,
       ROUND((3.5 + 4 * pg_temp.hrand(s.source_id || ':rate'))::NUMERIC, 3),
       loan.term,
       (s.sale_date + (loan.term || ' months')::INTERVAL)::DATE,
       1, 'active',
       pg_temp.duuid('transfer', s.source_id),
       'unverified'
FROM _seed s
CROSS JOIN LATERAL (
    SELECT CASE WHEN s.pt_code = 'RES_SFD' THEN 360
                ELSE (60 + FLOOR(5 * pg_temp.hrand(s.source_id || ':term'))::INT * 12)
           END AS term
) loan
WHERE s.has_sale AND s.has_mortgage;

-- ---------------------------------------------------------------------------
-- Market observations: multifamily floorplan rents, commercial leases,
-- active for-sale listings
-- ---------------------------------------------------------------------------
INSERT INTO property_unit_rents (
    id, property_id, comp_type_id, unit_type, unit_area, bedrooms, bathrooms,
    unit_count, rate_amount, rate_period, rate_basis, rate_type, observed_on,
    contributed_by_id, verification_status
)
SELECT pg_temp.duuid('rent:' || fp.unit_type, s.source_id),
       pg_temp.duuid('property', s.source_id),
       (SELECT id FROM comp_types WHERE code = 'multifamily'),
       fp.unit_type, fp.area, fp.beds, fp.baths,
       GREATEST(1, s.unit_count / 2),
       ROUND((fp.base + fp.spread * pg_temp.hrand(s.source_id || ':rent:' || fp.unit_type))::NUMERIC, 0),
       'monthly', 'per_unit', 'asking',
       DATE '2026-05-01',
       pg_temp.duuid('user', 'dev'), 'unverified'
FROM _seed s
CROSS JOIN (VALUES
    ('1BR/1BA', 760, 1, 1.0, 1200, 800),
    ('2BR/2BA', 1120, 2, 2.0, 1650, 1100)
) AS fp(unit_type, area, beds, baths, base, spread)
WHERE s.pt_code = 'MF_MID';

INSERT INTO property_leases (
    id, property_id, comp_type_id, lessee_name, lease_type, transaction_type,
    commencement_date, expiration_date, term_months, leased_area, rent_amount,
    rent_period, starting_rent_per_area, annual_rent, contributed_by_id,
    verification_status
)
SELECT pg_temp.duuid('lease', s.source_id),
       pg_temp.duuid('property', s.source_id),
       (SELECT ct.id FROM comp_types ct
        JOIN property_types pt ON pt.comp_type_id = ct.id
        WHERE pt.code = s.pt_code),
       (ARRAY['Summit Services','Bluebird Retail','Apex Logistics','Ivy Health',
              'Terra Foods','Nimbus Tech'])[1 + FLOOR(6 * pg_temp.hrand(s.source_id || ':tenant'))::INT],
       CASE s.pt_code WHEN 'COM_OFF' THEN 'modified_gross' ELSE 'triple_net' END::lease_type,
       'new_lease',
       lease.commencement,
       (lease.commencement + (lease.term || ' months')::INTERVAL)::DATE,
       lease.term,
       lease.area,
       lease.rate, 'per_area_annual', lease.rate,
       ROUND(lease.rate * lease.area, 2),
       pg_temp.duuid('user', 'dev'),
       CASE WHEN s.is_verified THEN 'verified' ELSE 'unverified' END::verification_status
FROM _seed s
CROSS JOIN LATERAL (
    SELECT (DATE '2023-01-01' + FLOOR(1100 * pg_temp.hrand(s.source_id || ':lc'))::INT) AS commencement,
           (36 + FLOOR(7 * pg_temp.hrand(s.source_id || ':lterm'))::INT * 12) AS term,
           GREATEST(1200, (s.rba * (0.15 + 0.35 * pg_temp.hrand(s.source_id || ':larea')))::INT) AS area,
           ROUND(CASE s.pt_code
               WHEN 'COM_OFF' THEN 24 + 22 * pg_temp.hrand(s.source_id || ':lrate')
               WHEN 'COM_RET' THEN 18 + 24 * pg_temp.hrand(s.source_id || ':lrate')
               ELSE 6 + 8 * pg_temp.hrand(s.source_id || ':lrate')
           END::NUMERIC, 2) AS rate
) lease
WHERE s.pt_code IN ('COM_OFF', 'COM_RET', 'COM_IND');

INSERT INTO property_listings (
    id, property_id, listing_kind, status, list_price, listed_on,
    listing_brokerage, verification_status
)
SELECT pg_temp.duuid('listing', s.source_id),
       pg_temp.duuid('property', s.source_id),
       'for_sale', 'active',
       ROUND((s.est_value * 1.05)::NUMERIC, -3),
       DATE '2026-01-01' + FLOOR(150 * pg_temp.hrand(s.source_id || ':listed'))::INT,
       'OpenComps Dev Brokerage',
       'unverified'
FROM _seed s
WHERE s.has_listing;

COMMIT;

-- what got seeded
SELECT 'properties' AS entity, COUNT(*) FROM properties WHERE metadata ? 'dev_seed'
UNION ALL SELECT 'parcels', COUNT(*) FROM parcels WHERE parcel_number LIKE 'DEV-%'
UNION ALL SELECT 'owners', COUNT(*) FROM owners
UNION ALL SELECT 'sales', COUNT(*) FROM property_sales
UNION ALL SELECT 'leases', COUNT(*) FROM property_leases
UNION ALL SELECT 'unit_rents', COUNT(*) FROM property_unit_rents
UNION ALL SELECT 'assessments', COUNT(*) FROM assessments
UNION ALL SELECT 'tax_bills', COUNT(*) FROM tax_bills
UNION ALL SELECT 'mortgages', COUNT(*) FROM property_mortgages
UNION ALL SELECT 'listings', COUNT(*) FROM property_listings
ORDER BY 1;
