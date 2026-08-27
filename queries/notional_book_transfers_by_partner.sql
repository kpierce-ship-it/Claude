-- Notional Book Transfers (Treasury Prime)
--
-- Identifies offering funding events settled via an internal Treasury Prime
-- book transfer (as opposed to an ACH pull) — these carry an
-- external_payment_id prefixed "Book_". The receiving account is the
-- offering's notional funding account (notional_funding_accounts.account_id),
-- which is what actually gets credited when the partner books funds in.
--
-- ASSUMPTIONS TO VERIFY (not confirmed against the live schema this session):
--   1. The "Book_" prefix match is case-sensitive as given. If Treasury Prime
--      ever sends a different case, switch `like` to `ilike`.
--   2. `notional_funding_accounts` has an `account_id` column live, mirroring
--      the confirmed `refined_notional_funding_accounts.account_id` column.

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
ptnr.short_code as partner
from offering_funding_events ofe
join offerings o on o.id = ofe.offering_id
join notional_funding_accounts nfa on nfa.id = ofe.funding_account_id
join programs p on p.id = o.program_id
join organizations org on org.id = p.organization_id
join organizations oorg on oorg.id = o.organization_id
join partners ptnr on ptnr.id = p.partner_id
where left(ofe.external_payment_id, 5) = 'Book_'
order by ofe.created_at desc
""");
