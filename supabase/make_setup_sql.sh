#!/usr/bin/env bash
# Combines all migrations into ONE file you can paste into
# Supabase Dashboard → SQL Editor (alternative to `supabase db push`).
# Run it only once on a fresh project.
set -euo pipefail
cd "$(dirname "$0")"
{
  echo "-- Woops: full database setup. Paste into Supabase → SQL Editor → Run (once, on a new project)."
  for f in migrations/*.sql; do
    echo; echo "-- ===== $(basename "$f") ====="; cat "$f"
  done
} > setup_all.sql
echo "Created supabase/setup_all.sql"
