#!/usr/bin/env bash
# Money-logic unit tests for the balance/ledger rework.
# Runs every *.sql test against the LOCAL Supabase database (never prod).
# Each test wraps itself in a transaction with a frozen now() and rolls back,
# so it is deterministic and repeatable. Requires `supabase start` first.
#
#   bash supabase/tests/run.sh
set -euo pipefail

DB_CONTAINER="${DB_CONTAINER:-supabase_db_kabanchiki}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail=0
for f in "$DIR"/test_*.sql; do
    name="$(basename "$f")"
    out="$(docker exec -i "$DB_CONTAINER" psql -U postgres -q < "$f" 2>&1)" || true
    oks="$(printf '%s\n' "$out" | grep -cE '^NOTICE:  ok' || true)"
    if printf '%s\n' "$out" | grep -qE 'PASSED'; then
        echo "PASS  $name  ($oks assertions)"
    else
        echo "FAIL  $name"
        printf '%s\n' "$out" | grep -E 'FAIL|ERROR|error:' || printf '%s\n' "$out" | tail -5
        fail=1
    fi
done
exit $fail
