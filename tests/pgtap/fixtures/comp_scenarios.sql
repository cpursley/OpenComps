-- Scenario extensions layered on fixtures/atlanta_records.sql.
-- Each block exercises a slice of the schema the base fixture leaves cold:
--
--   A. Emory Point multifamily full stack: DeKalb assessment + tax bill,
--      JV ownership (GP/LP split), CMBS debt with near-term maturity,
--      sale comp with per-unit metrics, vendor AVM with confidence range
--   B. 1007-style residential rent comp on the Grant Park bungalow
--   C. Westpark industrial: active listing closes to a recorded sale,
--      ownership turnover, NNN lease, delinquent tax bill, and a
--      post-sale parcel split (property UUID survives parcel churn)
--   D. 2500 Peachtree condo unit sub-parcel (RESO UPI ':sub:') and unit sale
--   E. Vacant land property: no situs address, land_details, land sale comp
--   F. Mixed-kind comp set (sale + lease + unit_rent, AI-suggested item)

-- ---------------------------------------------------------------------------
-- Shared additions
-- ---------------------------------------------------------------------------
INSERT INTO data_providers (id, code, name, category, kind)
VALUES
    ('20000000-0000-0000-0000-000000000005', 'avm_vendor', 'Metro AVM', 'valuation', 'api');

INSERT INTO owners (id, name, normalized_name, kind)
VALUES
    ('90000000-0000-0000-0000-000000000008', 'Westpark Acquisitions LLC', 'westpark acquisitions llc', 'llc');

INSERT INTO comp_types (id, code, name, primary_unit, secondary_units)
VALUES
    ('30000000-0000-0000-0000-000000000006', 'land', 'Land', 'acre', ARRAY['price_per_acre']);

INSERT INTO property_types (id, code, name, comp_type_id)
VALUES
    ('31000000-0000-0000-0000-000000000006', 'LND_COM', 'Commercial Land', '30000000-0000-0000-0000-000000000006');

-- ---------------------------------------------------------------------------
-- A. Emory Point Apartments (property 4, parcel 4, DeKalb)
-- ---------------------------------------------------------------------------
INSERT INTO property_transfers (
    id, property_id, parcel_id, transfer_kind, recorded_on, effective_on,
    consideration, document_number, grantee_owner_id, verification_status
)
VALUES (
    'a0000000-0000-0000-0000-000000000005',
    '60000000-0000-0000-0000-000000000004',
    '70000000-0000-0000-0000-000000000004',
    'limited_warranty_deed', '2022-07-01', '2022-06-30', 68500000.00,
    'LWD-2022-13089-0855',
    '90000000-0000-0000-0000-000000000007',
    'verified'
);

INSERT INTO ownership_periods (
    id, property_id, started_on, acquired_via_transfer_id, verification_status
)
VALUES (
    'b0000000-0000-0000-0000-000000000005',
    '60000000-0000-0000-0000-000000000004',
    '2022-06-30',
    'a0000000-0000-0000-0000-000000000005',
    'verified'
);

-- institutional JV: operating GP with an LP capital partner
INSERT INTO ownership_interests (ownership_period_id, owner_id, ownership_pct, vesting, role)
VALUES
    ('b0000000-0000-0000-0000-000000000005', '90000000-0000-0000-0000-000000000007', 60.000, 'tenants in common', 'gp'),
    ('b0000000-0000-0000-0000-000000000005', '90000000-0000-0000-0000-000000000006', 40.000, 'tenants in common', 'lp');

INSERT INTO assessments (
    id, parcel_id, jurisdiction_id, tax_year, roll_type, assessed_land,
    assessed_improvements, assessed_total, market_value, taxable_value,
    verification_status
)
VALUES (
    'c0000000-0000-0000-0000-000000000003',
    '70000000-0000-0000-0000-000000000004',
    '40000000-0000-0000-0000-000000000002',
    2024, 'original', 6200000.00, 21300000.00, 27500000.00,
    68750000.00, 27500000.00,
    'verified'
);

INSERT INTO tax_bills (
    id, parcel_id, jurisdiction_id, tax_year, amount_billed, amount_paid,
    due_dates, line_items
)
VALUES (
    'd0000000-0000-0000-0000-000000000002',
    '70000000-0000-0000-0000-000000000004',
    '40000000-0000-0000-0000-000000000002',
    2024, 302500.00, 302500.00,
    '[{"date": "2024-11-15", "amount": 302500.00}]',
    '[{"name": "county", "amount": 195000.00}, {"name": "school", "amount": 107500.00}]'
);

INSERT INTO property_mortgages (
    id, property_id, parcel_id, recording_date, document_number, loan_amount,
    lender_name, borrower_owner_id, loan_type, interest_rate, term_months,
    maturity_date, lien_position, status, related_transfer_id,
    verification_status
)
VALUES (
    'e0000000-0000-0000-0000-000000000002',
    '60000000-0000-0000-0000-000000000004',
    '70000000-0000-0000-0000-000000000004',
    '2022-07-01', 'MTG-2022-13089-0855', 41100000.00,
    'BANK5 2022-5YR22 Mortgage Trust', '90000000-0000-0000-0000-000000000007',
    'cmbs', 5.320, 60, '2027-07-01', 1, 'active',
    'a0000000-0000-0000-0000-000000000005', 'verified'
);

INSERT INTO property_sales (
    id, property_id, transfer_id, comp_type_id, sale_date, sale_price,
    sale_type, buyer_name, seller_name, cap_rate, noi, metrics,
    contributed_by_id, verification_status
)
VALUES (
    'f0000000-0000-0000-0000-000000000004',
    '60000000-0000-0000-0000-000000000004',
    'a0000000-0000-0000-0000-000000000005',
    '30000000-0000-0000-0000-000000000004',
    '2022-06-30', 68500000.00, 'arms_length',
    'Emory Point Owner LLC', NULL, 4.90, 3356500.00,
    '{"price_per_unit": 428125, "unit_count": 160}',
    '10000000-0000-0000-0000-000000000001', 'verified'
);

INSERT INTO source_records (
    id, provider_id, record_kind, property_id, provider_record_id,
    raw_payload, normalized_fields
)
VALUES (
    '80000000-0000-0000-0000-000000000004',
    '20000000-0000-0000-0000-000000000005', 'avm',
    '60000000-0000-0000-0000-000000000004',
    'AVM-EMORY-2026',
    '{"value": 72400000, "low": 68100000, "high": 76900000}',
    '{"value_amount": 72400000}'
);

INSERT INTO valuations (
    id, property_id, valuation_kind, value_type, value_amount, value_low,
    value_high, confidence_score, as_of_date, source_record_id
)
VALUES (
    'f7000000-0000-0000-0000-000000000002',
    '60000000-0000-0000-0000-000000000004',
    'avm', 'market_value', 72400000.00, 68100000.00, 76900000.00,
    78, '2026-06-01',
    '80000000-0000-0000-0000-000000000004'
);

-- ---------------------------------------------------------------------------
-- B. 1007-style monthly rent comp: the Grant Park bungalow rents as an SFR
-- ---------------------------------------------------------------------------
INSERT INTO property_unit_rents (
    id, property_id, comp_type_id, unit_type, unit_area, bedrooms, bathrooms,
    unit_count, rate_amount, rate_period, rate_basis, rate_type, observed_on,
    contributed_by_id, verification_status
)
VALUES (
    'f5000000-0000-0000-0000-000000000003',
    '60000000-0000-0000-0000-000000000002',
    '30000000-0000-0000-0000-000000000001',
    'SFR 3/2', 1580, 3, 2.0, 1, 2400.00, 'monthly', 'per_unit', 'contract',
    '2024-06-01',
    '10000000-0000-0000-0000-000000000001', 'verified'
);

-- ---------------------------------------------------------------------------
-- C. Westpark Industrial Flex (property 5, parcel 5, Fulton)
-- ---------------------------------------------------------------------------
-- the active listing closes...
UPDATE property_listings
SET status = 'sold',
    status_changed_on = '2024-09-15',
    close_price = 7050000.00
WHERE id = 'f6000000-0000-0000-0000-000000000001';

-- ...into a recorded market sale
INSERT INTO property_transfers (
    id, property_id, parcel_id, transfer_kind, recorded_on, effective_on,
    consideration, document_number, grantor_owner_id, grantee_owner_id,
    verification_status
)
VALUES (
    'a0000000-0000-0000-0000-000000000006',
    '60000000-0000-0000-0000-000000000005',
    '70000000-0000-0000-0000-000000000005',
    'warranty_deed', '2024-09-16', '2024-09-15', 7050000.00,
    'WD-2024-13121-4125',
    '90000000-0000-0000-0000-000000000005',
    '90000000-0000-0000-0000-000000000008',
    'verified'
);

INSERT INTO ownership_periods (
    id, property_id, started_on, ended_on, acquired_via_transfer_id,
    disposed_via_transfer_id, verification_status
)
VALUES
    (
        'b0000000-0000-0000-0000-000000000006',
        '60000000-0000-0000-0000-000000000005',
        '2019-01-01', '2024-09-15', NULL,
        'a0000000-0000-0000-0000-000000000006', 'verified'
    ),
    (
        'b0000000-0000-0000-0000-000000000007',
        '60000000-0000-0000-0000-000000000005',
        '2024-09-15', NULL,
        'a0000000-0000-0000-0000-000000000006', NULL, 'verified'
    );

INSERT INTO ownership_interests (ownership_period_id, owner_id, ownership_pct, vesting, role)
VALUES
    ('b0000000-0000-0000-0000-000000000006', '90000000-0000-0000-0000-000000000005', 100.000, 'fee simple', 'owner'),
    ('b0000000-0000-0000-0000-000000000007', '90000000-0000-0000-0000-000000000008', 100.000, 'fee simple', 'owner');

INSERT INTO property_sales (
    id, property_id, transfer_id, comp_type_id, sale_date, sale_price,
    sale_type, buyer_name, seller_name, price_per_area, metrics,
    contributed_by_id, verification_status
)
VALUES (
    'f0000000-0000-0000-0000-000000000005',
    '60000000-0000-0000-0000-000000000005',
    'a0000000-0000-0000-0000-000000000006',
    '30000000-0000-0000-0000-000000000005',
    '2024-09-15', 7050000.00, 'arms_length',
    'Westpark Acquisitions LLC', 'Westpark Industrial LLC', 130.56,
    '{"clear_height_ft": 24}',
    '10000000-0000-0000-0000-000000000001', 'verified'
);

-- industrial physical specifics the base fixture left unset
UPDATE commercial_details
SET clear_height = 24.0,
    dock_doors = 12,
    drive_in_doors = 2,
    has_sprinkler = TRUE
WHERE property_id = '60000000-0000-0000-0000-000000000005';

-- the new owner signs an industrial NNN lease
INSERT INTO property_leases (
    id, property_id, comp_type_id, lessee_name, lessee_industry,
    landlord_name, lease_type, transaction_type, execution_date,
    commencement_date, expiration_date, term_months, leased_area,
    rent_amount, rent_period, starting_rent_per_area, annual_rent,
    verification_status
)
VALUES (
    'f2000000-0000-0000-0000-000000000003',
    '60000000-0000-0000-0000-000000000005',
    '30000000-0000-0000-0000-000000000005',
    'Southeast Logistics Co', 'logistics', 'Westpark Acquisitions LLC',
    'triple_net', 'new_lease', '2024-10-01',
    '2024-11-01', '2029-10-31', 60, 27000,
    8.75, 'per_area_annual', 8.75, 236250.00,
    'verified'
);

-- prior-year taxes went delinquent under the old owner
INSERT INTO tax_bills (
    id, parcel_id, jurisdiction_id, tax_year, amount_billed, amount_paid,
    is_delinquent, delinquent_amount, due_dates, line_items
)
VALUES (
    'd0000000-0000-0000-0000-000000000003',
    '70000000-0000-0000-0000-000000000005',
    '40000000-0000-0000-0000-000000000001',
    2023, 98400.00, 0.00,
    TRUE, 104300.00,
    '[{"date": "2023-10-15", "amount": 98400.00}]',
    '[{"name": "county", "amount": 61000.00}, {"name": "school", "amount": 37400.00}]'
);

-- county splits the parcel post-sale; property UUID survives the churn
UPDATE parcels
SET retired_on = '2025-01-15'
WHERE id = '70000000-0000-0000-0000-000000000005';

INSERT INTO parcels (
    id, jurisdiction_id, country, authority_code, parcel_number,
    normalized_parcel_number, legal_description, land_area
)
VALUES
    ('70000000-0000-0000-0000-000000000008', '40000000-0000-0000-0000-000000000001', 'US', '13121', '14F 0036 LL0405A', '14F0036LL0405A', 'Westpark industrial parcel A (split)', 130680),
    ('70000000-0000-0000-0000-000000000009', '40000000-0000-0000-0000-000000000001', 'US', '13121', '14F 0036 LL0405B', '14F0036LL0405B', 'Westpark industrial parcel B (split)', 91476);

INSERT INTO parcel_lineage (predecessor_parcel_id, successor_parcel_id, kind, effective_on)
VALUES
    ('70000000-0000-0000-0000-000000000005', '70000000-0000-0000-0000-000000000008', 'split', '2025-01-15'),
    ('70000000-0000-0000-0000-000000000005', '70000000-0000-0000-0000-000000000009', 'split', '2025-01-15');

UPDATE property_parcels
SET ended_on = '2025-01-15'
WHERE property_id = '60000000-0000-0000-0000-000000000005'
  AND parcel_id = '70000000-0000-0000-0000-000000000005';

INSERT INTO property_parcels (property_id, parcel_id, is_primary, started_on)
VALUES
    ('60000000-0000-0000-0000-000000000005', '70000000-0000-0000-0000-000000000008', TRUE, '2025-01-15'),
    ('60000000-0000-0000-0000-000000000005', '70000000-0000-0000-0000-000000000009', FALSE, '2025-01-15');

-- ---------------------------------------------------------------------------
-- D. 2500 Peachtree condo unit sub-parcel (property 7)
-- ---------------------------------------------------------------------------
INSERT INTO parcels (
    id, jurisdiction_id, country, authority_code, parcel_number,
    normalized_parcel_number, unit_designator, legal_description
)
VALUES (
    '70000000-0000-0000-0000-000000000010',
    '40000000-0000-0000-0000-000000000001',
    'US', '13121', '17 010100080250', '17010100080250', '1204',
    'Peachtree condominium unit 1204'
);

INSERT INTO property_parcels (property_id, parcel_id, is_primary, started_on)
VALUES (
    '60000000-0000-0000-0000-000000000007',
    '70000000-0000-0000-0000-000000000010',
    FALSE, '2021-01-01'
);

INSERT INTO property_sales (
    id, property_id, comp_type_id, sale_date, sale_price, sale_type,
    buyer_name, metrics, contributed_by_id, verification_status
)
VALUES (
    'f0000000-0000-0000-0000-000000000006',
    '60000000-0000-0000-0000-000000000007',
    '30000000-0000-0000-0000-000000000001',
    '2024-08-15', 410000.00, 'arms_length',
    'Private Buyer', '{"unit": "1204"}',
    '10000000-0000-0000-0000-000000000001', 'verified'
);

-- ---------------------------------------------------------------------------
-- E. Vacant commercial land: no situs address, land_details, land sale comp
-- ---------------------------------------------------------------------------
INSERT INTO properties (id, name, property_type_id, location, metadata)
VALUES (
    '60000000-0000-0000-0000-000000000008',
    'Fulton Industrial Blvd Land',
    '31000000-0000-0000-0000-000000000006',
    ST_SetSRID(ST_MakePoint(-84.5701, 33.7402), 4326)::GEOGRAPHY,
    '{"seed_source_id": "comp_scenarios_land"}'
);

INSERT INTO parcels (
    id, jurisdiction_id, country, authority_code, parcel_number,
    normalized_parcel_number, legal_description, land_area
)
VALUES (
    '70000000-0000-0000-0000-000000000011',
    '40000000-0000-0000-0000-000000000001',
    'US', '13121', '14F 0100 LL0001', '14F0100LL0001',
    'Fulton Industrial Blvd vacant land', 261360
);

INSERT INTO property_parcels (property_id, parcel_id, is_primary, started_on)
VALUES (
    '60000000-0000-0000-0000-000000000008',
    '70000000-0000-0000-0000-000000000011',
    TRUE, '2020-01-01'
);

INSERT INTO land_details (
    property_id, lot_size, zoning, land_use, frontage, topography,
    utilities, flood_zone, entitlement_status, is_corner
)
VALUES (
    '60000000-0000-0000-0000-000000000008',
    261360, 'M-1', 'industrial', 420.0, 'level',
    ARRAY['water', 'sewer', 'electric'], 'X', 'unentitled', TRUE
);

INSERT INTO property_sales (
    id, property_id, comp_type_id, sale_date, sale_price, sale_type,
    buyer_name, metrics, contributed_by_id, verification_status
)
VALUES (
    'f0000000-0000-0000-0000-000000000007',
    '60000000-0000-0000-0000-000000000008',
    '30000000-0000-0000-0000-000000000006',
    '2024-03-01', 1306800.00, 'arms_length',
    'Industrial Land Ventures LLC', '{"price_per_acre": 217800}',
    '10000000-0000-0000-0000-000000000001', 'verified'
);

-- ---------------------------------------------------------------------------
-- F. Mixed-kind comp set supporting the Emory Point valuation
-- ---------------------------------------------------------------------------
INSERT INTO comp_sets (
    id, created_by_id, name, subject_property_id, effective_date, purpose,
    search_criteria
)
VALUES (
    'f9000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000001',
    'Emory Point income capitalization support',
    '60000000-0000-0000-0000-000000000004',
    '2026-06-01', 'appraisal',
    '{"comp_kinds": ["sale", "lease", "unit_rent"]}'
);

INSERT INTO comp_set_items (
    comp_set_id, comp_kind, comp_id, position, selection_source, notes
)
VALUES
    ('f9000000-0000-0000-0000-000000000002', 'sale', 'f0000000-0000-0000-0000-000000000004', 1, 'user', 'subject prior sale'),
    ('f9000000-0000-0000-0000-000000000002', 'unit_rent', 'f5000000-0000-0000-0000-000000000001', 2, 'ai_suggested', 'subject 1BR asking rents'),
    ('f9000000-0000-0000-0000-000000000002', 'lease', 'f2000000-0000-0000-0000-000000000001', 3, 'user', 'office lease for expense context');
