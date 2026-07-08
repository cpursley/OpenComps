-- Postgres runs files in this directory on first boot of a fresh pgdata volume.
-- The main schema also declares its required runtime extensions, but creating
-- them here makes a brand-new Docker database ready for migration and pgTAP.
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS pgtap;
