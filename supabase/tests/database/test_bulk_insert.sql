\set ON_ERROR_STOP true

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap;
\ir fixtures/atlanta_records.psql

SELECT plan(12);

-- ---------------------------------------------------------------------------
-- Happy path: rows land, generated ids and defaults come back
-- ---------------------------------------------------------------------------
SELECT is(
    (
        SELECT COUNT(*)
        FROM bulk_insert('addresses', '[
            {"address_hash": "bulktest-0000000000000000000001",
             "street_number": "101", "street_name": "Bulk", "street_suffix": "St",
             "locality": "Atlanta", "region": "GA", "postal_code": "30312",
             "location": "SRID=4326;POINT(-84.37 33.74)"},
            {"address_hash": "bulktest-0000000000000000000002",
             "street_number": "102", "street_name": "Bulk", "street_suffix": "St",
             "locality": "Atlanta", "region": "GA", "postal_code": "30312"}
        ]'::jsonb)
    ),
    2::BIGINT,
    'bulk_insert returns one jsonb row per inserted row'
);

SELECT ok(
    (
        SELECT (r->>'id') IS NOT NULL AND (r->>'full_address') LIKE '101 Bulk St%'
        FROM bulk_insert('addresses', '[
            {"address_hash": "bulktest-0000000000000000000003",
             "street_number": "101", "street_name": "Bulk", "street_suffix": "St",
             "locality": "Atlanta", "region": "GA", "postal_code": "30312"}
        ]'::jsonb) AS r
    ),
    'returned jsonb carries generated id and generated full_address'
);

-- Columns absent from the payload must take their DEFAULTs, not NULL
-- (addresses.country is NOT NULL DEFAULT ''US'' - the naive
-- jsonb_populate_recordset SELECT * would blow up here).
SELECT is(
    (
        SELECT r->>'country'
        FROM bulk_insert('addresses', '[
            {"address_hash": "bulktest-0000000000000000000004",
             "street_number": "104", "street_name": "Bulk", "street_suffix": "St",
             "locality": "Atlanta", "region": "GA", "postal_code": "30312"}
        ]'::jsonb) AS r
    ),
    'US',
    'columns absent from the payload keep their defaults'
);

-- EWKT geography strings cast on the way in, same as the REST path
SELECT ok(
    (
        SELECT ST_DWithin(
            a.location,
            ST_SetSRID(ST_MakePoint(-84.37, 33.74), 4326)::GEOGRAPHY,
            1
        )
        FROM addresses a
        WHERE a.address_hash = 'bulktest-0000000000000000000001'
    ),
    'EWKT location strings are stored as geography'
);

-- ---------------------------------------------------------------------------
-- Chain: returned ids feed the next bulk_insert (address -> property -> rent)
-- ---------------------------------------------------------------------------
SELECT is(
    (
        WITH addr AS (
            SELECT (r->>'id')::UUID AS id
            FROM bulk_insert('addresses', '[
                {"address_hash": "bulktest-0000000000000000000005",
                 "street_number": "105", "street_name": "Bulk", "street_suffix": "St",
                 "locality": "Atlanta", "region": "GA", "postal_code": "30312"}
            ]'::jsonb) AS r
        ),
        prop AS (
            SELECT (r->>'id')::UUID AS id
            FROM addr,
                 bulk_insert('properties', jsonb_build_array(jsonb_build_object(
                     'name', 'Bulk Test Property',
                     'situs_address_id', addr.id,
                     'property_type_id', '31000000-0000-0000-0000-000000000004'
                 ))) AS r
        )
        SELECT r->>'verification_status'
        FROM prop,
             bulk_insert('property_unit_rents', jsonb_build_array(jsonb_build_object(
                 'property_id', prop.id,
                 'comp_type_id', '30000000-0000-0000-0000-000000000004',
                 'unit_type', '2BR',
                 'bedrooms', 2,
                 'rate_amount', 2100,
                 'observed_on', '2026-07-09'
             ))) AS r
    ),
    'unverified',
    'returned ids chain address -> property -> unit rent in one statement'
);

-- ---------------------------------------------------------------------------
-- Argument validation
-- ---------------------------------------------------------------------------
SELECT throws_ok(
    $$SELECT bulk_insert('addresses', '{"address_hash": "x"}'::jsonb)$$,
    '22023',
    NULL,
    'object (non-array) rows raise invalid_parameter_value'
);

SELECT throws_ok(
    $$SELECT bulk_insert('addresses', 'null'::jsonb)$$,
    '22023',
    NULL,
    'JSON null rows raise invalid_parameter_value'
);

SELECT is(
    (SELECT COUNT(*) FROM bulk_insert('addresses', '[]'::jsonb)),
    0::BIGINT,
    'empty array is a no-op, not an error'
);

-- ---------------------------------------------------------------------------
-- Table gating
-- ---------------------------------------------------------------------------
SELECT throws_ok(
    $$SELECT bulk_insert('comp_types', '[{"code": "rogue"}]'::jsonb)$$,
    '22023',
    NULL,
    'vocabulary tables are refused'
);

SELECT throws_ok(
    $$SELECT bulk_insert('no_such_table', '[{"a": 1}]'::jsonb)$$,
    '22023',
    NULL,
    'unknown tables are refused'
);

SELECT throws_ok(
    $$SELECT bulk_insert('v_current_sources', '[{"a": 1}]'::jsonb)$$,
    '22023',
    NULL,
    'views are refused'
);

-- Unknown keys surface as undefined_column, mirroring PostgREST PGRST204
SELECT throws_ok(
    $$SELECT bulk_insert('addresses', '[
        {"address_hash": "bulktest-0000000000000000000006", "beds": 2}
    ]'::jsonb)$$,
    '42703',
    NULL,
    'unknown payload keys raise undefined_column'
);

SELECT * FROM finish();

ROLLBACK;
