-- READ-ONLY historical opening reconciliation report (Part 5).
-- Run manually on an isolated copy or via MCP SELECT-only. Does NOT modify data.
-- Compare cloud dealer absolute vs sum(children) vs existing opening ops.

WITH child_dd AS (
  SELECT dealer_sync_id AS sync_id,
         COALESCE(SUM(COALESCE(add_diesel,0) * COALESCE(rate,0)),0) AS purchase_dd
  FROM zaib_dealer_purchases WHERE deleted_at IS NULL
  GROUP BY dealer_sync_id
),
child_direct AS (
  SELECT dealer_sync_id AS sync_id,
         COALESCE(SUM(COALESCE(amount_given,0)),0) AS direct_dd
  FROM zaib_dealer_direct WHERE deleted_at IS NULL
  GROUP BY dealer_sync_id
),
child_d AS (
  SELECT dealer_sync_id AS sync_id,
         COALESCE(SUM(COALESCE(amount_given,0)),0) AS payout_d
  FROM zaib_dealer_payouts WHERE deleted_at IS NULL
  GROUP BY dealer_sync_id
),
opening_ops AS (
  SELECT dealer_sync_id AS sync_id,
         COALESCE(SUM(dd_delta),0) AS op_dd,
         COALESCE(SUM(d_delta),0) AS op_d
  FROM zaib_dealer_balance_ops
  WHERE deleted_at IS NULL
    AND source_kind IN ('opening','opening_seed','manual')
    AND (source_sync_id LIKE 'opening:%' OR source_kind = 'manual')
  GROUP BY dealer_sync_id
)
SELECT
  d.sync_id,
  d.dealer_name,
  COALESCE(d.dd_amount,0) AS cloud_dd,
  COALESCE(d.d_amount,0) AS cloud_d,
  COALESCE(p.purchase_dd,0) + COALESCE(x.direct_dd,0) AS child_dd,
  COALESCE(y.payout_d,0) AS child_d,
  COALESCE(d.dd_amount,0) - (COALESCE(p.purchase_dd,0) + COALESCE(x.direct_dd,0)) AS residual_dd,
  COALESCE(d.d_amount,0) - COALESCE(y.payout_d,0) AS residual_d,
  COALESCE(o.op_dd,0) AS existing_op_dd,
  COALESCE(o.op_d,0) AS existing_op_d,
  CASE
    WHEN ABS(COALESCE(d.dd_amount,0) - (COALESCE(p.purchase_dd,0) + COALESCE(x.direct_dd,0))) < 0.01
     AND ABS(COALESCE(d.d_amount,0) - COALESCE(y.payout_d,0)) < 0.01
      THEN 'zero_residual_ok'
    WHEN COALESCE(o.op_dd,0) <> 0 OR COALESCE(o.op_d,0) <> 0
      THEN 'has_opening_or_manual_ops_review'
    WHEN ABS(COALESCE(d.dd_amount,0) - (COALESCE(p.purchase_dd,0) + COALESCE(x.direct_dd,0))) >= 0.01
      OR ABS(COALESCE(d.d_amount,0) - COALESCE(y.payout_d,0)) >= 0.01
      THEN 'residual_needs_human_review'
    ELSE 'ok'
  END AS status
FROM zaib_dealers d
LEFT JOIN child_dd p ON p.sync_id = d.sync_id
LEFT JOIN child_direct x ON x.sync_id = d.sync_id
LEFT JOIN child_d y ON y.sync_id = d.sync_id
LEFT JOIN opening_ops o ON o.sync_id = d.sync_id
WHERE d.deleted_at IS NULL
ORDER BY status, d.dealer_name;
