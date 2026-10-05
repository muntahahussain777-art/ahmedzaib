-- Soft-delete duplicate zaib_petrol_entries (same business fingerprint, different sync_id).
-- Keeps newest updated_at so WinForms updates win. Repeatable / additive.
-- Applied 2026-10-05 on project hvcfaslsgewdfblfdsdn.

WITH ranked AS (
  SELECT sync_id,
         ROW_NUMBER() OVER (
           PARTITION BY customer_sync_id,
                        COALESCE(date_text,''),
                        COALESCE(amount,0),
                        COALESCE(credit,0),
                        COALESCE(is_initial_entry,1),
                        COALESCE(advance,0),
                        COALESCE(litter,0),
                        COALESCE(rate,0),
                        COALESCE(receipt_no,''),
                        COALESCE(vehicle,'')
           ORDER BY updated_at DESC NULLS LAST, sync_id DESC
         ) AS rn
  FROM zaib_petrol_entries
  WHERE deleted_at IS NULL
)
UPDATE zaib_petrol_entries e
SET deleted_at = timezone('utc', now()),
    updated_at = timezone('utc', now()),
    device_id = TRIM(BOTH ',' FROM COALESCE(NULLIF(device_id,''), '') || ',dedupe-keep-newest')
FROM ranked r
WHERE e.sync_id = r.sync_id
  AND r.rn > 1
  AND e.deleted_at IS NULL;
