-- General measurement converter RPC.
--
-- convert_area handles the unit_system enum (sq ft <-> m2) for the comp
-- search internals; convert_measure is the REST/MCP-facing general
-- converter with explicit units, so clients get US-standard output for
-- dist_meters, radius shortcuts, and land areas without doing arithmetic:
--   length:   m, km, ft, yd, mi
--   area:     sqm, sqft, acre, hectare
--   per-area: per_sqm, per_sqft   (rates like $/sqft; inverse area factor)
-- Cross-dimension conversions and unknown units raise SQLSTATE 22023.
-- NULL value returns NULL. Currency is deliberately absent: money is
-- stored as quoted, never converted.
--
-- NOTE: no BEGIN/COMMIT here — tinbase wraps migrations in a transaction and
-- the psql paths apply migrations with -1.

CREATE OR REPLACE FUNCTION convert_measure(val NUMERIC, from_unit TEXT, to_unit TEXT)
RETURNS NUMERIC
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    from_dim TEXT; from_factor NUMERIC;
    to_dim TEXT;   to_factor NUMERIC;
BEGIN
    IF val IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT u.dim, u.factor INTO from_dim, from_factor
    FROM (VALUES
        ('m', 'length', 1.0), ('km', 'length', 1000.0),
        ('ft', 'length', 0.3048), ('yd', 'length', 0.9144),
        ('mi', 'length', 1609.344),
        ('sqm', 'area', 1.0), ('sqft', 'area', 0.09290304),
        ('acre', 'area', 4046.8564224), ('hectare', 'area', 10000.0),
        ('per_sqm', 'per_area', 1.0),
        ('per_sqft', 'per_area', 10.763910416709722)
    ) AS u(unit, dim, factor)
    WHERE u.unit = from_unit;
    IF from_dim IS NULL THEN
        RAISE EXCEPTION
            'unknown unit "%" (m, km, ft, yd, mi, sqm, sqft, acre, hectare, per_sqm, per_sqft)',
            from_unit USING ERRCODE = '22023';
    END IF;

    SELECT u.dim, u.factor INTO to_dim, to_factor
    FROM (VALUES
        ('m', 'length', 1.0), ('km', 'length', 1000.0),
        ('ft', 'length', 0.3048), ('yd', 'length', 0.9144),
        ('mi', 'length', 1609.344),
        ('sqm', 'area', 1.0), ('sqft', 'area', 0.09290304),
        ('acre', 'area', 4046.8564224), ('hectare', 'area', 10000.0),
        ('per_sqm', 'per_area', 1.0),
        ('per_sqft', 'per_area', 10.763910416709722)
    ) AS u(unit, dim, factor)
    WHERE u.unit = to_unit;
    IF to_dim IS NULL THEN
        RAISE EXCEPTION
            'unknown unit "%" (m, km, ft, yd, mi, sqm, sqft, acre, hectare, per_sqm, per_sqft)',
            to_unit USING ERRCODE = '22023';
    END IF;

    IF from_dim <> to_dim THEN
        RAISE EXCEPTION 'cannot convert % (%) to % (%)',
            from_unit, from_dim, to_unit, to_dim USING ERRCODE = '22023';
    END IF;

    RETURN val * from_factor / to_factor;
END;
$$;
