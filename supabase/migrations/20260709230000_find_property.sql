-- Duplicate-prevention lookup RPC.
--
-- "Is this property already in the database?" answered as a waterfall, one
-- rung per identity signal, strongest first; the first rung that matches
-- wins and weaker rungs are not consulted:
--   1. parcel   - APN normalized (strip punctuation/spaces, case-folded),
--                 optionally scoped to a county via the ZIP -> us_zips
--                 county_fips resolution (unknown ZIP raises 22023)
--   2. address  - pg_trgm similarity against the generated full_address,
--                 best match first
--   3. location - properties.location within radius_m meters (default 50,
--                 sized for geocoder scatter), nearest first
-- Rows carry matched_by ('parcel'|'address'|'location') so callers can
-- weigh confidence; at most 5 rows return. No usable arguments raises
-- SQLSTATE 22023.
--
-- NOTE: no BEGIN/COMMIT here — tinbase wraps migrations in a transaction and
-- the psql paths apply migrations with -1.

CREATE OR REPLACE FUNCTION find_property(
    apn TEXT DEFAULT NULL,
    zip TEXT DEFAULT NULL,
    address TEXT DEFAULT NULL,
    lat DOUBLE PRECISION DEFAULT NULL,
    long DOUBLE PRECISION DEFAULT NULL,
    radius_m DOUBLE PRECISION DEFAULT 50
) RETURNS TABLE (
    property_id UUID,
    property_name TEXT,
    full_address TEXT,
    matched_by TEXT,
    dist_meters DOUBLE PRECISION
)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    norm_apn TEXT;
    v_county_fips TEXT;
    anchor GEOGRAPHY;
BEGIN
    IF apn IS NULL AND address IS NULL AND (lat IS NULL OR long IS NULL) THEN
        RAISE EXCEPTION 'provide an apn, an address, or lat/long coordinates'
            USING ERRCODE = '22023';
    END IF;

    IF apn IS NOT NULL THEN
        norm_apn := upper(regexp_replace(apn, '[^A-Za-z0-9]', '', 'g'));
        IF zip IS NOT NULL THEN
            SELECT z.county_fips INTO v_county_fips FROM us_zips z
            WHERE z.zip = find_property.zip;
            IF v_county_fips IS NULL THEN
                RAISE EXCEPTION
                    'unknown ZIP "%" (is the us_zips reference dataset loaded?)',
                    zip USING ERRCODE = '22023';
            END IF;
        END IF;

        RETURN QUERY
        SELECT p.id, p.name, a.full_address, 'parcel'::TEXT,
               NULL::DOUBLE PRECISION
        FROM parcels pc
        JOIN property_parcels pp ON pp.parcel_id = pc.id
        JOIN properties p ON p.id = pp.property_id
        LEFT JOIN addresses a ON a.id = p.situs_address_id
        WHERE pc.retired_on IS NULL
          AND (v_county_fips IS NULL OR pc.authority_code = v_county_fips)
          AND (upper(pc.normalized_parcel_number) = norm_apn
               OR upper(regexp_replace(pc.parcel_number, '[^A-Za-z0-9]', '', 'g')) = norm_apn)
        LIMIT 5;
        IF FOUND THEN RETURN; END IF;
    END IF;

    IF address IS NOT NULL THEN
        RETURN QUERY
        SELECT p.id, p.name, a.full_address, 'address'::TEXT,
               NULL::DOUBLE PRECISION
        FROM addresses a
        JOIN properties p ON p.situs_address_id = a.id
        -- % is the trigram-indexed operator; the explicit similarity guard
        -- keeps behavior fixed if the pg_trgm.similarity_threshold GUC moves
        WHERE a.full_address % find_property.address
          AND similarity(a.full_address, find_property.address) > 0.3
        ORDER BY similarity(a.full_address, find_property.address) DESC
        LIMIT 5;
        IF FOUND THEN RETURN; END IF;
    END IF;

    IF lat IS NOT NULL AND long IS NOT NULL THEN
        anchor := resolve_search_anchor(lat, long, NULL);
        RETURN QUERY
        SELECT p.id, p.name, a.full_address, 'location'::TEXT,
               ST_Distance(p.location, anchor)::DOUBLE PRECISION
        FROM properties p
        LEFT JOIN addresses a ON a.id = p.situs_address_id
        WHERE p.location IS NOT NULL
          AND ST_DWithin(p.location, anchor, radius_m)
        ORDER BY ST_Distance(p.location, anchor)
        LIMIT 5;
    END IF;

    RETURN;
END;
$$;
