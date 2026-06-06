#!/usr/bin/env bash
# Download Google Sheet CSV exports into data/ for build-time download links.
# Requires CHAR_DATA_URL and CASE_DATA_URL (same URLs used by R at render time).

set -euo pipefail

if [[ -z "${CHAR_DATA_URL:-}" ]]; then
  echo "Error: CHAR_DATA_URL is not set." >&2
  exit 1
fi

if [[ -z "${CASE_DATA_URL:-}" ]]; then
  echo "Error: CASE_DATA_URL is not set." >&2
  exit 1
fi

mkdir -p data
curl -sSL "$CHAR_DATA_URL" -o data/characteristic_data.csv
curl -sSL "$CASE_DATA_URL" -o data/case_management.csv
echo "Fetched sheet data into data/"
