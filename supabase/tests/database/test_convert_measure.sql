\set ON_ERROR_STOP true

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(12);

-- length
SELECT is(
    round(convert_measure(100, 'm', 'ft'), 3),
    328.084,
    'meters convert to feet'
);

SELECT is(
    convert_measure(5, 'mi', 'm'),
    8046.72,
    'miles convert to meters (the radius_m shortcut)'
);

SELECT is(
    round(convert_measure(10, 'km', 'mi'), 4),
    6.2137,
    'kilometers convert to miles'
);

SELECT is(
    round(convert_measure(1387.56, 'm', 'mi'), 2),
    0.86,
    'dist_meters values convert to miles for US reporting'
);

-- area (including the land units sources quote)
SELECT is(
    convert_measure(1, 'acre', 'sqft'),
    43560.0,
    'acres convert to square feet'
);

SELECT is(
    convert_measure(1, 'hectare', 'sqm'),
    10000.0,
    'hectares convert to square meters'
);

SELECT is(
    round(convert_measure(100, 'sqm', 'sqft'), 2),
    1076.39,
    'square meters convert to square feet'
);

-- per-area rates (inverse of the area factor)
SELECT is(
    round(convert_measure(10, 'per_sqft', 'per_sqm'), 2),
    107.64,
    'per-square-foot rates convert to per-square-meter'
);

-- identity and null
SELECT is(
    convert_measure(42, 'mi', 'mi'),
    42.0,
    'same-unit conversion is identity'
);

SELECT is(
    convert_measure(NULL, 'm', 'ft'),
    NULL,
    'null value passes through as null'
);

-- dimension and unit validation
SELECT throws_ok(
    $$SELECT convert_measure(1, 'ft', 'sqm')$$,
    '22023',
    NULL,
    'cross-dimension conversion raises invalid_parameter_value'
);

SELECT throws_ok(
    $$SELECT convert_measure(1, 'furlong', 'm')$$,
    '22023',
    NULL,
    'unknown unit raises invalid_parameter_value'
);

SELECT * FROM finish();

ROLLBACK;
