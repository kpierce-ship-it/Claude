#!/usr/bin/env bash
# Runs queries/bank_gateway_transactions_org_div.sql against the prod
# federated connection (first-dollar-app), read-only.
#
# Prereqs (see FD-BigQuery-Treasury-CarePackage.md Part 1):
#   - gcloud + bq installed and authenticated (gcloud auth login)
#   - IAM: BigQuery Data Viewer + BigQuery Job User on first-dollar-app
#
# Usage:
#   ./queries/run_bank_gateway_transactions_org_div.sh [START_DATE] [END_DATE] [OUTFILE.csv]
#
#   START_DATE / END_DATE   YYYY-MM-DD, inclusive. Default: 2026-08-22 / 2026-08-24
#   OUTFILE.csv              Optional. If given, results are written as CSV
#                             instead of printed as a pretty table.
#
# Examples:
#   ./queries/run_bank_gateway_transactions_org_div.sh
#   ./queries/run_bank_gateway_transactions_org_div.sh 2026-08-01 2026-08-31
#   ./queries/run_bank_gateway_transactions_org_div.sh 2026-08-01 2026-08-31 out.csv

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/bank_gateway_transactions_org_div.sql"

START_DATE="${1:-2026-08-22}"
END_DATE="${2:-2026-08-24}"
OUTFILE="${3:-}"

if ! command -v bq >/dev/null 2>&1; then
  echo "error: 'bq' not found. Install/auth the Cloud SDK first (see FD-BigQuery-Treasury-CarePackage.md Part 1)." >&2
  exit 1
fi

QUERY="$(sed \
  -e "s/__START_DATE__/${START_DATE}/" \
  -e "s/__END_DATE__/${END_DATE}/" \
  "$SQL_FILE")"

if [[ -n "$OUTFILE" ]]; then
  bq --project_id=first-dollar-app query --use_legacy_sql=false --format=csv "$QUERY" > "$OUTFILE"
  echo "Wrote results to $OUTFILE"
else
  bq --project_id=first-dollar-app query --use_legacy_sql=false --format=pretty "$QUERY"
fi
