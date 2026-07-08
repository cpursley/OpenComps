\set ON_ERROR_STOP true

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(74);

SELECT has_extension('postgis', 'postgis extension is available');
SELECT has_extension('citext', 'citext extension is available');
SELECT has_extension('pg_trgm', 'pg_trgm extension is available');
SELECT has_extension('btree_gist', 'btree_gist extension is available');

SELECT has_enum('public', 'provider_kind', 'provider kind enum exists');
SELECT has_enum('public', 'verification_status', 'verification status enum exists');
SELECT has_enum('public', 'sale_type', 'sale type enum exists');
SELECT has_enum('public', 'lease_type', 'lease type enum exists');
SELECT has_enum('public', 'rent_period', 'rent period enum exists');
SELECT has_enum('public', 'comp_kind', 'comp kind enum exists');
SELECT has_enum('public', 'data_visibility', 'data visibility enum exists');

SELECT has_table('public', 'users', 'users table exists');
SELECT has_table('public', 'classification_taxonomies', 'classification taxonomies table exists');
SELECT has_table('public', 'comp_types', 'comp types table exists');
SELECT has_table('public', 'property_types', 'property types table exists');
SELECT has_table('public', 'property_type_mappings', 'property type mappings table exists');
SELECT has_table('public', 'data_providers', 'data providers table exists');
SELECT has_table('public', 'properties', 'properties table exists');
SELECT has_table('public', 'addresses', 'addresses table exists');
SELECT has_table('public', 'jurisdictions', 'jurisdictions table exists');
SELECT has_table('public', 'parcels', 'parcels table exists');
SELECT has_table('public', 'property_parcels', 'property parcel history table exists');
SELECT has_table('public', 'parcel_lineage', 'parcel lineage table exists');
SELECT has_table('public', 'property_identifiers', 'property identifiers table exists');
SELECT has_table('public', 'source_records', 'source records table exists');
SELECT has_table('public', 'residential_details', 'residential details table exists');
SELECT has_table('public', 'commercial_details', 'commercial details table exists');
SELECT has_table('public', 'land_details', 'land details table exists');
SELECT has_table('public', 'structures', 'structures table exists');
SELECT has_table('public', 'spaces', 'spaces table exists');
SELECT has_table('public', 'owners', 'owners table exists');
SELECT has_table('public', 'owner_contacts', 'owner contacts table exists');
SELECT has_table('public', 'owner_addresses', 'owner addresses table exists');
SELECT has_table('public', 'property_transfers', 'property transfers table exists');
SELECT has_table('public', 'ownership_periods', 'ownership periods table exists');
SELECT has_table('public', 'ownership_interests', 'ownership interests table exists');
SELECT has_table('public', 'assessments', 'assessments table exists');
SELECT has_table('public', 'tax_bills', 'tax bills table exists');
SELECT has_table('public', 'property_mortgages', 'property mortgages table exists');
SELECT has_table('public', 'property_sales', 'property sales table exists');
SELECT has_table('public', 'property_leases', 'property leases table exists');
SELECT has_table('public', 'rent_escalations', 'rent escalations table exists');
SELECT has_table('public', 'lease_concessions', 'lease concessions table exists');
SELECT has_table('public', 'property_unit_rents', 'property unit rents table exists');
SELECT has_table('public', 'property_listings', 'property listings table exists');
SELECT has_table('public', 'valuations', 'valuations table exists');
SELECT has_table('public', 'income_expense_statements', 'income and expense statements table exists');
SELECT has_table('public', 'comp_sets', 'comp sets table exists');
SELECT has_table('public', 'comp_set_items', 'comp set items table exists');
SELECT has_table('public', 'data_verifications', 'data verifications table exists');
SELECT has_table('public', 'us_zips', 'us zips table exists');
SELECT has_table('public', 'reference_dataset_loads', 'reference dataset loads table exists');

SELECT has_view('public', 'v_current_sources', 'current sources view exists');
SELECT has_view('public', 'v_current_ownership', 'current ownership view exists');
SELECT has_view('public', 'v_property_sale_history', 'property sale history view exists');

SELECT col_is_pk('public', 'properties', 'id', 'properties.id is the primary key');
SELECT col_type_is('public', 'properties', 'id', 'uuid', 'properties.id is uuid');
SELECT col_type_is('public', 'addresses', 'full_address', 'text', 'addresses.full_address is generated text');
SELECT col_not_null('public', 'addresses', 'address_hash', 'addresses require a dedupe hash');
SELECT col_type_is('public', 'parcels', 'reso_upi', 'text', 'parcels expose generated RESO UPI text');
SELECT col_type_is('public', 'ownership_periods', 'valid_period', 'daterange', 'ownership periods expose daterange');
SELECT col_type_is('public', 'property_sales', 'sale_type', 'sale_type', 'sale comps use sale_type enum');
SELECT col_is_pk('public', 'reference_dataset_loads', 'id', 'reference_dataset_loads.id is the primary key');
SELECT col_not_null('public', 'reference_dataset_loads', 'dataset', 'reference dataset loads require a dataset name');
SELECT col_not_null('public', 'reference_dataset_loads', 'row_count', 'reference dataset loads require a row count');
SELECT col_type_is('public', 'reference_dataset_loads', 'loaded_at', 'timestamp with time zone', 'reference dataset loads are timestamped');
SELECT hasnt_column('public', 'us_zips', 'loaded_at', 'us_zips rows do not carry per-row load timestamps');

SELECT has_index('public', 'parcels', 'parcels_active_number_index', 'active parcel number uniqueness index exists');
SELECT has_index('public', 'property_parcels', 'property_parcels_one_current_primary_index', 'one current primary parcel index exists');
SELECT has_index('public', 'source_records', 'source_records_current_index', 'current source record uniqueness index exists');
SELECT has_index('public', 'property_sales', 'property_sales_cap_rate_index', 'arms-length cap-rate index exists');
SELECT has_index('public', 'addresses', 'addresses_full_trgm_index', 'address trigram index exists');
SELECT has_index('public', 'us_zips', 'us_zips_location_index', 'zip centroid spatial index exists');
SELECT has_index('public', 'reference_dataset_loads', 'reference_dataset_loads_dataset_index', 'reference dataset load lookup index exists');

SELECT * FROM finish();

ROLLBACK;
