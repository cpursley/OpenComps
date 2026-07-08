#!/usr/bin/env bash
# Load or refresh SimpleMaps US Zips (free tier) into the OpenComps us_zips table.
#
# Usage:
#   ./scripts/load_us_zips.sh
#   ./scripts/load_us_zips.sh "postgres://postgres:postgres@localhost:5432/opencomps"
#   DATABASE_URL=postgres://... ./scripts/load_us_zips.sh
#   US_ZIPS_VERSION=1.96 ./scripts/load_us_zips.sh
#   US_ZIPS_FILE=~/Downloads/simplemaps_uszips_basicv1.95.1.zip ./scripts/load_us_zips.sh
#
# The release version is resolved in order: US_ZIPS_FILE filename,
# US_ZIPS_VERSION, the newest release found on the SimpleMaps page, then the
# pinned fallback. Every load is recorded in reference_dataset_loads, so
# "which release is loaded, and when?" is a query, not archaeology:
#   SELECT * FROM reference_dataset_loads WHERE dataset = 'us_zips'
#   ORDER BY loaded_at DESC LIMIT 1;
#
# Requires on the host: curl, unzip, psql.
#
# NOTE: Use of the free database in production requires that you link back to:
# https://simplemaps.com/data/us-zips
set -euo pipefail

DB="${1:-${DATABASE_URL:-postgres://${POSTGRES_USER:-postgres}:${POSTGRES_PASSWORD:-postgres}@${POSTGRES_HOST:-localhost}:${POSTGRES_PORT:-5432}/${POSTGRES_DB:-opencomps}}}"

FALLBACK_VERSION="1.95.1"
PAGE_URL="https://simplemaps.com/data/us-zips"
CURL_UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# Pull the newest simplemaps_uszips_basicv<X.Y.Z>.zip version off the page.
detect_latest_version() {
  curl -sSL --fail --http1.1 -A "$CURL_UA" "$PAGE_URL" \
    | grep -oE 'simplemaps_uszips_basicv[0-9]+(\.[0-9]+)*\.zip' \
    | sed -E 's/simplemaps_uszips_basicv([0-9]+(\.[0-9]+)*)\.zip/\1/' \
    | sort -uV | tail -1
}

version_from_name() {
  basename "$1" | grep -oE 'basicv[0-9]+(\.[0-9]+)*\.zip' \
    | sed -E 's/basicv([0-9]+(\.[0-9]+)*)\.zip/\1/' || true
}

if [ -n "${US_ZIPS_FILE:-}" ]; then
  echo "Using local SimpleMaps US Zips file: $US_ZIPS_FILE"
  cp "$US_ZIPS_FILE" "$WORKDIR/uszips.zip"
  SOURCE="$US_ZIPS_FILE"
  VERSION="${US_ZIPS_VERSION:-$(version_from_name "$US_ZIPS_FILE")}"
  if [ -z "$VERSION" ]; then
    echo "Could not parse a release version from the filename; recording 'unknown'." >&2
    VERSION="unknown"
  fi
else
  VERSION="${US_ZIPS_VERSION:-}"
  if [ -z "$VERSION" ]; then
    echo "Detecting latest SimpleMaps US Zips release..."
    VERSION="$(detect_latest_version || true)"
    if [ -z "$VERSION" ]; then
      echo "Could not detect the latest release; falling back to v${FALLBACK_VERSION}." >&2
      VERSION="$FALLBACK_VERSION"
    fi
  fi

  URL="${US_ZIPS_URL:-https://simplemaps.com/static/data/us-zips/${VERSION}/basic/simplemaps_uszips_basicv${VERSION}.zip}"
  SOURCE="$URL"

  echo "Downloading SimpleMaps US Zips v${VERSION}..."
  if ! curl -sSL --fail --http1.1 --retry 3 --retry-all-errors \
    -A "$CURL_UA" \
    -H "Referer: $PAGE_URL" \
    "$URL" -o "$WORKDIR/uszips.zip"; then
    cat >&2 <<MSG
Failed to download SimpleMaps US Zips from:
  $URL

If SimpleMaps blocks direct curl downloads, download the free ZIP in a browser
from $PAGE_URL and rerun with:
  US_ZIPS_FILE=/path/to/simplemaps_uszips_basicv${VERSION}.zip ./scripts/load_us_zips.sh
MSG
    exit 1
  fi
fi

unzip -o -q "$WORKDIR/uszips.zip" -d "$WORKDIR"

if [ ! -f "$WORKDIR/uszips.csv" ]; then
  echo "Expected uszips.csv inside the ZIP file, but it was not found." >&2
  exit 1
fi

# Escape single quotes for the SQL string literals below.
VERSION_SQL="${VERSION//\'/\'\'}"
SOURCE_SQL="${SOURCE//\'/\'\'}"

echo "Loading into us_zips..."
psql "$DB" -v ON_ERROR_STOP=1 <<SQL
BEGIN;

CREATE TEMP TABLE _uszips_staging (
    zip TEXT, lat TEXT, lng TEXT, city TEXT, state_id TEXT, state_name TEXT,
    zcta TEXT, parent_zcta TEXT, population TEXT, density TEXT,
    county_fips TEXT, county_name TEXT, county_weights TEXT,
    county_names_all TEXT, county_fips_all TEXT,
    imprecise TEXT, military TEXT, timezone TEXT
);

\\copy _uszips_staging FROM '$WORKDIR/uszips.csv' WITH (FORMAT csv, HEADER true)

TRUNCATE us_zips;

INSERT INTO us_zips (
    zip, city, state_id, state_name, is_zcta, parent_zcta,
    population, density, county_fips, county_name, county_weights,
    county_fips_all, county_names_all, is_imprecise, is_military,
    timezone, location
)
SELECT
    zip,
    city,
    state_id,
    state_name,
    zcta = 'TRUE',
    NULLIF(parent_zcta, ''),
    NULLIF(population, '')::INTEGER,
    NULLIF(density, '')::NUMERIC,
    NULLIF(county_fips, ''),
    NULLIF(county_name, ''),
    NULLIF(county_weights, '')::JSONB,
    COALESCE(STRING_TO_ARRAY(NULLIF(county_fips_all, ''), '|'), '{}'),
    COALESCE(STRING_TO_ARRAY(NULLIF(county_names_all, ''), '|'), '{}'),
    imprecise = 'TRUE',
    military = 'TRUE',
    NULLIF(timezone, ''),
    ST_SetSRID(ST_MakePoint(lng::DOUBLE PRECISION, lat::DOUBLE PRECISION), 4326)::GEOGRAPHY
FROM _uszips_staging;

INSERT INTO reference_dataset_loads (dataset, version, source_url, row_count)
SELECT 'us_zips', '$VERSION_SQL', '$SOURCE_SQL', COUNT(*) FROM us_zips;

COMMIT;

SELECT COUNT(*) AS zips_loaded, '$VERSION_SQL' AS release_version FROM us_zips;
SQL

echo "Done. Reminder: production use of the free dataset requires a link"
echo "back to https://simplemaps.com/data/us-zips"
