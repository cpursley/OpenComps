-- Bulk insert RPC.
--
-- PostgREST accepts a JSON array body for multi-row POSTs, but object-only
-- REST clients (e.g. the supabase MCP server, which delivers top-level array
-- bodies as strings) cannot send one. bulk_insert wraps the same operation in
-- a function call whose body is a plain object:
--
--   POST /rpc/bulk_insert  {"target": "addresses", "rows": [ {...}, ... ]}
--
-- Semantics mirror the REST insert path:
--   * inserted columns = union of keys across rows; columns absent from every
--     row keep their DEFAULTs (never NULL-clobbered)
--   * unknown keys raise undefined_column (42703), like PGRST204
--   * returns one jsonb per inserted row (ids and defaults included)
--   * vocabulary/reference tables and non-tables are refused (22023)
--
-- NOTE: no BEGIN/COMMIT here — tinbase wraps migrations in a transaction and
-- the psql paths apply migrations with -1.

CREATE OR REPLACE FUNCTION bulk_insert(target TEXT, rows JSONB)
RETURNS SETOF JSONB
LANGUAGE plpgsql AS $$
DECLARE
    -- canonical vocabulary and reference datasets are read-only to ingest
    denied CONSTANT TEXT[] := ARRAY[
        'comp_types', 'property_types', 'classification_taxonomies',
        'us_zips', 'reference_dataset_loads'
    ];
    cols TEXT;
BEGIN
    IF rows IS NULL OR jsonb_typeof(rows) <> 'array' THEN
        RAISE EXCEPTION 'rows must be a JSON array of objects'
            USING ERRCODE = '22023';
    END IF;
    IF target = ANY (denied) THEN
        RAISE EXCEPTION
            'bulk_insert into "%" is not allowed (vocabulary/reference table)',
            target USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname = target AND c.relkind = 'r'
    ) THEN
        RAISE EXCEPTION 'unknown table "%"', target USING ERRCODE = '22023';
    END IF;
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(rows) AS elem
        WHERE jsonb_typeof(elem) <> 'object'
    ) THEN
        RAISE EXCEPTION 'every element of rows must be a JSON object'
            USING ERRCODE = '22023';
    END IF;
    IF jsonb_array_length(rows) = 0 THEN
        RETURN;
    END IF;

    -- Insert only the columns the payload mentions so every other column
    -- takes its DEFAULT (jsonb_populate_recordset alone would NULL them).
    SELECT string_agg(format('%I', key), ', ')
    INTO cols
    FROM (
        SELECT DISTINCT jsonb_object_keys(elem) AS key
        FROM jsonb_array_elements(rows) AS elem
    ) payload_keys;

    RETURN QUERY EXECUTE format(
        'INSERT INTO public.%I (%s)
         SELECT %s FROM jsonb_populate_recordset(NULL::public.%I, $1)
         RETURNING to_jsonb(%I.*)',
        target, cols, cols, target, target
    ) USING rows;
END;
$$;
