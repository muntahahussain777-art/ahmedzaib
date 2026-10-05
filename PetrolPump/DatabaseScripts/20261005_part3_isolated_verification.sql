-- Part 3 isolated verification (safe unique sync_ids; cleaned up).
-- Validates LWW, no-resurrect, and concurrent child balance ops (not absolute LWW on dealers).

DO $$
DECLARE
  cust uuid := gen_random_uuid();
  deal uuid := gen_random_uuid();
  petrol uuid := gen_random_uuid();
  payout_a uuid := gen_random_uuid();
  payout_b uuid := gen_random_uuid();
  op_a uuid := gen_random_uuid();
  op_b uuid := gen_random_uuid();
  n text;
  still_del boolean;
  dd_sum double precision;
  d_sum double precision;
BEGIN
  INSERT INTO zaib_customers (sync_id, name, mobile, date_text, updated_at, device_id)
  VALUES (cust, 'P3IsolatedCust', 'p3-000', '2026-10-05', '2026-10-05T01:00:00Z', 'pc-p3');

  INSERT INTO zaib_dealers (sync_id, dealer_name, dd_amount, d_amount, date_text, updated_at, device_id)
  VALUES (deal, 'P3IsolatedDealer', 0, 0, '2026-10-05', '2026-10-05T01:00:00Z', 'pc-p3');

  INSERT INTO zaib_petrol_entries (
    sync_id, customer_sync_id, customer_name, date_text, receipt_no, vehicle,
    litter, rate, advance, amount, credit, balance, note, is_initial_entry, processed,
    updated_at, device_id)
  VALUES (
    petrol, cust, 'P3IsolatedCust', '2026-10-05', 'P3-R1', 'V1',
    10, 300, 0, 3000, 3000, 3000, 'p3', 1, 0,
    '2026-10-05T01:05:00Z', 'pc-p3');

  -- Two devices create DIFFERENT payouts for same dealer (both must exist)
  INSERT INTO zaib_dealer_payouts (
    sync_id, dealer_sync_id, dealer_name, amount_given, date_text, note, updated_at, device_id)
  VALUES
    (payout_a, deal, 'P3IsolatedDealer', 25, '2026-10-05', 'device-a', '2026-10-05T01:06:00Z', 'pc-p3'),
    (payout_b, deal, 'P3IsolatedDealer', 40, '2026-10-05', 'device-b', '2026-10-05T01:07:00Z', 'mobile-p3');

  IF (SELECT COUNT(*) FROM zaib_dealer_payouts WHERE dealer_sync_id = deal AND deleted_at IS NULL) <> 2 THEN
    RAISE EXCEPTION 'FAIL concurrent payouts not both retained';
  END IF;

  -- Explicit balance ops (manual/opening style) — both effects retained by sum
  INSERT INTO zaib_dealer_balance_ops (
    sync_id, dealer_sync_id, dd_delta, d_delta, source_kind, source_sync_id,
    date_text, note, updated_at, device_id)
  VALUES
    (op_a, deal, 100, 0, 'manual', 'manual-a', '2026-10-05', 'a', '2026-10-05T01:08:00Z', 'pc-p3'),
    (op_b, deal, 0, 15, 'manual', 'manual-b', '2026-10-05', 'b', '2026-10-05T01:09:00Z', 'mobile-p3');

  SELECT COALESCE(SUM(dd_delta),0), COALESCE(SUM(d_delta),0)
    INTO dd_sum, d_sum
  FROM zaib_dealer_balance_ops
  WHERE dealer_sync_id = deal AND deleted_at IS NULL;

  IF dd_sum <> 100 OR d_sum <> 15 THEN
    RAISE EXCEPTION 'FAIL balance op sums expected dd=100 d=15 got dd=% d=%', dd_sum, d_sum;
  END IF;

  -- mobile update wins on petrol
  UPDATE zaib_petrol_entries
  SET credit = 2800, balance = 2800, updated_at = '2026-10-05T02:00:00Z', device_id = 'mobile-p3'
  WHERE sync_id = petrol;

  UPDATE zaib_petrol_entries
  SET credit = 9999, updated_at = '2026-10-05T01:30:00Z', device_id = 'pc-stale'
  WHERE sync_id = petrol;
  SELECT credit::text INTO n FROM zaib_petrol_entries WHERE sync_id = petrol;
  IF n::numeric = 9999 THEN RAISE EXCEPTION 'FAIL stale overwrite'; END IF;

  -- soft delete + no resurrect at equal timestamp
  UPDATE zaib_customers
  SET deleted_at = '2026-10-05T03:00:00Z', updated_at = '2026-10-05T03:00:00Z', device_id = 'mobile-p3'
  WHERE sync_id = cust;
  UPDATE zaib_customers
  SET deleted_at = NULL, name = 'RESURRECT', updated_at = '2026-10-05T03:00:00Z', device_id = 'pc-bad'
  WHERE sync_id = cust;
  SELECT deleted_at IS NOT NULL INTO still_del FROM zaib_customers WHERE sync_id = cust;
  IF NOT still_del THEN RAISE EXCEPTION 'FAIL customer resurrected'; END IF;

  -- cleanup
  DELETE FROM zaib_dealer_balance_ops WHERE sync_id IN (op_a, op_b);
  DELETE FROM zaib_dealer_payouts WHERE sync_id IN (payout_a, payout_b);
  DELETE FROM zaib_petrol_entries WHERE sync_id = petrol;
  DELETE FROM zaib_dealers WHERE sync_id = deal;
  DELETE FROM zaib_customers WHERE sync_id = cust;

  RAISE NOTICE 'part3_isolated_ok';
END $$;

SELECT 'part3_isolated_ok' AS result;
