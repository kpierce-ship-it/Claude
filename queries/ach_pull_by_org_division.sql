-- ACH Pull by Org and Division
--
-- Offering funding events (ACH pulls from a partner/member's external bank
-- account into an offering) for 2026-06-01 through 2026-08-30, by org/division.
--
-- Pending transactions: the original version of this query filtered to
-- `ofe.external_payment_id is not null`, which only shows funding events that
-- have already been submitted for ACH processing. A funding event that is
-- still PENDING (created/approved but not yet submitted) has no
-- external_payment_id yet, so it was silently excluded. The filter below adds
-- those back in via a status match on '%pending%'.
--
-- ASSUMPTION TO VERIFY: `status` on offering_funding_events is a Postgres
-- enum and I don't have its literal values confirmed — I'm matching
-- case-insensitively on the substring "pending" rather than an exact value,
-- to avoid guessing wrong. Confirm the real values with:
--   SELECT DISTINCT status FROM offering_funding_events;
-- and tighten the match to an exact value (e.g. status::text = 'PENDING')
-- if you want to be strict about it.

SELECT * FROM EXTERNAL_QUERY("first-dollar-app.us.first-dollar-app-bq-external-connection", """
select
TO_CHAR(ofe.created_at, 'YYYY-MM-DD') as created_at,
org.name as organization_name,
org.name as division_name,
case when oorg.parent_organization_id is null then 'Org' else 'Division' end as division_or_org,
ptnr.short_code as partner,
o.public_id as offering_id,
o.name as offering_name,
ot.account_type::text as offering_type,
ofe.external_payment_id,
ofe.external_payment_status::text,
ofe.external_payment_error_code,
ofe.funding_amount,
ofe.status::text as funding_event_status,
eba.account_number_last4
from offering_funding_events ofe
join offerings o on o.id = ofe.offering_id
join offering_templates ot on ot.id = o.offering_template_id
join programs p on p.id = o.program_id
join organizations org on org.id = p.organization_id
join organizations oorg on oorg.id = o.organization_id
join partners ptnr on ptnr.id = p.partner_id
left join external_bank_accounts eba on eba.id = ofe.external_bank_account_id
where (ofe.external_payment_id is not null or ofe.status::text ilike '%pending%')
and ofe.created_at >= '2026-06-01' and ofe.created_at < '2026-08-31'
order by ofe.created_at desc, ofe.external_payment_status::text
""");
