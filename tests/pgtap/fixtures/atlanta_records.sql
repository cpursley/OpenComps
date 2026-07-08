-- Atlanta-area fixture records built from real, public-record addresses.

INSERT INTO users (id, email, display_name)
VALUES
    ('10000000-0000-0000-0000-000000000001', 'appraiser@example.com', 'Atlanta Appraiser'),
    ('10000000-0000-0000-0000-000000000002', 'reviewer@example.com', 'Review Appraiser');

INSERT INTO data_providers (id, code, name, category, kind)
VALUES
    ('20000000-0000-0000-0000-000000000001', 'dev_seed', 'OpenComps Dev Fixture', 'user_contributed', 'bulk_feed'),
    ('20000000-0000-0000-0000-000000000002', 'fulton_assessor', 'Fulton County Board of Assessors', 'public_records', 'bulk_feed'),
    ('20000000-0000-0000-0000-000000000003', 'dekalb_assessor', 'DeKalb County Property Appraisal', 'public_records', 'bulk_feed'),
    ('20000000-0000-0000-0000-000000000004', 'broker_survey', 'Broker Survey', 'market', 'manual');

INSERT INTO jurisdictions (id, country, region, name, kind, authority_code)
VALUES
    ('40000000-0000-0000-0000-000000000001', 'US', 'GA', 'Fulton County', 'county', '13121'),
    ('40000000-0000-0000-0000-000000000002', 'US', 'GA', 'DeKalb County', 'county', '13089'),
    ('40000000-0000-0000-0000-000000000003', 'US', 'GA', 'City of Atlanta', 'municipality', '1304000');

INSERT INTO us_zips (
    zip, city, state_id, state_name, is_zcta, population, density,
    county_fips, county_name, county_weights, county_fips_all,
    county_names_all, timezone, location
)
VALUES
    (
        '30305', 'Atlanta', 'GA', 'Georgia', TRUE, 28840, 2436.8,
        '13121', 'Fulton', '{"13121": 100.0}', ARRAY['13121'],
        ARRAY['Fulton'], 'America/New_York',
        ST_SetSRID(ST_MakePoint(-84.3855, 33.8312), 4326)::GEOGRAPHY
    ),
    (
        '30307', 'Atlanta', 'GA', 'Georgia', TRUE, 19313, 3030.1,
        '13089', 'DeKalb', '{"13089": 62.0, "13121": 38.0}', ARRAY['13089', '13121'],
        ARRAY['DeKalb', 'Fulton'], 'America/New_York',
        ST_SetSRID(ST_MakePoint(-84.3368, 33.7669), 4326)::GEOGRAPHY
    ),
    (
        '30316', 'Atlanta', 'GA', 'Georgia', TRUE, 37000, 2359.4,
        '13089', 'DeKalb', '{"13089": 73.0, "13121": 27.0}', ARRAY['13089', '13121'],
        ARRAY['DeKalb', 'Fulton'], 'America/New_York',
        ST_SetSRID(ST_MakePoint(-84.3330, 33.7390), 4326)::GEOGRAPHY
    ),
    (
        '30336', 'Atlanta', 'GA', 'Georgia', TRUE, 2100, 323.4,
        '13121', 'Fulton', '{"13121": 100.0}', ARRAY['13121'],
        ARRAY['Fulton'], 'America/New_York',
        ST_SetSRID(ST_MakePoint(-84.5586, 33.7348), 4326)::GEOGRAPHY
    )
ON CONFLICT (zip) DO NOTHING;

INSERT INTO classification_taxonomies (id, code, name, version)
VALUES
    ('32000000-0000-0000-0000-000000000001', 'uad_36', 'Uniform Appraisal Dataset', '3.6');

INSERT INTO comp_types (id, code, name, primary_unit, secondary_units)
VALUES
    ('30000000-0000-0000-0000-000000000001', 'residential', 'Residential', 'square_feet', ARRAY['bedrooms', 'bathrooms']),
    ('30000000-0000-0000-0000-000000000002', 'office', 'Office', 'rentable_square_feet', ARRAY['cap_rate', 'noi']),
    ('30000000-0000-0000-0000-000000000003', 'retail', 'Retail', 'rentable_square_feet', ARRAY['frontage']),
    ('30000000-0000-0000-0000-000000000004', 'multifamily', 'Multifamily', 'unit', ARRAY['bedrooms', 'monthly_rent']),
    ('30000000-0000-0000-0000-000000000005', 'industrial', 'Industrial', 'rentable_square_feet', ARRAY['clear_height']);

INSERT INTO property_types (id, code, name, comp_type_id)
VALUES
    ('31000000-0000-0000-0000-000000000001', 'RES_SFD', 'Single Family Detached', '30000000-0000-0000-0000-000000000001'),
    ('31000000-0000-0000-0000-000000000002', 'COM_OFF', 'Office Building', '30000000-0000-0000-0000-000000000002'),
    ('31000000-0000-0000-0000-000000000003', 'COM_RET', 'Retail Storefront', '30000000-0000-0000-0000-000000000003'),
    ('31000000-0000-0000-0000-000000000004', 'MF_MID', 'Mid-Rise Multifamily', '30000000-0000-0000-0000-000000000004'),
    ('31000000-0000-0000-0000-000000000005', 'COM_IND', 'Industrial Flex', '30000000-0000-0000-0000-000000000005');

INSERT INTO property_type_mappings (property_type_id, taxonomy_id, external_code, external_label)
VALUES
    ('31000000-0000-0000-0000-000000000001', '32000000-0000-0000-0000-000000000001', 'SF', 'Single Family');

INSERT INTO addresses (
    id, street_number, street_name, street_suffix, street_post_directional,
    locality, region, postal_code, admin_area, address_hash, location,
    is_standardized, standardization_source
)
VALUES
    (
        '50000000-0000-0000-0000-000000000001',
        '276', 'Springdale', 'Drive', 'NE', 'Atlanta', 'GA', '30305',
        'Fulton County', 'dev-seed:00012aa9e1f3582e',
        ST_SetSRID(ST_MakePoint(-84.3785038, 33.8220582), 4326)::GEOGRAPHY,
        TRUE, 'dev_seed'
    ),
    (
        '50000000-0000-0000-0000-000000000002',
        '42', 'Atlanta', 'Avenue', 'SE', 'Atlanta', 'GA', '30315',
        'Fulton County', 'dev-seed:000408244211c6e1',
        ST_SetSRID(ST_MakePoint(-84.3865759, 33.7307113), 4326)::GEOGRAPHY,
        TRUE, 'dev_seed'
    ),
    (
        '50000000-0000-0000-0000-000000000003',
        '1221', 'Caroline', 'Street', 'NE', 'Atlanta', 'GA', '30307',
        'DeKalb County', 'dev-seed:00062d8de2084de5',
        ST_SetSRID(ST_MakePoint(-84.3487897, 33.7583189), 4326)::GEOGRAPHY,
        TRUE, 'dev_seed'
    ),
    (
        '50000000-0000-0000-0000-000000000004',
        '855', 'Emory Point', 'Drive', 'NE', 'Atlanta', 'GA', '30329',
        'DeKalb County', 'dev-seed:001497adce8b3b07',
        ST_SetSRID(ST_MakePoint(-84.3290613, 33.8041009), 4326)::GEOGRAPHY,
        TRUE, 'dev_seed'
    ),
    (
        '50000000-0000-0000-0000-000000000005',
        '4125', 'Westpark', 'Drive', 'SW', 'Atlanta', 'GA', '30336',
        'Fulton County', 'dev-seed:0009f7b99e0f128c',
        ST_SetSRID(ST_MakePoint(-84.5634434, 33.7339872), 4326)::GEOGRAPHY,
        TRUE, 'dev_seed'
    ),
    (
        '50000000-0000-0000-0000-000000000006',
        '3324', 'Peachtree', 'Road', 'NE', 'Atlanta', 'GA', '30326',
        'Fulton County', 'dev-seed:00272bf4617da767',
        ST_SetSRID(ST_MakePoint(-84.3693857, 33.8459729), 4326)::GEOGRAPHY,
        TRUE, 'dev_seed'
    ),
    (
        '50000000-0000-0000-0000-000000000007',
        '2500', 'Peachtree', 'Road', 'NW', 'Atlanta', 'GA', '30305',
        'Fulton County', 'dev-seed:002580489a597879',
        ST_SetSRID(ST_MakePoint(-84.3881892, 33.8230297), 4326)::GEOGRAPHY,
        TRUE, 'dev_seed'
    );

INSERT INTO properties (id, name, property_type_id, situs_address_id, location, metadata)
VALUES
    (
        '60000000-0000-0000-0000-000000000001',
        '276 Springdale Drive NE',
        '31000000-0000-0000-0000-000000000001',
        '50000000-0000-0000-0000-000000000001',
        ST_SetSRID(ST_MakePoint(-84.3785038, 33.8220582), 4326)::GEOGRAPHY,
        '{"seed_source_id": "00012aa9e1f3582e"}'
    ),
    (
        '60000000-0000-0000-0000-000000000002',
        '42 Atlanta Avenue SE',
        '31000000-0000-0000-0000-000000000001',
        '50000000-0000-0000-0000-000000000002',
        ST_SetSRID(ST_MakePoint(-84.3865759, 33.7307113), 4326)::GEOGRAPHY,
        '{"seed_source_id": "000408244211c6e1"}'
    ),
    (
        '60000000-0000-0000-0000-000000000003',
        'Caroline Street Retail',
        '31000000-0000-0000-0000-000000000003',
        '50000000-0000-0000-0000-000000000003',
        ST_SetSRID(ST_MakePoint(-84.3487897, 33.7583189), 4326)::GEOGRAPHY,
        '{"seed_source_id": "00062d8de2084de5"}'
    ),
    (
        '60000000-0000-0000-0000-000000000004',
        'Emory Point Apartments',
        '31000000-0000-0000-0000-000000000004',
        '50000000-0000-0000-0000-000000000004',
        ST_SetSRID(ST_MakePoint(-84.3290613, 33.8041009), 4326)::GEOGRAPHY,
        '{"seed_source_id": "001497adce8b3b07"}'
    ),
    (
        '60000000-0000-0000-0000-000000000005',
        'Westpark Industrial Flex',
        '31000000-0000-0000-0000-000000000005',
        '50000000-0000-0000-0000-000000000005',
        ST_SetSRID(ST_MakePoint(-84.5634434, 33.7339872), 4326)::GEOGRAPHY,
        '{"seed_source_id": "0009f7b99e0f128c"}'
    ),
    (
        '60000000-0000-0000-0000-000000000006',
        '3324 Peachtree Office',
        '31000000-0000-0000-0000-000000000002',
        '50000000-0000-0000-0000-000000000006',
        ST_SetSRID(ST_MakePoint(-84.3693857, 33.8459729), 4326)::GEOGRAPHY,
        '{"seed_source_id": "00272bf4617da767"}'
    ),
    (
        '60000000-0000-0000-0000-000000000007',
        '2500 Peachtree Condominium',
        '31000000-0000-0000-0000-000000000004',
        '50000000-0000-0000-0000-000000000007',
        ST_SetSRID(ST_MakePoint(-84.3881892, 33.8230297), 4326)::GEOGRAPHY,
        '{"seed_source_id": "002580489a597879"}'
    );

INSERT INTO parcels (
    id, jurisdiction_id, country, authority_code, parcel_number,
    normalized_parcel_number, legal_description, land_area
)
VALUES
    ('70000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 'US', '13121', '17 010000010276', '17010000010276', 'Springdale Drive residential lot', 18295),
    ('70000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000001', 'US', '13121', '14 005400020042', '14005400020042', 'Atlanta Avenue residential lot', 7841),
    ('70000000-0000-0000-0000-000000000003', '40000000-0000-0000-0000-000000000002', 'US', '13089', '15 210 01 001', '1521001001', 'Caroline Street commercial parcel', 41382),
    ('70000000-0000-0000-0000-000000000004', '40000000-0000-0000-0000-000000000002', 'US', '13089', '18 108 01 055', '1810801055', 'Emory Point multifamily parcel', 148104),
    ('70000000-0000-0000-0000-000000000005', '40000000-0000-0000-0000-000000000001', 'US', '13121', '14F 0036 LL0405', '14F0036LL0405', 'Westpark industrial parcel', 222156),
    ('70000000-0000-0000-0000-000000000006', '40000000-0000-0000-0000-000000000001', 'US', '13121', '17 004400050324', '17004400050324', 'Peachtree office parcel', 52272),
    ('70000000-0000-0000-0000-000000000007', '40000000-0000-0000-0000-000000000001', 'US', '13121', '17 010100080250', '17010100080250', 'Peachtree condominium parcel', 15246);

INSERT INTO property_parcels (property_id, parcel_id, is_primary, started_on)
VALUES
    ('60000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000001', TRUE, '2018-06-15'),
    ('60000000-0000-0000-0000-000000000002', '70000000-0000-0000-0000-000000000002', TRUE, '2020-02-01'),
    ('60000000-0000-0000-0000-000000000003', '70000000-0000-0000-0000-000000000003', TRUE, '2019-01-01'),
    ('60000000-0000-0000-0000-000000000004', '70000000-0000-0000-0000-000000000004', TRUE, '2019-01-01'),
    ('60000000-0000-0000-0000-000000000005', '70000000-0000-0000-0000-000000000005', TRUE, '2019-01-01'),
    ('60000000-0000-0000-0000-000000000006', '70000000-0000-0000-0000-000000000006', TRUE, '2019-01-01'),
    ('60000000-0000-0000-0000-000000000007', '70000000-0000-0000-0000-000000000007', TRUE, '2021-01-01');

INSERT INTO property_identifiers (property_id, scheme, namespace, value, provider_id)
VALUES
    ('60000000-0000-0000-0000-000000000001', 'dev_seed_address_id', 'dev_seed', '00012aa9e1f3582e', '20000000-0000-0000-0000-000000000001'),
    ('60000000-0000-0000-0000-000000000003', 'dev_seed_address_id', 'dev_seed', '00062d8de2084de5', '20000000-0000-0000-0000-000000000001'),
    ('60000000-0000-0000-0000-000000000006', 'dev_seed_address_id', 'dev_seed', '00272bf4617da767', '20000000-0000-0000-0000-000000000001');

INSERT INTO source_records (
    id, provider_id, record_kind, dataset, jurisdiction_id, property_id,
    parcel_id, provider_record_id, version, is_current, superseded_by_id,
    raw_payload, normalized_fields, match_method, match_confidence,
    completeness_score, confidence_score
)
VALUES
    (
        '80000000-0000-0000-0000-000000000001',
        '20000000-0000-0000-0000-000000000001', 'property', 'dev_addresses',
        '40000000-0000-0000-0000-000000000001',
        '60000000-0000-0000-0000-000000000001',
        '70000000-0000-0000-0000-000000000001',
        '00012aa9e1f3582e', 2, TRUE, NULL,
        '{"location_address": "276 Springdale Drive NE, Atlanta, GA 30305", "lon": "-84.3785038", "lat": "33.8220582"}',
        '{"postal_code": "30305", "locality": "Atlanta", "region": "GA"}',
        'address_geocode', 0.99, 96, 94
    ),
    (
        '80000000-0000-0000-0000-000000000002',
        '20000000-0000-0000-0000-000000000001', 'property', 'dev_addresses',
        '40000000-0000-0000-0000-000000000001',
        '60000000-0000-0000-0000-000000000001',
        '70000000-0000-0000-0000-000000000001',
        '00012aa9e1f3582e', 1, FALSE,
        '80000000-0000-0000-0000-000000000001',
        '{"location_address": "276 Springdale Dr NE, Atlanta GA"}',
        '{"postal_code": "30305"}',
        'fuzzy_address', 0.82, 75, 71
    ),
    (
        '80000000-0000-0000-0000-000000000003',
        '20000000-0000-0000-0000-000000000002', 'assessment', 'tax_roll_2024',
        '40000000-0000-0000-0000-000000000001',
        '60000000-0000-0000-0000-000000000001',
        '70000000-0000-0000-0000-000000000001',
        '17 010000010276:2024', 1, TRUE, NULL,
        '{"tax_year": 2024, "assessed_total": 612000}',
        '{"tax_year": 2024, "assessed_total": 612000}',
        'exact_parcel', 1.00, 98, 96
    );

INSERT INTO residential_details (
    property_id, gla, bedrooms, bathrooms, bathrooms_full, bathrooms_half,
    total_rooms, stories, year_built, garage_spaces, fireplaces, lot_size,
    style, condition_rating, quality_rating
)
VALUES
    ('60000000-0000-0000-0000-000000000001', 2860, 4, 3.5, 3, 1, 9, 2.0, 1938, 2, 1, 18295, 'traditional', 'C3', 'Q3'),
    ('60000000-0000-0000-0000-000000000002', 1580, 3, 2.0, 2, 0, 7, 1.0, 1925, 1, 1, 7841, 'bungalow', 'C4', 'Q4');

INSERT INTO commercial_details (
    property_id, rentable_building_area, gross_building_area, land_area,
    stories, year_built, occupancy_pct, parking_spaces, parking_ratio,
    tenancy, building_class, zoning, submarket
)
VALUES
    ('60000000-0000-0000-0000-000000000003', 18500, 20000, 41382, 1, 2006, 96.0, 72, 3.9, 'multi_tenant', 'neighborhood', 'C-1', 'Inman Park'),
    ('60000000-0000-0000-0000-000000000005', 54000, 59000, 222156, 1, 1988, 88.5, 140, 2.6, 'multi_tenant', 'flex', 'M-1', 'I-20 West'),
    ('60000000-0000-0000-0000-000000000006', 215000, 240000, 52272, 18, 1999, 91.5, 640, 3.0, 'multi_tenant', 'A', 'SPI-12', 'Buckhead');

INSERT INTO structures (
    id, property_id, kind, name, structure_number, gross_area, rentable_area,
    floors, year_built, construction_type, elevators
)
VALUES
    ('71000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000003', 'building', 'Caroline Retail Building', '1', 20000, 18500, 1, 2006, 'masonry', 0),
    ('71000000-0000-0000-0000-000000000002', '60000000-0000-0000-0000-000000000005', 'building', 'Westpark Flex Building', '1', 59000, 54000, 1, 1988, 'tilt_up', 0),
    ('71000000-0000-0000-0000-000000000003', '60000000-0000-0000-0000-000000000006', 'building', 'Peachtree Office Tower', '1', 240000, 215000, 18, 1999, 'steel_frame', 6);

INSERT INTO spaces (
    id, property_id, structure_id, space_identifier, floor_number, space_use,
    rentable_area, usable_area, metadata
)
VALUES
    ('72000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000003', '71000000-0000-0000-0000-000000000001', 'Suite 100', 1, 'restaurant', 4200, 3900, '{"frontage": 55}'),
    ('72000000-0000-0000-0000-000000000002', '60000000-0000-0000-0000-000000000003', '71000000-0000-0000-0000-000000000001', 'Suite 120', 1, 'retail', 2600, 2400, '{"frontage": 34}'),
    ('72000000-0000-0000-0000-000000000003', '60000000-0000-0000-0000-000000000006', '71000000-0000-0000-0000-000000000003', 'Suite 1200', 12, 'office', 18500, 17100, '{"view": "city"}'),
    ('72000000-0000-0000-0000-000000000004', '60000000-0000-0000-0000-000000000006', '71000000-0000-0000-0000-000000000003', 'Suite 1400', 14, 'office', 22000, 20400, '{"view": "north"}');

INSERT INTO owners (id, name, normalized_name, kind)
VALUES
    ('90000000-0000-0000-0000-000000000001', 'Springdale Family Trust', 'springdale family trust', 'trust'),
    ('90000000-0000-0000-0000-000000000002', 'Springdale Holdings LLC', 'springdale holdings llc', 'llc'),
    ('90000000-0000-0000-0000-000000000003', 'Grant Park Family Trust', 'grant park family trust', 'trust'),
    ('90000000-0000-0000-0000-000000000004', 'Caroline Retail Partners LLC', 'caroline retail partners llc', 'llc'),
    ('90000000-0000-0000-0000-000000000005', 'Westpark Industrial LLC', 'westpark industrial llc', 'llc'),
    ('90000000-0000-0000-0000-000000000006', 'Peachtree Tower Partners LP', 'peachtree tower partners lp', 'partnership'),
    ('90000000-0000-0000-0000-000000000007', 'Emory Point Owner LLC', 'emory point owner llc', 'llc');

INSERT INTO owner_contacts (
    owner_id, kind, value, label, is_primary, visibility, confidence_score,
    verification_status
)
VALUES
    ('90000000-0000-0000-0000-000000000002', 'email', 'asset.manager@example.com', 'asset manager', TRUE, 'licensed', 86, 'pending_review'),
    ('90000000-0000-0000-0000-000000000004', 'phone', '+1-404-555-0100', 'leasing', TRUE, 'licensed', 78, 'unverified');

INSERT INTO owner_addresses (owner_id, address_id, kind, is_primary, verification_status)
VALUES
    ('90000000-0000-0000-0000-000000000002', '50000000-0000-0000-0000-000000000007', 'mailing', TRUE, 'verified');

INSERT INTO property_transfers (
    id, property_id, parcel_id, transfer_kind, recorded_on, effective_on,
    consideration, document_number, grantor_owner_id, grantee_owner_id,
    verification_status
)
VALUES
    (
        'a0000000-0000-0000-0000-000000000001',
        '60000000-0000-0000-0000-000000000001',
        '70000000-0000-0000-0000-000000000001',
        'warranty_deed', '2021-05-21', '2021-05-20', 745000.00,
        'WD-2021-13121-0001',
        '90000000-0000-0000-0000-000000000001',
        '90000000-0000-0000-0000-000000000002',
        'verified'
    ),
    (
        'a0000000-0000-0000-0000-000000000002',
        '60000000-0000-0000-0000-000000000002',
        '70000000-0000-0000-0000-000000000002',
        'warranty_deed', '2020-02-05', '2020-02-01', 425000.00,
        'WD-2020-13121-0042',
        NULL,
        '90000000-0000-0000-0000-000000000003',
        'verified'
    ),
    (
        'a0000000-0000-0000-0000-000000000003',
        '60000000-0000-0000-0000-000000000002',
        '70000000-0000-0000-0000-000000000002',
        'quitclaim', '2022-08-11', '2022-08-10', 10.00,
        'QC-2022-13121-0042',
        '90000000-0000-0000-0000-000000000003',
        '90000000-0000-0000-0000-000000000003',
        'verified'
    ),
    (
        'a0000000-0000-0000-0000-000000000004',
        '60000000-0000-0000-0000-000000000006',
        '70000000-0000-0000-0000-000000000006',
        'limited_warranty_deed', '2023-09-29', '2023-09-28', 41800000.00,
        'LWD-2023-13121-3324',
        NULL,
        '90000000-0000-0000-0000-000000000006',
        'verified'
    );

INSERT INTO ownership_periods (
    id, property_id, started_on, ended_on, acquired_via_transfer_id,
    disposed_via_transfer_id, verification_status
)
VALUES
    (
        'b0000000-0000-0000-0000-000000000001',
        '60000000-0000-0000-0000-000000000001',
        '2018-06-15', '2021-05-20', NULL,
        'a0000000-0000-0000-0000-000000000001', 'verified'
    ),
    (
        'b0000000-0000-0000-0000-000000000002',
        '60000000-0000-0000-0000-000000000001',
        '2021-05-20', NULL,
        'a0000000-0000-0000-0000-000000000001', NULL, 'verified'
    ),
    (
        'b0000000-0000-0000-0000-000000000003',
        '60000000-0000-0000-0000-000000000002',
        '2022-08-10', NULL,
        'a0000000-0000-0000-0000-000000000003', NULL, 'verified'
    ),
    (
        'b0000000-0000-0000-0000-000000000004',
        '60000000-0000-0000-0000-000000000006',
        '2023-09-28', NULL,
        'a0000000-0000-0000-0000-000000000004', NULL, 'verified'
    );

INSERT INTO ownership_interests (ownership_period_id, owner_id, ownership_pct, vesting, role)
VALUES
    ('b0000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000001', 100.000, 'trust', 'owner'),
    ('b0000000-0000-0000-0000-000000000002', '90000000-0000-0000-0000-000000000002', 100.000, 'fee simple', 'owner'),
    ('b0000000-0000-0000-0000-000000000003', '90000000-0000-0000-0000-000000000003', 100.000, 'trust', 'owner'),
    ('b0000000-0000-0000-0000-000000000004', '90000000-0000-0000-0000-000000000006', 100.000, 'limited partnership', 'owner');

INSERT INTO assessments (
    id, parcel_id, jurisdiction_id, tax_year, roll_type, assessed_land,
    assessed_improvements, assessed_total, market_value, taxable_value,
    source_record_id, verification_status
)
VALUES
    (
        'c0000000-0000-0000-0000-000000000001',
        '70000000-0000-0000-0000-000000000001',
        '40000000-0000-0000-0000-000000000001',
        2024, 'original', 214000.00, 398000.00, 612000.00,
        765000.00, 612000.00,
        '80000000-0000-0000-0000-000000000003', 'verified'
    ),
    (
        'c0000000-0000-0000-0000-000000000002',
        '70000000-0000-0000-0000-000000000006',
        '40000000-0000-0000-0000-000000000001',
        2024, 'original', 8500000.00, 27400000.00, 35900000.00,
        44875000.00, 35900000.00,
        NULL, 'verified'
    );

INSERT INTO tax_bills (
    id, parcel_id, jurisdiction_id, tax_year, bill_number, amount_billed,
    amount_paid, due_dates, line_items, source_record_id
)
VALUES
    (
        'd0000000-0000-0000-0000-000000000001',
        '70000000-0000-0000-0000-000000000001',
        '40000000-0000-0000-0000-000000000001',
        2024, NULL, 7212.44, 7212.44,
        '[{"date": "2024-10-15", "amount": 7212.44}]',
        '[{"name": "county", "amount": 4210.00}, {"name": "school", "amount": 3002.44}]',
        '80000000-0000-0000-0000-000000000003'
    );

INSERT INTO property_mortgages (
    id, property_id, parcel_id, recording_date, document_number, loan_amount,
    lender_name, borrower_owner_id, loan_type, interest_rate, term_months,
    maturity_date, lien_position, status, related_transfer_id,
    verification_status
)
VALUES
    (
        'e0000000-0000-0000-0000-000000000001',
        '60000000-0000-0000-0000-000000000001',
        '70000000-0000-0000-0000-000000000001',
        '2021-05-21', 'MTG-2021-13121-0001', 596000.00,
        'Peachtree Bank', '90000000-0000-0000-0000-000000000002',
        'fixed_rate', 4.125, 360, '2051-06-01', 1, 'active',
        'a0000000-0000-0000-0000-000000000001', 'verified'
    );

INSERT INTO property_sales (
    id, property_id, transfer_id, comp_type_id, sale_date, sale_price,
    sale_type, buyer_name, seller_name, financing, concessions_amount,
    price_per_area, source_record_id, contributed_by_id, verification_status
)
VALUES
    (
        'f0000000-0000-0000-0000-000000000001',
        '60000000-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000001',
        '30000000-0000-0000-0000-000000000001',
        '2021-05-20', 745000.00, 'arms_length',
        'Springdale Holdings LLC', 'Springdale Family Trust',
        'conventional', 5000.00, 260.49,
        '80000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-000000000001', 'verified'
    ),
    (
        'f0000000-0000-0000-0000-000000000002',
        '60000000-0000-0000-0000-000000000002',
        'a0000000-0000-0000-0000-000000000002',
        '30000000-0000-0000-0000-000000000001',
        '2020-02-01', 425000.00, 'arms_length',
        'Grant Park Family Trust', NULL,
        'cash', 0.00, 268.99,
        NULL, '10000000-0000-0000-0000-000000000001', 'verified'
    ),
    (
        'f0000000-0000-0000-0000-000000000003',
        '60000000-0000-0000-0000-000000000006',
        'a0000000-0000-0000-0000-000000000004',
        '30000000-0000-0000-0000-000000000002',
        '2023-09-28', 41800000.00, 'arms_length',
        'Peachtree Tower Partners LP', NULL,
        'debt_assumption', 0.00, 194.42,
        NULL, '10000000-0000-0000-0000-000000000001', 'verified'
    );

UPDATE property_sales
SET cap_rate = 6.75,
    noi = 2821500.00,
    noi_per_area = 13.12,
    opex = 1760000.00,
    opex_per_area = 8.19,
    occupancy_at_sale_pct = 91.5
WHERE id = 'f0000000-0000-0000-0000-000000000003';

INSERT INTO property_leases (
    id, property_id, comp_type_id, lessee_name, lessee_industry,
    landlord_name, space_id, suite, floor_number, lease_type,
    transaction_type, execution_date, commencement_date, expiration_date,
    term_months, leased_area, rent_amount, rent_period,
    starting_rent_per_area, effective_rent_per_area,
    net_effective_rent_per_area, annual_rent, free_rent_months,
    ti_allowance_per_area, verification_status
)
VALUES
    (
        'f2000000-0000-0000-0000-000000000001',
        '60000000-0000-0000-0000-000000000006',
        '30000000-0000-0000-0000-000000000002',
        'Northside Analytics', 'software', 'Peachtree Tower Partners LP',
        '72000000-0000-0000-0000-000000000003',
        '1200', 12, 'modified_gross', 'new_lease',
        '2024-01-15', '2024-04-01', '2031-03-31', 84,
        18500, 42.50, 'per_area_annual',
        42.50, 40.10, 38.20, 786250.00, 4.0, 45.00,
        'verified'
    ),
    (
        'f2000000-0000-0000-0000-000000000002',
        '60000000-0000-0000-0000-000000000003',
        '30000000-0000-0000-0000-000000000003',
        'Beltline Market', 'grocery', 'Caroline Retail Partners LLC',
        '72000000-0000-0000-0000-000000000002',
        '120', 1, 'triple_net', 'renewal',
        '2023-09-01', '2024-01-01', '2028-12-31', 60,
        2600, 36.00, 'per_area_annual',
        36.00, 35.00, 34.25, 93600.00, 1.0, 20.00,
        'verified'
    );

INSERT INTO rent_escalations (
    id, lease_id, escalation_type, escalation_value,
    escalation_frequency_months, effective_from, effective_until
)
VALUES
    ('f3000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'fixed_percent', 3.0000, 12, '2025-04-01', '2031-03-31'),
    ('f3000000-0000-0000-0000-000000000002', 'f2000000-0000-0000-0000-000000000002', 'fixed_percent', 2.5000, 12, '2025-01-01', '2028-12-31');

INSERT INTO lease_concessions (
    id, lease_id, concession_type, concession_value, concession_unit,
    abatement_months, ti_allowance_per_area, effective_date, expiration_date
)
VALUES
    ('f4000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'free_rent', 262083.33, 'total', 4, NULL, '2024-04-01', '2024-07-31'),
    ('f4000000-0000-0000-0000-000000000002', 'f2000000-0000-0000-0000-000000000001', 'ti_allowance', 832500.00, 'total', NULL, 45.00, '2024-04-01', '2025-03-31');

INSERT INTO property_unit_rents (
    id, property_id, comp_type_id, unit_type, unit_area, bedrooms, bathrooms,
    unit_count, units_available, rate_amount, rate_period, rate_basis,
    rate_type, observed_on, concessions_note, verification_status
)
VALUES
    (
        'f5000000-0000-0000-0000-000000000001',
        '60000000-0000-0000-0000-000000000004',
        '30000000-0000-0000-0000-000000000004',
        '1BR/1BA', 760, 1, 1.0, 88, 5, 1975.00,
        'monthly', 'per_unit', 'asking', '2024-05-01',
        'one month free on select units', 'verified'
    ),
    (
        'f5000000-0000-0000-0000-000000000002',
        '60000000-0000-0000-0000-000000000004',
        '30000000-0000-0000-0000-000000000004',
        '2BR/2BA', 1120, 2, 2.0, 72, 3, 2750.00,
        'monthly', 'per_unit', 'asking', '2024-05-01',
        'one month free on select units', 'verified'
    );

INSERT INTO property_listings (
    id, property_id, listing_kind, status, list_price, listed_on,
    mls_number, listing_brokerage, listing_agent, verification_status
)
VALUES
    (
        'f6000000-0000-0000-0000-000000000001',
        '60000000-0000-0000-0000-000000000005',
        'for_sale', 'active', 7250000.00, '2024-04-15',
        'ATL-FLEX-4125', 'Industrial Realty Advisors',
        'Jordan Broker', 'pending_review'
    );

INSERT INTO valuations (
    id, property_id, valuation_kind, value_type, interest_appraised,
    value_premise, value_amount, indicated_value_sales_comparison,
    indicated_value_cost, indicated_value_income, value_low, value_high,
    value_per_area, confidence_score, as_of_date, report_date,
    contributed_by_id
)
VALUES
    (
        'f7000000-0000-0000-0000-000000000001',
        '60000000-0000-0000-0000-000000000001',
        'appraisal', 'market_value', 'fee_simple', 'as_is',
        760000.00, 755000.00, 775000.00, NULL, 735000.00,
        785000.00, 265.73, 92, '2024-03-15', '2024-03-22',
        '10000000-0000-0000-0000-000000000001'
    );

INSERT INTO income_expense_statements (
    id, property_id, statement_year, is_actual, pgi, vacancy_loss, vacancy_pct,
    egi, opex_total, noi, capex, reimbursements, line_items,
    verification_status
)
VALUES
    (
        'f8000000-0000-0000-0000-000000000001',
        '60000000-0000-0000-0000-000000000006',
        2023, TRUE, 4725000.00, 401625.00, 8.50,
        4323375.00, 1501875.00, 2821500.00, 250000.00,
        615000.00,
        '{"base_rent": 4100000, "parking": 625000, "repairs": 310000}',
        'verified'
    );

INSERT INTO comp_sets (
    id, created_by_id, name, subject_property_id, effective_date, purpose,
    search_criteria, notes
)
VALUES
    (
        'f9000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-000000000001',
        'Springdale residential sale comps',
        '60000000-0000-0000-0000-000000000001',
        '2024-03-15', 'appraisal',
        '{"radius_miles": 3, "property_type": "RES_SFD", "sale_date_after": "2020-01-01"}',
        'Starter set for Atlanta residential comp modeling'
    );

INSERT INTO comp_set_items (
    comp_set_id, comp_kind, comp_id, position, selection_source, notes
)
VALUES
    ('f9000000-0000-0000-0000-000000000001', 'sale', 'f0000000-0000-0000-0000-000000000002', 1, 'user', 'nearby bungalow sale'),
    ('f9000000-0000-0000-0000-000000000001', 'sale', 'f0000000-0000-0000-0000-000000000001', 2, 'imported', 'subject prior sale');

INSERT INTO data_verifications (
    id, verifiable_type, verifiable_id, field_name, verification_status,
    verification_method, verification_date, confidence_level,
    confidence_score, evidence_type, evidence_notes, verified_by_id,
    verified_at
)
VALUES
    (
        'fa000000-0000-0000-0000-000000000001',
        'property_sale',
        'f0000000-0000-0000-0000-000000000001',
        'sale_price', 'verified', 'public_filing', '2024-03-20',
        'high', 95, 'deed', 'Matched deed consideration to sale comp.',
        '10000000-0000-0000-0000-000000000002', NOW()
    ),
    (
        'fa000000-0000-0000-0000-000000000002',
        'address',
        '50000000-0000-0000-0000-000000000001',
        'location', 'verified', 'appraiser_workfile', '2024-03-18',
        'high', 91, 'map', 'Geocode reviewed against workfile map.',
        '10000000-0000-0000-0000-000000000002', NOW()
    );
