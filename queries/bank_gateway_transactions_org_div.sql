-- Bank gateway account transactions (deposits/withdrawals) for non-HSA offerings,
-- with an ORG/DIV flag so you can tell top-level orgs apart from divisions.
-- Live federated read (not the lagged `refined` mirror) via EXTERNAL_QUERY.
--
-- Run via queries/run_bank_gateway_transactions_org_div.sh, which fills in
-- __START_DATE__ / __END_DATE__ below. Running this file's SQL directly
-- (e.g. copy-pasted into the BigQuery console) requires replacing those
-- two placeholders with real dates ('YYYY-MM-DD') first.
SELECT
  transaction_date,
  org_short_code,
  organization_name,
  account_id,
  CONCAT(transaction_type, ' [', transaction_id, ']') AS description,
  transaction_type,
  amount,
  current_balance,
  partner_code,
  offering_type,
  org_or_div
FROM EXTERNAL_QUERY(
  "first-dollar-app.us.first-dollar-app-bq-external-connection",
  """
  SELECT DISTINCT ON (bgat.id)
    bga.account_id,
    org.short_code AS org_short_code,
    org.name AS organization_name,
    bgat.transaction_date,
    CAST(bgat.transaction_type AS TEXT) AS transaction_type,
    bgat.transaction_id,
    bgat.amount,
    bgat.current_balance,
    part.short_code AS partner_code,
    CAST(ot.account_type AS TEXT) AS offering_type,
    CASE WHEN org.parent_organization_id IS NULL THEN 'ORG' ELSE 'DIV' END AS org_or_div
  FROM bank_gateway_account_transactions bgat
  JOIN bank_gateway_accounts bga ON bga.id = bgat.bank_gateway_account_id
  JOIN notional_funding_accounts nfa ON nfa.account_id = bga.account_id
  JOIN offerings o ON o.id = nfa.offering_id
  JOIN offering_templates ot ON ot.id = o.offering_template_id
  JOIN programs prog ON prog.id = o.program_id
  JOIN partners part ON part.id = prog.partner_id
  JOIN organizations org ON org.id = o.organization_id
  WHERE CAST(ot.account_type AS TEXT) != 'HSA'
  AND CAST(bgat.transaction_type AS TEXT) IN ('DEPOSIT', 'WITHDRAWAL')
  AND bgat.transaction_date BETWEEN '__START_DATE__' AND '__END_DATE__'
  ORDER BY bgat.id, part.short_code, org.name, bga.account_id, bgat.transaction_date
  """
)
ORDER BY
  partner_code,
  organization_name,
  account_id,
  transaction_id DESC
