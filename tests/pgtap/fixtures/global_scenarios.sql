-- International, specialty-rental, and geospatial scenario data, layered on
-- fixtures/atlanta_records.sql + fixtures/comp_scenarios.sql:
--
--   G. Ontario PIN parcel + CAD/metric Toronto multifamily sale
--   H. German Flurstueck parcel + EUR/metric Munich industrial sale & lease
--   I. Specialty rate bases: assisted-living per-bed, hotel per-key daily
--      ADR, and a by-the-bed residential lease (per-bed in metrics)
--   J. For-lease listing on the Caroline Street retail
--   K. Fulton County boundary polygon for containment/proximity queries

-- ---------------------------------------------------------------------------
-- G/H. International jurisdictions, addresses, parcels
-- ---------------------------------------------------------------------------
INSERT INTO jurisdictions (id, country, region, name, kind, authority_code)
VALUES
    ('40000000-0000-0000-0000-000000000004', 'CA', 'ON', 'Ontario Land Registry Office 80 (Toronto)', 'land_registry', 'ON-LRO-80'),
    ('40000000-0000-0000-0000-000000000005', 'DE', 'BY', 'Grundbuchamt Muenchen', 'land_registry', 'DE-09162');

-- crude Fulton County bounding polygon: covers the Fulton fixture points,
-- excludes the DeKalb ones (Caroline Street, Emory Point)
UPDATE jurisdictions
SET geom = ST_Multi(ST_GeomFromText(
    'POLYGON((-84.62 33.60, -84.36 33.60, -84.36 33.95, -84.62 33.95, -84.62 33.60))',
    4326))
WHERE id = '40000000-0000-0000-0000-000000000001';

INSERT INTO addresses (
    id, country, street_number, street_name, street_suffix,
    street_post_directional, locality, region, postal_code, address_hash,
    location
)
VALUES
    (
        '50000000-0000-0000-0000-000000000008',
        'CA', '318', 'King', 'Street', 'West', 'Toronto', 'ON', 'M5V 1J2',
        'global:king-west-318',
        ST_SetSRID(ST_MakePoint(-79.3907, 43.6455), 4326)::GEOGRAPHY
    ),
    (
        '50000000-0000-0000-0000-000000000009',
        'DE', '110', 'Landsberger Strasse', NULL, NULL, 'Muenchen', 'BY', '80339',
        'global:landsberger-110',
        ST_SetSRID(ST_MakePoint(11.5335, 48.1420), 4326)::GEOGRAPHY
    );

INSERT INTO comp_types (id, code, name, primary_unit, secondary_units)
VALUES
    ('30000000-0000-0000-0000-000000000007', 'senior_housing', 'Senior Housing', 'bed', ARRAY['care_level']),
    ('30000000-0000-0000-0000-000000000008', 'hospitality', 'Hospitality', 'key', ARRAY['adr', 'revpar']);

INSERT INTO property_types (id, code, name, comp_type_id)
VALUES
    ('31000000-0000-0000-0000-000000000007', 'SEN_AL', 'Assisted Living', '30000000-0000-0000-0000-000000000007'),
    ('31000000-0000-0000-0000-000000000008', 'HOS_HTL', 'Hotel', '30000000-0000-0000-0000-000000000008');

INSERT INTO properties (id, name, property_type_id, situs_address_id, location, metadata)
VALUES
    (
        '60000000-0000-0000-0000-000000000009',
        'King West Lofts',
        '31000000-0000-0000-0000-000000000004',
        '50000000-0000-0000-0000-000000000008',
        ST_SetSRID(ST_MakePoint(-79.3907, 43.6455), 4326)::GEOGRAPHY,
        '{"seed_source_id": "global_toronto"}'
    ),
    (
        '60000000-0000-0000-0000-000000000010',
        'Werksviertel Logistik',
        '31000000-0000-0000-0000-000000000005',
        '50000000-0000-0000-0000-000000000009',
        ST_SetSRID(ST_MakePoint(11.5335, 48.1420), 4326)::GEOGRAPHY,
        '{"seed_source_id": "global_munich"}'
    ),
    (
        '60000000-0000-0000-0000-000000000011',
        'Roswell Road Assisted Living',
        '31000000-0000-0000-0000-000000000007',
        NULL,
        ST_SetSRID(ST_MakePoint(-84.3790, 33.9280), 4326)::GEOGRAPHY,
        '{"seed_source_id": "global_senior"}'
    ),
    (
        '60000000-0000-0000-0000-000000000012',
        'Downtown Atlanta Hotel',
        '31000000-0000-0000-0000-000000000008',
        NULL,
        ST_SetSRID(ST_MakePoint(-84.3880, 33.7590), 4326)::GEOGRAPHY,
        '{"seed_source_id": "global_hotel"}'
    );

-- raw-as-issued identifiers: an Ontario PIN and a German Flurstueck number
INSERT INTO parcels (
    id, jurisdiction_id, country, authority_code, parcel_number,
    normalized_parcel_number, unit_system, land_area, legal_description
)
VALUES
    (
        '70000000-0000-0000-0000-000000000012',
        '40000000-0000-0000-0000-000000000004',
        'CA', 'ON-LRO-80', '76331-0245', '763310245',
        'metric', 1850, 'King Street West mixed-use parcel'
    ),
    (
        '70000000-0000-0000-0000-000000000013',
        '40000000-0000-0000-0000-000000000005',
        'DE', 'DE-09162', 'Flur 2, Flurstueck 123/4', '2-123/4',
        'metric', 24000, 'Werksviertel logistics parcel'
    );

INSERT INTO property_parcels (property_id, parcel_id, is_primary, started_on)
VALUES
    ('60000000-0000-0000-0000-000000000009', '70000000-0000-0000-0000-000000000012', TRUE, '2024-05-15'),
    ('60000000-0000-0000-0000-000000000010', '70000000-0000-0000-0000-000000000013', TRUE, '2024-02-01');

-- ---------------------------------------------------------------------------
-- G. Toronto multifamily sale: CAD, metric, price per square meter
-- ---------------------------------------------------------------------------
INSERT INTO property_sales (
    id, property_id, comp_type_id, sale_date, currency, sale_price, sale_type,
    buyer_name, unit_system, price_per_area, metrics, verification_status
)
VALUES (
    'f0000000-0000-0000-0000-000000000008',
    '60000000-0000-0000-0000-000000000009',
    '30000000-0000-0000-0000-000000000004',
    '2024-05-15', 'CAD', 24750000.00, 'arms_length',
    'King West Residential REIT', 'metric', 5500.00,
    '{"price_per_unit": 515625, "unit_count": 48}',
    'verified'
);

-- ---------------------------------------------------------------------------
-- H. Munich industrial: EUR/metric sale and lease
-- ---------------------------------------------------------------------------
INSERT INTO property_sales (
    id, property_id, comp_type_id, sale_date, currency, sale_price, sale_type,
    buyer_name, unit_system, price_per_area, verification_status
)
VALUES (
    'f0000000-0000-0000-0000-000000000009',
    '60000000-0000-0000-0000-000000000010',
    '30000000-0000-0000-0000-000000000005',
    '2024-02-01', 'EUR', 18600000.00, 'arms_length',
    'Bayern Logistik Fonds', 'metric', 1550.00,
    'verified'
);

INSERT INTO property_leases (
    id, property_id, comp_type_id, lessee_name, lease_type, transaction_type,
    commencement_date, expiration_date, term_months, unit_system, currency,
    leased_area, rent_amount, rent_period, starting_rent_per_area,
    annual_rent, verification_status
)
VALUES (
    'f2000000-0000-0000-0000-000000000004',
    '60000000-0000-0000-0000-000000000010',
    '30000000-0000-0000-0000-000000000005',
    'Alpen Distribution GmbH', 'triple_net', 'new_lease',
    '2024-06-01', '2034-05-31', 120, 'metric', 'EUR',
    8500, 78.00, 'per_area_annual', 78.00,
    663000.00, 'verified'
);

-- ---------------------------------------------------------------------------
-- I. Specialty rate bases
-- ---------------------------------------------------------------------------
-- assisted living: surveyed per-bed monthly rate
INSERT INTO property_unit_rents (
    id, property_id, comp_type_id, unit_type, unit_count, rate_amount,
    rate_period, rate_basis, rate_type, observed_on, verification_status
)
VALUES (
    'f5000000-0000-0000-0000-000000000004',
    '60000000-0000-0000-0000-000000000011',
    '30000000-0000-0000-0000-000000000007',
    'AL Studio Bed', 64, 5200.00, 'monthly', 'per_bed', 'asking',
    '2026-05-01', 'verified'
);

-- hotel: per-key nightly ADR observation
INSERT INTO property_unit_rents (
    id, property_id, comp_type_id, unit_type, unit_count, rate_amount,
    rate_period, rate_basis, rate_type, observed_on, verification_status
)
VALUES (
    'f5000000-0000-0000-0000-000000000005',
    '60000000-0000-0000-0000-000000000012',
    '30000000-0000-0000-0000-000000000008',
    'Standard King', 180, 189.00, 'daily', 'per_key', 'asking',
    '2026-06-15', 'verified'
);

-- by-the-bed residential lease: headline rent typed, per-bed in metrics
INSERT INTO property_leases (
    id, property_id, comp_type_id, lessee_name, lease_type, transaction_type,
    commencement_date, expiration_date, term_months, rent_amount, rent_period,
    metrics, verification_status
)
VALUES (
    'f2000000-0000-0000-0000-000000000005',
    '60000000-0000-0000-0000-000000000002',
    '30000000-0000-0000-0000-000000000001',
    'Georgia State Students', 'residential', 'new_lease',
    '2024-06-01', '2025-06-01', 12, 2400.00, 'monthly',
    '{"rent_per_bed": 800, "beds": 3}',
    'verified'
);

-- ---------------------------------------------------------------------------
-- J. For-lease listing on the Caroline Street retail
-- ---------------------------------------------------------------------------
INSERT INTO property_listings (
    id, property_id, listing_kind, status, list_rent_amount, list_rent_period,
    listed_on, listing_brokerage, verification_status
)
VALUES (
    'f6000000-0000-0000-0000-000000000002',
    '60000000-0000-0000-0000-000000000003',
    'for_lease', 'active', 38.00, 'per_area_annual',
    '2026-04-01', 'Inman Park Retail Advisors', 'pending_review'
);
