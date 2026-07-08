\set ON_ERROR_STOP true

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap;
\ir fixtures/atlanta_records.sql

SELECT plan(38);

SELECT is(
    (SELECT COUNT(*) FROM properties WHERE metadata ? 'seed_source_id'),
    7::BIGINT,
    'fixture loads seven Atlanta-area properties'
);

SELECT set_eq(
    $$
        SELECT name::TEXT
        FROM properties
        WHERE metadata ? 'seed_source_id'
    $$,
    ARRAY[
        '276 Springdale Drive NE',
        '42 Atlanta Avenue SE',
        'Caroline Street Retail',
        'Emory Point Apartments',
        'Westpark Industrial Flex',
        '3324 Peachtree Office',
        '2500 Peachtree Condominium'
    ]::TEXT[],
    'fixture preserves the expected property names'
);

SELECT is(
    (
        SELECT full_address
        FROM addresses
        WHERE id = '50000000-0000-0000-0000-000000000001'
    ),
    '276 Springdale Drive NE Atlanta GA 30305 US',
    'address components generate a searchable display address'
);

SELECT ok(
    (
        SELECT ST_DWithin(a.location, z.location, 5000)
        FROM addresses a
        JOIN us_zips z ON z.zip = a.postal_code
        WHERE a.id = '50000000-0000-0000-0000-000000000001'
    ),
    'Springdale geocode is within 5 km of ZIP 30305 centroid'
);

-- scoped to fixture ZIPs so results hold with or without the full
-- SimpleMaps dataset loaded alongside
SELECT set_eq(
    $$
        SELECT z.zip
        FROM us_zips z, addresses a
        WHERE a.id = '50000000-0000-0000-0000-000000000001'
          AND z.zip IN ('30305', '30307', '30316', '30336')
          AND ST_DWithin(z.location, a.location, 8000)
    $$,
    ARRAY['30305', '30307'],
    'radius search finds ZIP centroids within 8 km of the Springdale address'
);

SELECT is(
    (
        SELECT z.zip
        FROM us_zips z, addresses a
        WHERE a.id = '50000000-0000-0000-0000-000000000001'
          AND z.zip IN ('30305', '30307', '30316', '30336')
        ORDER BY z.location <-> a.location
        LIMIT 1
    ),
    '30305',
    'nearest-ZIP distance ordering returns the containing ZIP first'
);

SELECT is(
    (
        SELECT reso_upi
        FROM parcels
        WHERE id = '70000000-0000-0000-0000-000000000001'
    ),
    'urn:reso:upi:2.0:US:13121:17 010000010276',
    'parcel generates RESO UPI from jurisdiction authority and raw parcel number'
);

SELECT is(
    (
        SELECT COUNT(*)
        FROM property_parcels
        WHERE is_primary = TRUE AND ended_on IS NULL
    ),
    7::BIGINT,
    'every fixture property has one current primary parcel'
);

SELECT is(
    (
        SELECT COUNT(*)
        FROM v_current_sources
        WHERE property_id = '60000000-0000-0000-0000-000000000001'
    ),
    2::BIGINT,
    'current source view includes current property and assessment sources'
);

SELECT is_empty(
    $$
        SELECT 1
        FROM v_current_sources
        WHERE source_record_id = '80000000-0000-0000-0000-000000000002'
    $$,
    'current source view excludes superseded source records'
);

SELECT is(
    (
        SELECT owner_name
        FROM v_current_ownership
        WHERE property_id = '60000000-0000-0000-0000-000000000001'
    ),
    'Springdale Holdings LLC',
    'current ownership view returns the current Springdale owner'
);

SELECT is_empty(
    $$
        SELECT 1
        FROM v_current_ownership
        WHERE property_id = '60000000-0000-0000-0000-000000000001'
          AND owner_name = 'Springdale Family Trust'
    $$,
    'current ownership view excludes prior owners'
);

SELECT is(
    (
        SELECT o.name
        FROM ownership_periods op
        JOIN ownership_interests oi ON oi.ownership_period_id = op.id
        JOIN owners o ON o.id = oi.owner_id
        WHERE op.property_id = '60000000-0000-0000-0000-000000000001'
          AND op.valid_period @> DATE '2020-01-01'
    ),
    'Springdale Family Trust',
    'ownership daterange answers historical as-of owner'
);

SELECT is(
    (
        SELECT o.name
        FROM ownership_periods op
        JOIN ownership_interests oi ON oi.ownership_period_id = op.id
        JOIN owners o ON o.id = oi.owner_id
        WHERE op.property_id = '60000000-0000-0000-0000-000000000001'
          AND op.valid_period @> DATE '2022-01-01'
    ),
    'Springdale Holdings LLC',
    'ownership daterange answers current as-of owner'
);

SELECT is(
    (
        SELECT sale_price
        FROM v_property_sale_history
        WHERE property_id = '60000000-0000-0000-0000-000000000001'
    ),
    745000.00::NUMERIC,
    'sale history exposes Springdale sale price'
);

SELECT is(
    (
        SELECT transfer_kind
        FROM v_property_sale_history
        WHERE sale_id = 'f0000000-0000-0000-0000-000000000001'
    ),
    'warranty_deed',
    'sale history joins sale comps to recorded transfer kind'
);

SELECT is_empty(
    $$
        SELECT 1
        FROM v_property_sale_history
        WHERE transfer_kind = 'quitclaim'
    $$,
    'quitclaim deed transfers do not become sale comps automatically'
);

SELECT is(
    (
        SELECT COUNT(*)
        FROM property_sales
        WHERE comp_type_id = '30000000-0000-0000-0000-000000000001'
          AND sale_type = 'arms_length'
    ),
    2::BIGINT,
    'residential arms-length sale comps are queryable by comp type and sale type'
);

SELECT is(
    (
        SELECT cap_rate
        FROM property_sales
        WHERE id = 'f0000000-0000-0000-0000-000000000003'
    ),
    6.75::NUMERIC,
    'commercial sale comp stores screened cap rate'
);

SELECT is(
    (
        SELECT assessed_total
        FROM assessments
        WHERE parcel_id = '70000000-0000-0000-0000-000000000001'
          AND tax_year = 2024
    ),
    612000.00::NUMERIC,
    'assessment stores parcel-first assessed value'
);

SELECT is(
    (
        SELECT JSONB_ARRAY_LENGTH(line_items)
        FROM tax_bills
        WHERE id = 'd0000000-0000-0000-0000-000000000001'
    ),
    2,
    'tax bill stores jurisdiction line-item detail'
);

SELECT is(
    (
        SELECT maturity_date
        FROM property_mortgages
        WHERE property_id = '60000000-0000-0000-0000-000000000001'
          AND status = 'active'
    ),
    DATE '2051-06-01',
    'active mortgage maturity is queryable'
);

SELECT is(
    (
        SELECT COUNT(*)
        FROM structures
        WHERE property_id = '60000000-0000-0000-0000-000000000006'
    ),
    1::BIGINT,
    'office property has a physical structure'
);

SELECT is(
    (
        SELECT SUM(rentable_area)
        FROM spaces
        WHERE property_id = '60000000-0000-0000-0000-000000000006'
    ),
    40500::BIGINT,
    'office structure has separately leasable spaces'
);

SELECT is(
    (
        SELECT COUNT(*)
        FROM property_leases
        WHERE verification_status = 'verified'
    ),
    2::BIGINT,
    'verified lease comps load'
);

SELECT is(
    (
        SELECT net_effective_rent_per_area
        FROM property_leases
        WHERE id = 'f2000000-0000-0000-0000-000000000001'
    ),
    38.20::NUMERIC,
    'lease comp stores net effective rent per area'
);

SELECT is(
    (
        SELECT SUM(concession_value)
        FROM lease_concessions
        WHERE lease_id = 'f2000000-0000-0000-0000-000000000001'
    ),
    1094583.33::NUMERIC,
    'lease concessions preserve free rent and TI value'
);

SELECT is(
    (
        SELECT COUNT(*)
        FROM rent_escalations
        WHERE escalation_type = 'fixed_percent'
    ),
    2::BIGINT,
    'rent escalations model fixed annual increases'
);

SELECT results_eq(
    $$
        SELECT unit_type::TEXT, rate_amount::NUMERIC(14,2)
        FROM property_unit_rents
        ORDER BY unit_type
    $$,
    $$
        VALUES
            ('1BR/1BA'::TEXT, 1975.00::NUMERIC(14,2)),
            ('2BR/2BA'::TEXT, 2750.00::NUMERIC(14,2))
    $$,
    'unit rent survey rows compare expected floorplan rents'
);

SELECT is(
    (
        SELECT list_price
        FROM property_listings
        WHERE status = 'active'
    ),
    7250000.00::NUMERIC,
    'active listing stores asking price'
);

SELECT is(
    (
        SELECT value_amount
        FROM valuations
        WHERE property_id = '60000000-0000-0000-0000-000000000001'
        ORDER BY as_of_date DESC
        LIMIT 1
    ),
    760000.00::NUMERIC,
    'valuation stores reconciled opinion of value'
);

SELECT is(
    (
        SELECT noi
        FROM income_expense_statements
        WHERE property_id = '60000000-0000-0000-0000-000000000006'
          AND statement_year = 2023
    ),
    2821500.00::NUMERIC,
    'income statement stores NOI for commercial screening'
);

SELECT is(
    (
        SELECT comp_id
        FROM comp_set_items
        WHERE comp_set_id = 'f9000000-0000-0000-0000-000000000001'
          AND position = 1
    ),
    'f0000000-0000-0000-0000-000000000002'::UUID,
    'comp set preserves selected comparable order'
);

SELECT is(
    (
        SELECT verification_method
        FROM data_verifications
        WHERE verifiable_type = 'property_sale'
          AND field_name = 'sale_price'
    ),
    'public_filing',
    'field-level verification keeps evidence method'
);

SELECT is(
    (
        SELECT visibility
        FROM owner_contacts
        WHERE owner_id = '90000000-0000-0000-0000-000000000002'
          AND kind = 'email'
    ),
    'licensed'::data_visibility,
    'owner contact visibility can mark licensed skip-trace data'
);

SELECT is(
    (
        SELECT visibility
        FROM owner_addresses
        WHERE owner_id = '90000000-0000-0000-0000-000000000002'
          AND is_primary = TRUE
    ),
    'public_record'::data_visibility,
    'owner mailing address defaults to public-record visibility'
);

SELECT is(
    (
        SELECT p.name
        FROM property_identifiers pi
        JOIN properties p ON p.id = pi.property_id
        WHERE pi.scheme = 'dev_seed_address_id'
          AND pi.namespace = 'dev_seed'
          AND pi.value = '00012aa9e1f3582e'
    ),
    '276 Springdale Drive NE',
    'namespaced identifier maps a dev seed ID to the property spine'
);

SELECT results_eq(
    $$
        SELECT p.name::TEXT, j.name::TEXT
        FROM properties p
        JOIN property_parcels pp ON pp.property_id = p.id
        JOIN parcels pa ON pa.id = pp.parcel_id
        JOIN jurisdictions j ON j.id = pa.jurisdiction_id
        WHERE p.name IN ('Caroline Street Retail', '276 Springdale Drive NE')
        ORDER BY p.name
    $$,
    $$
        VALUES
            ('276 Springdale Drive NE'::TEXT, 'Fulton County'::TEXT),
            ('Caroline Street Retail'::TEXT, 'DeKalb County'::TEXT)
    $$,
    'parcel links preserve county authority across Fulton and DeKalb examples'
);

SELECT * FROM finish();

ROLLBACK;
