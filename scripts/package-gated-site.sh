#!/usr/bin/env bash
# Repackage a rendered Quarto _site/ behind SHA1 hash directory paths.
# Requires RESTRICTED_PORTAL_USER and RESTRICTED_PORTAL_PASS environment variables.

set -euo pipefail

if [[ -z "${RESTRICTED_PORTAL_USER:-}" ]]; then
  echo "Error: RESTRICTED_PORTAL_USER is not set." >&2
  exit 1
fi

if [[ -z "${RESTRICTED_PORTAL_PASS:-}" ]]; then
  echo "Error: RESTRICTED_PORTAL_PASS is not set." >&2
  exit 1
fi

if [[ ! -d "_site" ]]; then
  echo "Error: _site/ directory not found. Run 'quarto render' first." >&2
  exit 1
fi

USER_HASH=$(echo -n "$RESTRICTED_PORTAL_USER" | openssl dgst -sha1 | awk '{print $NF}')
PASS_HASH=$(echo -n "$RESTRICTED_PORTAL_PASS" | openssl dgst -sha1 | awk '{print $NF}')
GATE="a${USER_HASH}/a${PASS_HASH}"

echo "Packaging site behind gate: ${GATE}/"

STAGING=$(mktemp -d)
mv _site "$STAGING/quarto_out"
mkdir -p "_site/a${USER_HASH}"
mv "$STAGING/quarto_out" "_site/${GATE}"
rmdir "$STAGING"

cp login_portal/index.html _site/index.html
cp login_portal/styles.css _site/styles.css

echo "Done. Login portal at _site/index.html; site content at _site/${GATE}/"
