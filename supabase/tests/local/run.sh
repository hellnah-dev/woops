#!/usr/bin/env bash
# Runs all migrations + security tests against a throwaway local PostgreSQL DB.
# Requires: PostgreSQL 15+ client/server tools on PATH (e.g. `brew install postgresql@17`).
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd ../.. && pwd)"
DB="amora_test_$$"
createdb "$DB"
trap 'dropdb --if-exists "$DB" >/dev/null 2>&1 || true' EXIT
PSQL=(psql -X -q -v ON_ERROR_STOP=1 -d "$DB")
"${PSQL[@]}" -f 00_supabase_stub.sql
for f in "$ROOT"/migrations/*.sql; do
  echo "→ applying $(basename "$f")"
  "${PSQL[@]}" -f "$f"
done
"${PSQL[@]}" -f 01_test_helpers.sql
"${PSQL[@]}" -P pager=off -f 10_security_tests.sql
