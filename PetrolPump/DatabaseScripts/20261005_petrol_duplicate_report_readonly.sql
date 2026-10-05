-- READ-ONLY: suspected petrol duplicates (same business values, different sync_id).
-- Do NOT run 20261005_petrol_dedupe_soft_delete.sql again.
-- Do NOT auto-delete. Distinct SyncIds are separate entries unless independently proven duplicates.
-- Safe to run on a backup / isolated copy.

-- 1) Suspected live duplicates (report only)
WITH keyed AS (
  SELECT
    sync_id,
    customer_sync_id,
    COALESCE(date_text, '') AS date_text,
    COALESCE(amount, 0) AS amount,
    COALESCE(credit, 0) AS credit,
    COALESCE(is_initial_entry, 1) AS is_initial_entry,
    COALESCE(advance, 0) AS advance,
    COALESCE(litter, 0) AS litter,
    COALESCE(rate, 0) AS rate,
    COALESCE(receipt_no, '') AS receipt_no,
    COALESCE(vehicle, '') AS vehicle,
    updated_at,
    deleted_at,
    device_id
  FROM zaib_petrol_entries
  WHERE deleted_at IS NULL
),
grp AS (
  SELECT
    customer_sync_id, date_text, amount, credit, is_initial_entry,
    advance, litter, rate, receipt_no, vehicle,
    COUNT(*) AS n,
    COUNT(DISTINCT sync_id) AS distinct_sync_ids
  FROM keyed
  GROUP BY 1,2,3,4,5,6,7,8,9,10
  HAVING COUNT(DISTINCT sync_id) > 1
)
SELECT k.*
FROM keyed k
JOIN grp g USING (
  customer_sync_id, date_text, amount, credit, is_initial_entry,
  advance, litter, rate, receipt_no, vehicle
)
ORDER BY k.customer_sync_id, k.date_text, k.amount, k.updated_at DESC;

-- 2) Recovery CANDIDATES from prior fingerprint soft-delete (report only — do not restore blindly)
SELECT
  sync_id,
  customer_sync_id,
  date_text,
  amount,
  credit,
  litter,
  rate,
  receipt_no,
  vehicle,
  deleted_at,
  updated_at,
  device_id
FROM zaib_petrol_entries
WHERE deleted_at IS NOT NULL
  AND COALESCE(device_id, '') LIKE '%dedupe-keep-newest%'
ORDER BY deleted_at DESC, updated_at DESC;
