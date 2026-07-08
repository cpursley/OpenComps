\set ON_ERROR_STOP true

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap;
\ir fixtures/atlanta_records.sql
\ir fixtures/comp_scenarios.sql
\ir fixtures/global_scenarios.sql

SELECT plan(10);

-- the README claim, verbatim: a Georgia APN, an Ontario PIN, and a German
-- Flurstueck all fit
SELECT set_eq(
    $$
        SELECT reso_upi
        FROM parcels
        WHERE id IN (
            '70000000-0000-0000-0000-000000000001',
            '70000000-0000-0000-0000-000000000012',
            '70000000-0000-0000-0000-000000000013'
        )
    $$,
    ARRAY[
        'urn:reso:upi:2.0:US:13121:17 010000010276',
        'urn:reso:upi:2.0:CA:ON-LRO-80:76331-0245',
        'urn:reso:upi:2.0:DE:DE-09162:Flur 2, Flurstueck 123/4'
    ]::TEXT[],
    'US, Canadian, and German parcel identifiers generate RESO UPIs side by side'
);

SELECT results_eq(
    $$
        SELECT currency::TEXT, unit_system::TEXT, price_per_area::NUMERIC
        FROM property_sales
        WHERE id = 'f0000000-0000-0000-0000-000000000008'
    $$,
    $$
        VALUES ('CAD'::TEXT, 'metric'::TEXT, 5500.00::NUMERIC)
    $$,
    'Toronto sale comp is quoted in CAD per square meter'
);

SELECT set_eq(
    $$
        SELECT DISTINCT currency::TEXT
        FROM property_sales
    $$,
    ARRAY['USD', 'CAD', 'EUR']::TEXT[],
    'sale comps in three currencies coexist, stored as quoted'
);

SELECT is(
    (SELECT COUNT(DISTINCT unit_system) FROM property_sales),
    2::BIGINT,
    'imperial and metric sale comps sit side by side in the same table'
);

SELECT is(
    (
        SELECT full_address
        FROM addresses
        WHERE id = '50000000-0000-0000-0000-000000000008'
    ),
    '318 King Street West Toronto ON M5V 1J2 CA',
    'international address components generate a searchable display address'
);

SELECT results_eq(
    $$
        SELECT currency::TEXT, annual_rent::NUMERIC
        FROM property_leases
        WHERE id = 'f2000000-0000-0000-0000-000000000004'
    $$,
    $$
        VALUES ('EUR'::TEXT, 663000.00::NUMERIC)
    $$,
    'Munich industrial lease is quoted in EUR at a per-square-meter rate'
);

SELECT is(
    (
        SELECT (metrics->>'rent_per_bed')::NUMERIC
        FROM property_leases
        WHERE id = 'f2000000-0000-0000-0000-000000000005'
    ),
    800::NUMERIC,
    'by-the-bed residential lease keeps per-bed rent in metrics'
);

SELECT is(
    (
        SELECT rate_amount
        FROM property_unit_rents
        WHERE id = 'f5000000-0000-0000-0000-000000000004'
          AND rate_basis = 'per_bed'
    ),
    5200.00::NUMERIC,
    'assisted-living survey rate is quoted per bed'
);

SELECT results_eq(
    $$
        SELECT rate_amount::NUMERIC, rate_basis::TEXT, rate_period::TEXT
        FROM property_unit_rents
        WHERE id = 'f5000000-0000-0000-0000-000000000005'
    $$,
    $$
        VALUES (189.00::NUMERIC, 'per_key'::TEXT, 'daily'::TEXT)
    $$,
    'hotel ADR observation is quoted per key per day'
);

SELECT is(
    (
        SELECT list_rent_amount
        FROM property_listings
        WHERE listing_kind = 'for_lease'
          AND status = 'active'
    ),
    38.00::NUMERIC,
    'active for-lease listing stores its asking rent'
);

SELECT * FROM finish();

ROLLBACK;
