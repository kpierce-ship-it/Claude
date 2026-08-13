# First Dollar — BigQuery + Treasury Query Care Package

A self-contained reference for running First Dollar data queries from Claude Code.

**How to use:** this file lives in the repo so Claude Code (and anyone on the team) can load it before writing queries. Part 1 is a setup prompt for connecting a local machine to BigQuery — paste it into a Claude Code session running on your own laptop and let Claude walk you through connecting, one step at a time. Parts 2–6 are reference knowledge to read before writing any query.

Everything here is read-only against production BigQuery. You are querying a mirror of the app database — you are not touching the live app.

## Part 1 — Connect to BigQuery (paste this to Claude Code as a prompt)

> Help me set up read-only Google BigQuery access on my machine so I can run
> queries from Claude Code. Explain each command in plain language, go ONE STEP AT
> A TIME, and wait for me to confirm each step before the next. If I paste an
> error, troubleshoot before continuing. First ask which OS I'm on (Mac or
> Windows) and adjust commands accordingly; on Windows have me use PowerShell.
>
> STEP 0 — Access gate. Ask me to confirm I've been granted BigQuery IAM access
> (at least "BigQuery Data Viewer" + "BigQuery Job User") on our GCP projects with
> my company Google account. If queries later fail with a permission/403 error,
> that's an IAM access request to our GCP admin — NOT a broken install.
>
> STEP 1 — Install the Google Cloud SDK (gives me the gcloud and bq commands):
> https://cloud.google.com/sdk/docs/install . After installing, tell me to CLOSE
> and REOPEN the terminal, then verify: `gcloud --version` and `bq version`
>
> STEP 2 — Two logins (explain why each):
> ```
> gcloud auth login                      (signs in the CLI; use my COMPANY account)
> gcloud auth application-default login  (credentials for scripts/client libs)
> ```
>
> STEP 3 — Set a safe default project (non-prod):
> ```
> gcloud config set project first-dollar-app-dev
> ```
>
> STEP 4 — Verify with a harmless query against the prod mirror:
> ```
> bq --project_id=first-dollar-app query --use_legacy_sql=false \
>    "SELECT COUNT(*) FROM \`first-dollar-app.refined.refined_organizations\`"
> ```
> If it returns a number, access works.
>
> STEP 5 — Make query runs frictionless: help me allowlist the bq command in Claude
> Code settings (.claude/settings.json or user settings) — e.g. allow "Bash(bq:*)"
> — so Claude Code doesn't prompt me on every query. Explain the tradeoff.
>
> Treat production (first-dollar-app) as READ-ONLY. Start with the OS question.

## Part 2 — Where the data lives

Production app data is mirrored into BigQuery in the project `first-dollar-app`, dataset `refined`. Tables are prefixed `refined_` (e.g. `refined_offerings`). This mirror is the primary source for analytics/ops queries and is read-only.

Environment → GCP project (query the one that matches the environment you mean):

| Environment | GCP project ID |
|---|---|
| prod | `first-dollar-app` |
| staging | `first-dollar-app-staging` |
| develop | `first-dollar-app-develop` |
| dev | `first-dollar-app-dev` |
| sandbox | `first-dollar-app-sandbox` |

**Traps:**
- `first-dollar-app-dev` is not `first-dollar-app-develop` — two different projects.
- `first-dollar-app-fdprod` is not live prod — real production data lives in `first-dollar-app`. Verify the project before trusting results.

## Part 3 — Query-writing conventions (read before writing SQL)

- Standard SQL only: always pass `--use_legacy_sql=false`.
- **SCD tables — filter `is_current`.** Many `refined_` tables are slowly-changing dimensions with historical versions of each row. Unless you want history, add `WHERE is_current` (or `AND o.is_current` in joins). Forgetting this silently multiplies rows.
- **Encrypted columns end in `_enc`** and arrive as ciphertext (envelope-encrypted PII/PHI). Do not expect to read a person's SSN/DOB/name out of them, and do not try to decrypt them.
- **Never SELECT raw PHI into outputs.** Key results by record id / member id / error code — not by name, SSN, or DOB. This keeps query output safe to paste into tickets or Slack.
- The mirror lags live data by up to ~1 day. For recency-sensitive checks (did a transfer just complete?), cross-check Cloud Logging (`gcloud logging read ... --project=first-dollar-app`) rather than trusting the mirror alone.
- Discover tables/columns instead of guessing:
  ```
  bq ls first-dollar-app:refined
  bq show first-dollar-app:refined.refined_offering_claims
  ```
  or query `refined.INFORMATION_SCHEMA.COLUMNS`.
- **Advanced — live (non-lagged) reads via federation.** You can query the live Postgres through the federated connection instead of the mirror:
  ```
  EXTERNAL_QUERY('first-dollar-app.us.first-dollar-app-bq-external-connection', """ <postgres SQL> """)
  ```
  Use Postgres syntax inside the string and cast ENUM columns to text (`status::text`). Same rules apply: read-only, no raw PHI in output.
- Reusable query examples live in the repo under `queries/` — start from those rather than from scratch when one fits.

## Part 4 — Treasury / money-movement primer

Treasury Prime is First Dollar's banking partner. Any `ach_transfer_id` you see is Treasury Prime's gateway ID. When money moves, it must be mirrored on FD's ledgers and kept in sync with the other sources of record (Treasury Prime, Piermont, Xformative).

Claim reimbursements (FSA/HRA/ICHRA/LSA, and HSA withdrawals) pay out via outgoing ACH:
- The payment leg lives in `ach_transfers` (mirror: `refined_ach_transfers`, SCD — filter `is_current`).
- A claim links to its payment by: `offering_claims.ach_transfer_external_id = ach_transfers.ach_transfer_id`.
- Signal of payment state: a PAID non-HSA claim has both an `ach_transfer_external_id` and an `amount_paid`; an APPROVED claim has neither yet. So the ACH link appearing = payment was initiated. This lets you distinguish "stuck in adjudication" from "stuck/errored in payment."
- HSA ACH withdrawal lifecycle updates arrive via Treasury Prime's `ach.update` webhook, which emits `achWithdrawalCompleted` / `achWithdrawalFailed` events.

Notional / RMF ICHRA reconciliation compares a Treasury Prime virtual account's activity against the offering ledger's claim disbursements:
- `refined_notional_funding_accounts` (the TP virtual account per offering) joined to `refined_offerings` (`is_current`, keyed by `public_ulid`).
- Variance = TP account activity vs. ledger disbursements. This is exactly what the repo's `reconcile-offering` command automates (read-only, prod refined).

## Part 5 — Key tables quick reference (`first-dollar-app.refined.*`)

All SCD unless noted — filter `is_current`.

| Table | What it holds |
|---|---|
| `refined_organizations` | Partner orgs (has `short_code`) |
| `refined_organization_memberships` | Who belongs to which org |
| `refined_offerings` | Benefit offerings (keyed by `public_ulid`) |
| `refined_offering_templates` | Offering type/config templates |
| `refined_offering_participants` | Members enrolled in an offering |
| `refined_offering_claims` | Claims; carries `user_id`, `ach_transfer_external_id`, `amount_paid` |
| `refined_offering_funding_events` | Funding into offerings |
| `refined_participant_funding_events` | Per-participant funding |
| `refined_ach_transfers` | ACH legs; `ach_transfer_id` = Treasury Prime gateway id |
| `refined_health_savings_accounts` | HSA accounts |
| `refined_external_bank_accounts` | Linked member bank accounts |
| `refined_notional_funding_accounts` | Treasury Prime virtual accounts (notional/RMF) |
| `refined_users` | Users (PII columns are `_enc` ciphertext) |
| `offering_card_transaction_totals` | Card spend rollups |

Verify columns with `bq show` before relying on them — this list is a map, not a schema.

## Part 6 — Safety rules (non-negotiable)

1. **Read-only against production.** Never write, never run DML. `first-dollar-app` is live prod data.
2. **No raw PHI in output.** Key by ids and codes; `_enc` columns stay encrypted.
3. **Confirm the project before trusting results** (see the traps in Part 2).
4. **Prefer the refined mirror**; only use live federation (`EXTERNAL_QUERY`) when you specifically need non-lagged data, and keep it read-only.
5. If a query needs data you can't reach (permission/403, or an `_enc` value), that's an access/decryption boundary — stop and escalate, don't work around it.
