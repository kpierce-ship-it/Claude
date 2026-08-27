-- Notional Book Transfers (Treasury Prime)
--
-- Identifies offering funding events settled via an internal Treasury Prime
-- book transfer (as opposed to an ACH pull) — these carry an
-- external_payment_id prefixed "Book_". The receiving account is the
-- offering's notional funding account (notional_funding_accounts.account_id),
-- which is what actually gets credited when the partner books funds in.
--
-- Confirmed against live data: external_payment_id uses a lowercase "book_"
-- prefix (e.g. book_11n6hwwaaq16rbg), not "Book_".
--
-- ASSUMPTION TO VERIFY: `notional_funding_accounts` has an `account_id`
-- column live, mirroring the confirmed `refined_notional_funding_accounts.account_id`.
--
-- ThresholdDollarAmount / RMF threshold: offering_funding_events on the live
-- Postgres side only has the raw `calculation_snapshot` JSONB blob — the
-- flattened calc_* columns (calc_threshold_pct, calc_required_floor, etc.)
-- only exist on the refined BigQuery mirror, derived from this same JSON.
-- It's nested under an "rmf" object, camelCase:
--   calculation_snapshot->'rmf'->>'thresholdDollarAmount'
-- (there's also a sibling emergencyThresholdDollarAmount under the same
-- "rmf" object, not currently pulled here.)
--
-- CONFIRMED: book_ transfer settlement events have calculation_snapshot = null
-- — the RMF calc doesn't run on the transfer itself. So the threshold is
-- looked up via a LATERAL join: for each book_ row, take the most recent
-- funding event for the SAME offering, at or before this event's created_at,
-- that does carry a non-null rmf.thresholdDollarAmount. threshold_source_*
-- columns show which event the value was sourced from, for audit purposes.

SELECT * FROM EXTERNAL_QUERY("first-dollar-app.us.first-dollar-app-bq-external-connection", """
select
ofe.id as funding_event_id,
ofe.public_id::text as public_id,
ofe.external_payment_id,
ofe.external_payment_status::text,
ofe.status::text as funding_event_status,
ofe.funding_amount,
ofe.created_at,
ofe.approved_at,
ofe.payment_received_at,
o.public_id as offering_id,
o.name as offering_name,
nfa.id as notional_funding_account_id,
nfa.account_id as receiving_account_id,
org.name as organization_name,
oorg.name as division_name,
ptnr.short_code as partner,
rmf.threshold_dollar_amount,
rmf.source_funding_event_id as threshold_source_funding_event_id,
rmf.source_created_at as threshold_source_created_at
from offering_funding_events ofe
join offerings o on o.id = ofe.offering_id
join notional_funding_accounts nfa on nfa.id = ofe.funding_account_id
join programs p on p.id = o.program_id
join organizations org on org.id = p.organization_id
join organizations oorg on oorg.id = o.organization_id
join partners ptnr on ptnr.id = p.partner_id
left join lateral (
  select
    (x.calculation_snapshot->'rmf'->>'thresholdDollarAmount')::numeric as threshold_dollar_amount,
    x.id as source_funding_event_id,
    x.created_at as source_created_at
  from offering_funding_events x
  where x.offering_id = ofe.offering_id
    and x.calculation_snapshot->'rmf'->>'thresholdDollarAmount' is not null
    and x.created_at <= ofe.created_at
  order by x.created_at desc
  limit 1
) rmf on true
where left(ofe.external_payment_id, 5) = 'book_'
order by ofe.created_at desc
""");
