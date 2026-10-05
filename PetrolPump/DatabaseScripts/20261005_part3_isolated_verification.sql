-- Part 3 isolated verification (safe: unique sync_ids, cleaned up).
-- Run via Supabase SQL editor / MCP. Does not touch production business names.

DO $$
DECLARE
  cust uuid := gen_random_uuid();
  deal uuid := gen_random_uuid();
  petrol uuid := gen_random_uuid();
  payout uuid := gen_random_uuid();
  n text;
  still_del boolean;
BEGIN
  -- PC→cloud insert
  INSERT INTO zaib_customers (sync_id, name, mobile, date_text, updated_at, device_id)
  VALUES (cust, 'P3IsolatedCust', 'p3-000', '2026-10-05', '2026-10-05T01:00:00Z', 'pc-p3');
  INSERT INTO zaib_dealers (sync_id, dealer_name, dd_amount, d_amount, date_text, updated_at, device_id)
  VALUES (deal, 'P3IsolatedDealer', 100, 50, '2026-10-05', '2026-10-05T01:00:00Z', 'pc-p3');
  INSERT INTO zaib_petrol_entries (
    sync_id, customer_sync_id, customer_name, date_text, receipt_no, vehicle,
    litter, rate, advance, amount, credit, balance, note, is_initial_entry, processed,
    updated_at, device_id)
  VALUES (
    petrol, cust, 'P3IsolatedCust', '2026-10-05', 'P3-R1', 'V1',
    10, 300, 0, 3000, 3000, 3000, 'p3', 1, 0,
    '2026-10-05T01:05:00Z', 'pc-p3');
  INSERT INTO zaib_dealer_payouts (
    sync_id, dealer_sync_id, dealer_name, amount_given, date_text, note, updated_at, device_id)
  VALUES (payout, deal, 'P3IsolatedDealer', 25, '2026-10-05', 'p3', '2026-10-05T01:06:00Z', 'pc-p3');

  -- mobile update wins
  UPDATE zaib_petrol_entries
  SET credit = 2800, balance = 2800, updated_at = '2026-10-05T02:00:00Z', device_id = 'mobile-p3'
  WHERE sync_id = petrol;

  -- stale PC overwrite rejected
  UPDATE zaib_petrol_entries
  SET credit = 9999, updated_at = '2026-10-05T01:30:00Z', device_id = 'pc-stale'
  WHERE sync_id = petrol;
  SELECT credit::text INTO n FROM zaib_petrol_entries WHERE sync_id = petrol;
  IF n::numeric = 9999 THEN RAISE EXCEPTION 'FAIL stale overwrite'; END IF;

  -- concurrent dealer balance: newer wins
  UPDATE zaib_dealers SET d_amount = 75, updated_at = '2026-10-05T02:10:00Z', device_id = 'mobile-p3' WHERE sync_id = deal;
  UPDATE zaib_dealers SET d_amount = 60, updated_at = '2026-10-05T02:05:00Z', device_id = 'pc-p3' WHERE sync_id = deal;
  SELECT d_amount::text INTO n FROM zaib_dealers WHERE sync_id = deal;
  IF n::numeric <> 75 THEN RAISE EXCEPTION 'FAIL dealer LWW expected 75 got %', n; END IF;

  -- soft delete + no resurrect at equal timestamp
  UPDATE zaib_customers
  SET deleted_at = '2026-10-05T03:00:00Z', updated_at = '2026-10-05T03:00:00Z', device_id = 'mobile-p3'
  WHERE sync_id = cust;
  UPDATE zaib_customers
  SET deleted_at = NULL, name = 'RESURRECT', updated_at = '2026-10-05T03:00:00Z', device_id = 'pc-bad'
  WHERE sync_id = cust;
  SELECT deleted_at IS NOT NULL INTO still_del FROM zaib_customers WHERE sync_id = cust;
  IF NOT still_del THEN RAISE EXCEPTION 'FAIL customer resurrected'; END IF;

  -- cleanup isolated rows
  DELETE FROM zaib_dealer_payouts WHERE sync_id = payout;
  DELETE FROM zaib_petrol_entries WHERE sync_id = petrol;
  DELETE FROM zaib_dealers WHERE sync_id = deal;
  DELETE FROM zaib_customers WHERE sync_id = cust;

  RAISE NOTICE 'part3_isolated_ok';
END $$;

SELECT 'part3_isolated_ok' AS result;
