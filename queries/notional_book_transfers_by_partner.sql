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
-- ThresholdDollarAmount / RMF threshold: NOT event data. It's a static
-- per-offering setting stored in offerings.offering_config (jsonb), nested
-- under "rmf", camelCase — offering_config->'rmf'->>'thresholdDollarAmount'.
-- (Ruled out calculation_snapshot on offering_funding_events: that's null on
-- book_ transfer settlement events, since the RMF calc doesn't re-run on the
-- transfer itself — the config lives on the offering, not the event.)
-- Falls back to offering_templates.offering_config if the offering doesn't
-- override it. Sibling key emergencyThresholdDollarAmount is also pulled.

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
(coalesce(o.offering_config->'rmf'->>'thresholdDollarAmount', ot.offering_config->'rmf'->>'thresholdDollarAmount'))::numeric as threshold_dollar_amount,
(coalesce(o.offering_config->'rmf'->>'emergencyThresholdDollarAmount', ot.offering_config->'rmf'->>'emergencyThresholdDollarAmount'))::numeric as emergency_threshold_dollar_amount
from offering_funding_events ofe
join offerings o on o.id = ofe.offering_id
join offering_templates ot on ot.id = o.offering_template_id
join notional_funding_accounts nfa on nfa.id = ofe.funding_account_id
join programs p on p.id = o.program_id
join organizations org on org.id = p.organization_id
join organizations oorg on oorg.id = o.organization_id
join partners ptnr on ptnr.id = p.partner_id
where left(ofe.external_payment_id, 5) = 'book_'
order by ofe.created_at desc
""");
