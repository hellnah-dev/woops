#!/usr/bin/env bash
# Creates admin/js/config.js from the SUPABASE_* values in ../.env
set -euo pipefail
cd "$(dirname "$0")"
URL=$(grep -E '^SUPABASE_URL=' ../.env | cut -d= -f2-)
KEY=$(grep -E '^SUPABASE_PUBLISHABLE_KEY=' ../.env | cut -d= -f2-)
cat > js/config.js <<JS
// Generated from .env by make_config.sh. Public values only.
export const SUPABASE_URL = '${URL}';
export const SUPABASE_PUBLISHABLE_KEY = '${KEY}';
JS
echo "Created admin/js/config.js"
