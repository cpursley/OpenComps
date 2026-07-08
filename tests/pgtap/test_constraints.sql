\set ON_ERROR_STOP true

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap;
\ir fixtures/atlanta_records.sql

SELECT plan(57);

SELECT lives_ok(
    $$
        INSERT INTO parcels (
            id, jurisdiction_id, country, authority_code, parcel_number,
            normalized_parcel_number, retired_on
        )
        VALUES (
            '70000000-0000-0000-0000-000000000101',
            '40000000-0000-0000-0000-000000000001',
            'US', '13121', '17 010000010276', '17010000010276',
            '2024-01-01'
        )
    $$,
    'retired parcel numbers can coexist with the active parcel'
);

SELECT throws_ok(
    $$
        INSERT INTO parcels (
            id, jurisdiction_id, country, authority_code, parcel_number,
            normalized_parcel_number
        )
        VALUES (
            '70000000-0000-0000-0000-000000000102',
            '40000000-0000-0000-0000-000000000001',
            'US', '13121', '17 010000010276', '17010000010276'
        )
    $$,
    '23505'::CHAR(5),
    NULL,
    'active parcel numbers are unique per jurisdiction'
);

INSERT INTO parcels (
    id, jurisdiction_id, country, authority_code, parcel_number,
    normalized_parcel_number
)
VALUES (
    '70000000-0000-0000-0000-000000000103',
    '40000000-0000-0000-0000-000000000001',
    'US', '13121', '17 010000010999', '17010000010999'
);

SELECT throws_ok(
    $$
        INSERT INTO property_parcels (property_id, parcel_id, is_primary, started_on)
        VALUES (
            '60000000-0000-0000-0000-000000000001',
            '70000000-0000-0000-0000-000000000103',
            TRUE,
            '2024-01-01'
        )
    $$,
    '23505'::CHAR(5),
    NULL,
    'a property cannot have two current primary parcels'
);

SELECT lives_ok(
    $$
        INSERT INTO property_parcels (property_id, parcel_id, is_primary, started_on)
        VALUES (
            '60000000-0000-0000-0000-000000000001',
            '70000000-0000-0000-0000-000000000103',
            FALSE,
            '2024-01-01'
        )
    $$,
    'a property can have an additional current non-primary parcel'
);

SELECT throws_ok(
    $$
        INSERT INTO source_records (
            provider_id, record_kind, property_id, provider_record_id,
            raw_payload
        )
        VALUES (
            '20000000-0000-0000-0000-000000000001',
            'property',
            '60000000-0000-0000-0000-000000000001',
            '00012aa9e1f3582e',
            '{}'
        )
    $$,
    '23505'::CHAR(5),
    NULL,
    'only one current source record exists per provider, kind, and provider record ID'
);

SELECT lives_ok(
    $$
        INSERT INTO source_records (
            provider_id, record_kind, property_id, provider_record_id,
            version, is_current, raw_payload
        )
        VALUES (
            '20000000-0000-0000-0000-000000000001',
            'property',
            '60000000-0000-0000-0000-000000000001',
            '00012aa9e1f3582e',
            0,
            FALSE,
            '{}'
        )
    $$,
    'non-current source record versions can be retained'
);

SELECT throws_ok(
    $$
        INSERT INTO property_identifiers (
            property_id, scheme, namespace, value
        )
        VALUES (
            '60000000-0000-0000-0000-000000000002',
            'dev_seed_address_id',
            'dev_seed',
            '00012aa9e1f3582e'
        )
    $$,
    '23505'::CHAR(5),
    NULL,
    'external identifiers are unique within scheme and namespace'
);

SELECT lives_ok(
    $$
        INSERT INTO property_identifiers (
            property_id, scheme, namespace, value
        )
        VALUES (
            '60000000-0000-0000-0000-000000000002',
            'dev_seed_address_id',
            'other_seed',
            '00012aa9e1f3582e'
        )
    $$,
    'the same external identifier value can exist in another namespace'
);

SELECT throws_ok(
    $$
        INSERT INTO ownership_periods (
            property_id, started_on, ended_on, verification_status
        )
        VALUES (
            '60000000-0000-0000-0000-000000000001',
            '2020-01-01',
            '2022-01-01',
            'verified'
        )
    $$,
    '23P01'::CHAR(5),
    NULL,
    'verified ownership periods cannot overlap'
);

SELECT lives_ok(
    $$
        INSERT INTO ownership_periods (
            property_id, started_on, ended_on, verification_status
        )
        VALUES (
            '60000000-0000-0000-0000-000000000001',
            '2020-01-01',
            '2022-01-01',
            'unverified'
        )
    $$,
    'unverified ownership periods may overlap while reconciliation is pending'
);

SELECT throws_ok(
    $$
        INSERT INTO tax_bills (
            parcel_id, jurisdiction_id, tax_year, bill_number
        )
        VALUES (
            '70000000-0000-0000-0000-000000000001',
            '40000000-0000-0000-0000-000000000001',
            2024,
            NULL
        )
    $$,
    '23505'::CHAR(5),
    NULL,
    'unnumbered tax bills are unique per parcel, jurisdiction, and year'
);

SELECT throws_ok(
    $$
        INSERT INTO assessments (
            parcel_id, jurisdiction_id, tax_year, roll_type
        )
        VALUES (
            '70000000-0000-0000-0000-000000000001',
            '40000000-0000-0000-0000-000000000001',
            2024,
            'original'
        )
    $$,
    '23505'::CHAR(5),
    NULL,
    'assessment original roll is unique per parcel, jurisdiction, and year'
);

SELECT lives_ok(
    $$
        INSERT INTO assessments (
            parcel_id, jurisdiction_id, tax_year, roll_type
        )
        VALUES (
            '70000000-0000-0000-0000-000000000001',
            '40000000-0000-0000-0000-000000000001',
            2024,
            'corrected'
        )
    $$,
    'assessment corrected roll can coexist with original roll'
);

SELECT throws_ok(
    $$
        INSERT INTO property_sales (property_id, sale_date, sale_price)
        VALUES ('60000000-0000-0000-0000-000000000001', '2024-01-01', -1)
    $$,
    '23514'::CHAR(5),
    NULL,
    'sale price cannot be negative'
);

SELECT throws_ok(
    $$
        INSERT INTO property_sales (property_id, sale_date, sale_price, cap_rate)
        VALUES ('60000000-0000-0000-0000-000000000006', '2024-01-01', 1, 100.01)
    $$,
    '23514'::CHAR(5),
    NULL,
    'cap rate is bounded to 0 through 100 percent'
);

SELECT throws_ok(
    $$
        INSERT INTO property_leases (
            property_id, commencement_date, expiration_date
        )
        VALUES (
            '60000000-0000-0000-0000-000000000006',
            '2025-01-01',
            '2024-01-01'
        )
    $$,
    '23514'::CHAR(5),
    NULL,
    'lease expiration must be after commencement'
);

SELECT throws_ok(
    $$
        INSERT INTO property_leases (
            property_id, commencement_date, free_rent_months
        )
        VALUES (
            '60000000-0000-0000-0000-000000000006',
            '2025-01-01',
            -1
        )
    $$,
    '23514'::CHAR(5),
    NULL,
    'free rent months cannot be negative'
);

SELECT throws_ok(
    $$
        INSERT INTO rent_escalations (
            lease_id, escalation_type, escalation_frequency_months
        )
        VALUES (
            'f2000000-0000-0000-0000-000000000001',
            'fixed_percent',
            0
        )
    $$,
    '23514'::CHAR(5),
    NULL,
    'rent escalation frequency must be positive'
);

SELECT throws_ok(
    $$
        INSERT INTO rent_escalations (
            lease_id, escalation_type, effective_from, effective_until
        )
        VALUES (
            'f2000000-0000-0000-0000-000000000001',
            'fixed_percent',
            '2025-01-01',
            '2024-01-01'
        )
    $$,
    '23514'::CHAR(5),
    NULL,
    'rent escalation effective date range must be ordered'
);

SELECT throws_ok(
    $$
        INSERT INTO lease_concessions (
            lease_id, concession_type, abatement_percent
        )
        VALUES (
            'f2000000-0000-0000-0000-000000000001',
            'free_rent',
            100.01
        )
    $$,
    '23514'::CHAR(5),
    NULL,
    'lease concession abatement percent is bounded'
);

SELECT throws_ok(
    $$
        INSERT INTO property_unit_rents (
            property_id, unit_type, rate_amount, observed_on
        )
        VALUES (
            '60000000-0000-0000-0000-000000000004',
            'Studio',
            -100,
            '2024-01-01'
        )
    $$,
    '23514'::CHAR(5),
    NULL,
    'unit rent amount cannot be negative'
);

SELECT throws_ok(
    $$
        INSERT INTO property_listings (
            property_id, listing_kind, list_price
        )
        VALUES (
            '60000000-0000-0000-0000-000000000005',
            'for_sale',
            -1
        )
    $$,
    '23514'::CHAR(5),
    NULL,
    'listing price cannot be negative'
);

SELECT throws_ok(
    $$
        INSERT INTO property_listings (
            property_id, listing_kind, listed_on, status_changed_on
        )
        VALUES (
            '60000000-0000-0000-0000-000000000005',
            'for_sale',
            '2024-03-01',
            '2024-02-01'
        )
    $$,
    '23514'::CHAR(5),
    NULL,
    'listing status date cannot precede listing date'
);

SELECT throws_ok(
    $$
        INSERT INTO structures (property_id, gross_area)
        VALUES ('60000000-0000-0000-0000-000000000006', -1)
    $$,
    '23514'::CHAR(5),
    NULL,
    'structure gross area must be positive when present'
);

SELECT throws_ok(
    $$
        INSERT INTO spaces (property_id, space_identifier, rentable_area)
        VALUES ('60000000-0000-0000-0000-000000000006', 'Bad Space', -1)
    $$,
    '23514'::CHAR(5),
    NULL,
    'space rentable area must be positive when present'
);

SELECT throws_ok(
    $$
        INSERT INTO us_zips (zip, city, state_id, location)
        VALUES ('3035', 'Atlanta', 'GA', ST_SetSRID(ST_MakePoint(-84.3, 33.8), 4326)::GEOGRAPHY)
    $$,
    '23514'::CHAR(5),
    NULL,
    'US ZIP codes must be five digits'
);

SELECT throws_ok(
    $$
        INSERT INTO us_zips (zip, city, state_id, location)
        VALUES ('99998', 'Atlanta', 'ga', ST_SetSRID(ST_MakePoint(-84.3, 33.8), 4326)::GEOGRAPHY)
    $$,
    '23514'::CHAR(5),
    NULL,
    'US ZIP state IDs must be uppercase postal abbreviations'
);

SELECT throws_ok(
    $$
        INSERT INTO reference_dataset_loads (dataset, version, row_count)
        VALUES ('us_zips', '1.96', -1)
    $$,
    '23514'::CHAR(5),
    NULL,
    'reference dataset load row count cannot be negative'
);

-- synthetic dataset name so the test cannot collide with real us_zips loads
INSERT INTO reference_dataset_loads (dataset, version, source_url, row_count, loaded_at)
VALUES
    ('pgtap_probe_zips', '1.95.1', 'https://example.com/v1.95.1.zip', 33782,
     '2026-01-01T00:00:00Z'),
    ('pgtap_probe_zips', '1.96', 'https://example.com/v1.96.zip', 33790,
     '2026-07-01T00:00:00Z');

SELECT is(
    (
        SELECT DISTINCT ON (dataset) version
        FROM reference_dataset_loads
        WHERE dataset = 'pgtap_probe_zips'
        ORDER BY dataset, loaded_at DESC
    ),
    '1.96',
    'most recent load per dataset reports the currently loaded version'
);

SELECT throws_ok(
    $$
        INSERT INTO property_transfers (property_id, transfer_kind, consideration)
        VALUES ('60000000-0000-0000-0000-000000000001', 'warranty_deed', -1)
    $$,
    '23514'::CHAR(5),
    NULL,
    'transfer consideration cannot be negative'
);

SELECT throws_ok(
    $$
        INSERT INTO property_mortgages (property_id, loan_amount, interest_rate)
        VALUES ('60000000-0000-0000-0000-000000000002', 500000, -0.5)
    $$,
    '23514'::CHAR(5),
    NULL,
    'mortgage interest rate cannot be negative'
);

SELECT throws_ok(
    $$
        INSERT INTO assessments (
            parcel_id, jurisdiction_id, tax_year, roll_type, assessed_total
        )
        VALUES (
            '70000000-0000-0000-0000-000000000003',
            '40000000-0000-0000-0000-000000000002',
            2024,
            'original',
            -1
        )
    $$,
    '23514'::CHAR(5),
    NULL,
    'assessed values cannot be negative'
);

SELECT throws_ok(
    $$
        INSERT INTO tax_bills (
            parcel_id, jurisdiction_id, tax_year, bill_number, amount_billed
        )
        VALUES (
            '70000000-0000-0000-0000-000000000003',
            '40000000-0000-0000-0000-000000000002',
            2024,
            'TB-2024-TEST',
            -1
        )
    $$,
    '23514'::CHAR(5),
    NULL,
    'tax bill amounts cannot be negative'
);

SELECT throws_ok(
    $$
        INSERT INTO residential_details (property_id, year_built, year_renovated)
        VALUES ('60000000-0000-0000-0000-000000000007', 1938, 1930)
    $$,
    '23514'::CHAR(5),
    NULL,
    'residential renovation year cannot precede year built'
);

SELECT throws_ok(
    $$
        INSERT INTO commercial_details (property_id, year_built, year_renovated)
        VALUES ('60000000-0000-0000-0000-000000000007', 1999, 1980)
    $$,
    '23514'::CHAR(5),
    NULL,
    'commercial renovation year cannot precede year built'
);

SELECT throws_ok(
    $$
        INSERT INTO structures (property_id, year_built, year_renovated)
        VALUES ('60000000-0000-0000-0000-000000000007', 1999, 1980)
    $$,
    '23514'::CHAR(5),
    NULL,
    'structure renovation year cannot precede year built'
);

SELECT throws_ok(
    $$
        INSERT INTO income_expense_statements (
            property_id, statement_year, opex_total
        )
        VALUES ('60000000-0000-0000-0000-000000000006', 2024, -1)
    $$,
    '23514'::CHAR(5),
    NULL,
    'income statement operating expenses cannot be negative'
);

SELECT throws_ok(
    $$
        INSERT INTO owner_contacts (owner_id, kind, value)
        VALUES ('90000000-0000-0000-0000-000000000002', 'fax', '+1-404-555-0101')
    $$,
    '23514'::CHAR(5),
    NULL,
    'owner contact kind is constrained to supported contact point types'
);

SELECT throws_ok(
    $$
        INSERT INTO valuations (
            property_id, valuation_kind, value_amount, value_high, as_of_date
        )
        VALUES (
            '60000000-0000-0000-0000-000000000001',
            'appraisal',
            100,
            99,
            '2024-01-01'
        )
    $$,
    '23514'::CHAR(5),
    NULL,
    'valuation high bound cannot be below reconciled value'
);

SELECT throws_ok(
    $$
        INSERT INTO property_sales (property_id, sale_date, sale_type)
        VALUES ('60000000-0000-0000-0000-000000000001', '2024-01-01', 'not_a_sale_type')
    $$,
    '22P02'::CHAR(5),
    NULL,
    'sale type must be a valid enum value'
);

SELECT throws_ok(
    $$
        INSERT INTO source_records (
            provider_id, record_kind, confidence_score, raw_payload
        )
        VALUES (
            '20000000-0000-0000-0000-000000000001',
            'property',
            101,
            '{}'
        )
    $$,
    '23514'::CHAR(5),
    NULL,
    'source record confidence score is bounded'
);

SELECT throws_ok(
    $$
        INSERT INTO ownership_interests (
            ownership_period_id, owner_id, ownership_pct
        )
        VALUES (
            'b0000000-0000-0000-0000-000000000002',
            '90000000-0000-0000-0000-000000000001',
            100.001
        )
    $$,
    '23514'::CHAR(5),
    NULL,
    'single ownership interest cannot exceed 100 percent'
);

SELECT throws_ok(
    $$
        INSERT INTO spaces (property_id, space_identifier)
        VALUES ('60000000-0000-0000-0000-000000000006', 'Suite 1200')
    $$,
    '23505'::CHAR(5),
    NULL,
    'space identifiers are unique per property'
);

SELECT throws_ok(
    $$
        INSERT INTO data_verifications (
            verifiable_type, verifiable_id, verification_method, verified_by_id
        )
        VALUES (
            'not_a_verifiable_type',
            '60000000-0000-0000-0000-000000000001',
            'manual',
            '10000000-0000-0000-0000-000000000001'
        )
    $$,
    '23514'::CHAR(5),
    NULL,
    'verification type is constrained to modeled verifiable records'
);

SELECT throws_ok(
    $$
        INSERT INTO users (email)
        VALUES ('APPRAISER@example.com')
    $$,
    '23505'::CHAR(5),
    NULL,
    'user emails are unique case-insensitively (citext)'
);

SELECT throws_ok(
    $$
        INSERT INTO addresses (country, address_hash)
        VALUES ('us', 'constraint-test-lowercase-country')
    $$,
    '23514'::CHAR(5),
    NULL,
    'address country codes must be uppercase ISO 3166-1 alpha-2'
);

SELECT throws_ok(
    $$
        INSERT INTO addresses (country, address_hash)
        VALUES ('US', 'dev-seed:00012aa9e1f3582e')
    $$,
    '23505'::CHAR(5),
    NULL,
    'address dedupe hash is unique'
);

SELECT throws_ok(
    $$
        INSERT INTO comp_set_items (comp_set_id, comp_kind, comp_id)
        VALUES (
            'f9000000-0000-0000-0000-000000000001',
            'sale',
            'f0000000-0000-0000-0000-000000000002'
        )
    $$,
    '23505'::CHAR(5),
    NULL,
    'the same comp cannot be added to a comp set twice'
);

SELECT throws_ok(
    $$
        INSERT INTO valuations (
            property_id, valuation_kind, value_amount, value_low, as_of_date
        )
        VALUES (
            '60000000-0000-0000-0000-000000000001',
            'appraisal',
            100,
            101,
            '2024-01-01'
        )
    $$,
    '23514'::CHAR(5),
    NULL,
    'valuation low bound cannot exceed reconciled value'
);

SELECT throws_ok(
    $$
        INSERT INTO source_records (
            provider_id, record_kind, match_confidence, raw_payload
        )
        VALUES (
            '20000000-0000-0000-0000-000000000001',
            'property',
            1.01,
            '{}'
        )
    $$,
    '23514'::CHAR(5),
    NULL,
    'source record match confidence is bounded to 0 through 1'
);

SELECT throws_ok(
    $$
        INSERT INTO parcel_lineage (
            predecessor_parcel_id, successor_parcel_id, kind
        )
        VALUES (
            '70000000-0000-0000-0000-000000000001',
            '70000000-0000-0000-0000-000000000001',
            'renumber'
        )
    $$,
    '23514'::CHAR(5),
    NULL,
    'a parcel cannot be its own lineage successor'
);

INSERT INTO parcel_lineage (predecessor_parcel_id, successor_parcel_id, kind)
VALUES (
    '70000000-0000-0000-0000-000000000101',
    '70000000-0000-0000-0000-000000000103',
    'renumber'
);

SELECT throws_ok(
    $$
        INSERT INTO parcel_lineage (
            predecessor_parcel_id, successor_parcel_id, kind
        )
        VALUES (
            '70000000-0000-0000-0000-000000000101',
            '70000000-0000-0000-0000-000000000103',
            'split'
        )
    $$,
    '23505'::CHAR(5),
    NULL,
    'a parcel lineage edge is recorded only once'
);

SELECT throws_ok(
    $$
        INSERT INTO property_unit_rents (
            property_id, unit_type, unit_area, rate_amount, observed_on
        )
        VALUES (
            '60000000-0000-0000-0000-000000000004',
            'Studio',
            0,
            1500,
            '2024-01-01'
        )
    $$,
    '23514'::CHAR(5),
    NULL,
    'unit rent area must be positive when present'
);

SELECT throws_ok(
    $$
        INSERT INTO commercial_details (property_id, occupancy_pct)
        VALUES ('60000000-0000-0000-0000-000000000007', 100.01)
    $$,
    '23514'::CHAR(5),
    NULL,
    'occupancy percentage is bounded to 0 through 100'
);

SELECT throws_ok(
    $$
        INSERT INTO ownership_interests (ownership_period_id, owner_id, ownership_pct)
        VALUES (
            'b0000000-0000-0000-0000-000000000002',
            '90000000-0000-0000-0000-000000000002',
            50.000
        )
    $$,
    '23505'::CHAR(5),
    NULL,
    'an owner appears at most once per ownership period'
);

SELECT throws_ok(
    $$
        INSERT INTO jurisdictions (country, region, name, kind, authority_code)
        VALUES ('US', 'GA', 'Fulton County Duplicate', 'county', '13121')
    $$,
    '23505'::CHAR(5),
    NULL,
    'jurisdiction authority codes are unique per country and kind'
);

SELECT throws_ok(
    $$
        INSERT INTO rent_escalations (
            lease_id, escalation_type, cpi_floor, cpi_cap
        )
        VALUES (
            'f2000000-0000-0000-0000-000000000001',
            'cpi',
            3.0,
            2.0
        )
    $$,
    '23514'::CHAR(5),
    NULL,
    'CPI escalation cap cannot be below its floor'
);

SELECT * FROM finish();

ROLLBACK;
