\set ON_ERROR_STOP true

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap;
\ir fixtures/atlanta_records.psql

SELECT plan(17);

-- ---------------------------------------------------------------------------
-- Rung 1: parcel (APN, optionally scoped to a county via ZIP)
-- ---------------------------------------------------------------------------
SELECT is(
    (SELECT property_id FROM find_property(apn => '17 010000010276', zip => '30305')),
    '60000000-0000-0000-0000-000000000001'::UUID,
    'raw APN scoped by ZIP county finds the Springdale property'
);

SELECT is(
    (SELECT matched_by FROM find_property(apn => '17 010000010276', zip => '30305')),
    'parcel',
    'APN hits report matched_by = parcel'
);

-- source formatting differs from what the county issued: normalization matches
SELECT is(
    (SELECT property_id FROM find_property(apn => '18-108-01-055')),
    '60000000-0000-0000-0000-000000000004'::UUID,
    'dashed APN with no ZIP still matches via normalization'
);

-- right APN, wrong county: ZIP scoping must exclude it (and nothing else to
-- fall through to), so the search comes back empty rather than guessing
SELECT is(
    (SELECT COUNT(*) FROM find_property(apn => '17 010000010276', zip => '30307')),
    0::BIGINT,
    'APN scoped to the wrong county returns no rows'
);

SELECT throws_ok(
    $$SELECT * FROM find_property(apn => '17 010000010276', zip => '99999')$$,
    '22023',
    NULL,
    'unknown ZIP raises invalid_parameter_value'
);

-- ---------------------------------------------------------------------------
-- Rung 2: address (trigram similarity on full_address)
-- ---------------------------------------------------------------------------
SELECT is(
    (SELECT property_id FROM find_property(address => '855 Emory Point Dr NE, Atlanta GA 30329') LIMIT 1),
    '60000000-0000-0000-0000-000000000004'::UUID,
    'abbreviated address fuzzy-matches the stored full_address'
);

SELECT is(
    (SELECT matched_by FROM find_property(address => '855 Emory Point Dr NE, Atlanta GA 30329') LIMIT 1),
    'address',
    'address hits report matched_by = address'
);

-- waterfall precedence: a parcel hit wins and address input is not consulted
SELECT is(
    (SELECT matched_by FROM find_property(
        apn => '18 108 01 055',
        address => '276 Springdale Drive NE Atlanta GA 30305') LIMIT 1),
    'parcel',
    'parcel rung takes precedence over address input'
);

SELECT is(
    (SELECT COUNT(*) FROM find_property(
        apn => '18 108 01 055',
        address => '276 Springdale Drive NE Atlanta GA 30305')),
    1::BIGINT,
    'winning rung returns only its own matches'
);

-- a dud APN falls through to the address rung
SELECT is(
    (SELECT property_id FROM find_property(
        apn => '99 999 99 999',
        address => '276 Springdale Drive NE Atlanta GA 30305') LIMIT 1),
    '60000000-0000-0000-0000-000000000001'::UUID,
    'unmatched APN falls through to the address rung'
);

-- best match first when several stored addresses resemble the query
SELECT is(
    (SELECT property_id FROM find_property(address => '3324 Peachtree Road NE Atlanta GA 30326') LIMIT 1),
    '60000000-0000-0000-0000-000000000006'::UUID,
    'address matches are ordered best-first'
);

-- a different house number on a known street is a DIFFERENT property: the
-- shared street/city/ZIP tail must not carry a trigram false-positive (3324
-- and 2500 Peachtree Road are seeded; 5000 Peachtree Road is neither)
SELECT is(
    (SELECT COUNT(*) FROM find_property(address => '5000 Peachtree Road NE Atlanta GA 30326')),
    0::BIGINT,
    'a different street number on a known street does not false-match'
);

-- ---------------------------------------------------------------------------
-- Rung 3: location (proximity to properties.location)
-- ---------------------------------------------------------------------------
SELECT is(
    (SELECT matched_by FROM find_property(lat => 33.8222582, long => -84.3785038) LIMIT 1),
    'location',
    'coordinates ~22m from a property match by location'
);

SELECT ok(
    (SELECT dist_meters > 0 AND dist_meters <= 50
     FROM find_property(lat => 33.8222582, long => -84.3785038) LIMIT 1),
    'location hits carry dist_meters within the default 50m radius'
);

SELECT is(
    (SELECT COUNT(*) FROM find_property(lat => 33.8270582, long => -84.3785038)),
    0::BIGINT,
    'coordinates ~550m away find nothing at the default radius'
);

-- ---------------------------------------------------------------------------
-- No match / bad arguments
-- ---------------------------------------------------------------------------
SELECT is(
    (SELECT COUNT(*) FROM find_property(address => 'zzqx qwvv blvd nowheresville')),
    0::BIGINT,
    'gibberish address returns no rows rather than weak matches'
);

SELECT throws_ok(
    $$SELECT * FROM find_property()$$,
    '22023',
    NULL,
    'calling with no usable arguments raises invalid_parameter_value'
);

SELECT * FROM finish();

ROLLBACK;
