\set ON_ERROR_STOP true

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap;
\ir fixtures/atlanta_records.sql
\ir fixtures/comp_scenarios.sql

SELECT plan(34);

-- ---------------------------------------------------------------------------
-- A. Emory Point multifamily full stack
-- ---------------------------------------------------------------------------
SELECT is(
    (
        SELECT assessed_total
        FROM assessments
        WHERE parcel_id = '70000000-0000-0000-0000-000000000004'
          AND tax_year = 2024
    ),
    27500000.00::NUMERIC,
    'multifamily parcel carries a DeKalb assessment'
);

SELECT ok(
    (
        SELECT amount_paid = amount_billed
        FROM tax_bills
        WHERE id = 'd0000000-0000-0000-0000-000000000002'
    ),
    'multifamily tax bill is paid in full'
);

SELECT is(
    (
        SELECT sale_price
        FROM property_sales
        WHERE property_id = '60000000-0000-0000-0000-000000000004'
          AND sale_type = 'arms_length'
    ),
    68500000.00::NUMERIC,
    'multifamily arms-length sale comp stores headline price'
);

SELECT is(
    (
        SELECT (metrics->>'price_per_unit')::NUMERIC
        FROM property_sales
        WHERE id = 'f0000000-0000-0000-0000-000000000004'
    ),
    428125::NUMERIC,
    'asset-class long-tail metric (price per unit) is queryable from metrics JSONB'
);

SELECT is(
    (
        SELECT cap_rate
        FROM property_sales
        WHERE id = 'f0000000-0000-0000-0000-000000000004'
    ),
    4.90::NUMERIC,
    'multifamily sale comp stores screened cap rate'
);

-- the README flagship debt screen: active loans maturing inside a window
SELECT is(
    (
        SELECT lender_name
        FROM property_mortgages
        WHERE status = 'active'
          AND maturity_date <= DATE '2028-01-01'
    ),
    'BANK5 2022-5YR22 Mortgage Trust',
    'maturity screen finds only the CMBS loan maturing inside the window'
);

SELECT is(
    (
        SELECT dp.code
        FROM valuations v
        JOIN source_records sr ON sr.id = v.source_record_id
        JOIN data_providers dp ON dp.id = sr.provider_id
        WHERE v.id = 'f7000000-0000-0000-0000-000000000002'
    ),
    'avm_vendor',
    'vendor AVM valuation traces back to its provider'
);

SELECT is(
    (
        SELECT value_high - value_low
        FROM valuations
        WHERE id = 'f7000000-0000-0000-0000-000000000002'
    ),
    8800000.00::NUMERIC,
    'AVM valuation carries a confidence range around the point value'
);

SELECT is(
    (
        SELECT SUM(ownership_pct)
        FROM ownership_interests
        WHERE ownership_period_id = 'b0000000-0000-0000-0000-000000000005'
    ),
    100.000::NUMERIC,
    'JV ownership interests sum to a whole'
);

SELECT is(
    (
        SELECT COUNT(*)
        FROM ownership_interests
        WHERE ownership_period_id = 'b0000000-0000-0000-0000-000000000005'
    ),
    2::BIGINT,
    'one ownership regime holds both JV members'
);

-- "everything this LLC owns": current interests across properties
SELECT set_eq(
    $$
        SELECT p.name::TEXT
        FROM v_current_ownership vco
        JOIN properties p ON p.id = vco.property_id
        WHERE vco.owner_name = 'Peachtree Tower Partners LP'
    $$,
    ARRAY['3324 Peachtree Office', 'Emory Point Apartments']::TEXT[],
    'portfolio query returns every property an owner currently holds an interest in'
);

-- ---------------------------------------------------------------------------
-- B. 1007-style residential rent comp
-- ---------------------------------------------------------------------------
SELECT is(
    (
        SELECT rate_amount
        FROM property_unit_rents
        WHERE id = 'f5000000-0000-0000-0000-000000000003'
          AND rate_period = 'monthly'
          AND rate_type = 'contract'
    ),
    2400.00::NUMERIC,
    'single-family monthly contract rent comp stores the 1007-style rate'
);

SELECT is(
    (
        SELECT rd.bedrooms
        FROM property_unit_rents ur
        JOIN residential_details rd ON rd.property_id = ur.property_id
        WHERE ur.id = 'f5000000-0000-0000-0000-000000000003'
    ),
    3,
    'residential rent comp joins to physical bedroom count'
);

-- ---------------------------------------------------------------------------
-- C. Westpark industrial: listing -> sale, NNN lease, delinquency, ownership
-- ---------------------------------------------------------------------------
SELECT is(
    (
        SELECT close_price
        FROM property_listings
        WHERE id = 'f6000000-0000-0000-0000-000000000001'
          AND status = 'sold'
    ),
    7050000.00::NUMERIC,
    'sold listing records its close price'
);

SELECT results_eq(
    $$
        SELECT sale_price::NUMERIC, transfer_kind::TEXT
        FROM v_property_sale_history
        WHERE property_id = '60000000-0000-0000-0000-000000000005'
    $$,
    $$
        VALUES (7050000.00::NUMERIC, 'warranty_deed'::TEXT)
    $$,
    'industrial sale history links the closed listing sale to its deed'
);

SELECT is(
    (
        SELECT annual_rent
        FROM property_leases
        WHERE id = 'f2000000-0000-0000-0000-000000000003'
          AND lease_type = 'triple_net'
    ),
    236250.00::NUMERIC,
    'industrial NNN lease stores annualized rent'
);

SELECT is(
    (
        SELECT cd.clear_height
        FROM property_leases pl
        JOIN commercial_details cd ON cd.property_id = pl.property_id
        WHERE pl.id = 'f2000000-0000-0000-0000-000000000003'
    ),
    24.0::NUMERIC,
    'industrial lease comp joins to clear height for screening'
);

SELECT set_eq(
    $$
        SELECT parcel_id
        FROM tax_bills
        WHERE is_delinquent = TRUE
    $$,
    ARRAY['70000000-0000-0000-0000-000000000005']::UUID[],
    'delinquency screen surfaces only the delinquent parcel'
);

SELECT is(
    (
        SELECT owner_name
        FROM v_current_ownership
        WHERE property_id = '60000000-0000-0000-0000-000000000005'
    ),
    'Westpark Acquisitions LLC',
    'ownership turnover: buyer is the current owner'
);

SELECT is(
    (
        SELECT o.name
        FROM ownership_periods op
        JOIN ownership_interests oi ON oi.ownership_period_id = op.id
        JOIN owners o ON o.id = oi.owner_id
        WHERE op.property_id = '60000000-0000-0000-0000-000000000005'
          AND op.valid_period @> DATE '2020-06-01'
    ),
    'Westpark Industrial LLC',
    'ownership turnover: as-of query still finds the prior owner'
);

-- parcel split: the property UUID survives parcel churn
SELECT ok(
    (
        SELECT retired_on IS NOT NULL
        FROM parcels
        WHERE id = '70000000-0000-0000-0000-000000000005'
    ),
    'split predecessor parcel is retired'
);

SELECT set_eq(
    $$
        SELECT successor_parcel_id
        FROM parcel_lineage
        WHERE predecessor_parcel_id = '70000000-0000-0000-0000-000000000005'
          AND kind = 'split'
    $$,
    ARRAY[
        '70000000-0000-0000-0000-000000000008',
        '70000000-0000-0000-0000-000000000009'
    ]::UUID[],
    'parcel lineage records both split successors'
);

SELECT is(
    (
        SELECT COUNT(*)
        FROM property_parcels
        WHERE property_id = '60000000-0000-0000-0000-000000000005'
          AND ended_on IS NULL
    ),
    2::BIGINT,
    'the same property record now spans both successor parcels'
);

SELECT is(
    (
        SELECT COUNT(*)
        FROM property_parcels
        WHERE property_id = '60000000-0000-0000-0000-000000000005'
          AND is_primary = TRUE
          AND ended_on IS NULL
    ),
    1::BIGINT,
    'exactly one successor parcel is the current primary'
);

-- ---------------------------------------------------------------------------
-- D. Condo unit sub-parcel
-- ---------------------------------------------------------------------------
SELECT is(
    (
        SELECT reso_upi
        FROM parcels
        WHERE id = '70000000-0000-0000-0000-000000000010'
    ),
    'urn:reso:upi:2.0:US:13121:17 010100080250:sub:1204',
    'condo unit parcel generates a RESO UPI with the sub designator'
);

SELECT is(
    (
        SELECT COUNT(*)
        FROM parcels
        WHERE parcel_number = '17 010100080250'
          AND retired_on IS NULL
    ),
    2::BIGINT,
    'condo master parcel and unit sub-parcel coexist under one parcel number'
);

SELECT is(
    (
        SELECT sale_price
        FROM property_sales
        WHERE id = 'f0000000-0000-0000-0000-000000000006'
    ),
    410000.00::NUMERIC,
    'condo unit sale comp is recorded against the property spine'
);

-- ---------------------------------------------------------------------------
-- E. Vacant land
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT situs_address_id IS NULL
        FROM properties
        WHERE id = '60000000-0000-0000-0000-000000000008'
    ),
    'vacant land property is valid without a situs address'
);

SELECT ok(
    (
        SELECT utilities @> ARRAY['water', 'sewer']
        FROM land_details
        WHERE property_id = '60000000-0000-0000-0000-000000000008'
    ),
    'land details store available utilities as a searchable array'
);

SELECT is(
    (
        SELECT (metrics->>'price_per_acre')::NUMERIC
        FROM property_sales
        WHERE id = 'f0000000-0000-0000-0000-000000000007'
    ),
    217800::NUMERIC,
    'land sale comp stores price per acre in metrics'
);

-- ---------------------------------------------------------------------------
-- F. Mixed-kind comp set + classification mapping + value timeline
-- ---------------------------------------------------------------------------
SELECT is(
    (
        SELECT COUNT(DISTINCT comp_kind)
        FROM comp_set_items
        WHERE comp_set_id = 'f9000000-0000-0000-0000-000000000002'
    ),
    3::BIGINT,
    'a comp set can mix sale, lease, and unit rent comparables'
);

SELECT is(
    (
        SELECT selection_source
        FROM comp_set_items
        WHERE comp_set_id = 'f9000000-0000-0000-0000-000000000002'
          AND position = 2
    ),
    'ai_suggested'::comp_selection_source,
    'comp set items record AI-suggested provenance'
);

SELECT is(
    (
        SELECT pt.code
        FROM property_type_mappings m
        JOIN property_types pt ON pt.id = m.property_type_id
        JOIN classification_taxonomies ct ON ct.id = m.taxonomy_id
        WHERE ct.code = 'uad_36'
          AND m.external_code = 'SF'
    ),
    'RES_SFD',
    'external taxonomy code maps back to the internal property type'
);

-- official assessed values and value opinions unify via UNION, by design
SELECT is(
    (
        SELECT COUNT(*)
        FROM (
            SELECT a.market_value AS value
            FROM assessments a
            JOIN property_parcels pp ON pp.parcel_id = a.parcel_id
            WHERE pp.property_id = '60000000-0000-0000-0000-000000000001'
            UNION ALL
            SELECT v.value_amount
            FROM valuations v
            WHERE v.property_id = '60000000-0000-0000-0000-000000000001'
        ) AS timeline
    ),
    2::BIGINT,
    'unified value timeline is a UNION of assessments and valuations'
);

SELECT * FROM finish();

ROLLBACK;
