#!/usr/bin/env bash
# Keep FormTemplate.html in sync with docs/google-form-template.md (for maintainers).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cp "$ROOT/docs/google-form-template.md" "$ROOT/scripts/FormTemplate.html"
echo "Synced scripts/FormTemplate.html from docs/google-form-template.md"
