-- OPTIONAL / MANUAL REVIEW ONLY — historical dealer opening residuals
-- =============================================================================
-- DO NOT run automatically on production fleets from CI or app startup.
-- Run only after manual review on an isolated copy (or via controlled MCP test).
--
-- Goal: seed opening balance ops ONLY where residual opening
--   (|DDAmount| + |DAmount| minus sum of child markers) is unambiguous.
-- Idempotency: source_sync_id = 'opening:' || dealer.sync_id (ON CONFLICT DO NOTHING).
--
-- Local SQLite (WinForms): inserts into SyncDealerBalanceOp + SyncBalanceApplied.
-- Cloud (Supabase): mirror into zaib_dealer_balance_ops with source_kind = 'opening_seed'
--   ONLY if you have verified residuals — prefer client-side opening enqueue going forward.
--
-- Tracking table for reviewed seeds (SQLite or staging DB):
CREATE TABLE IF NOT EXISTS zaib_dealer_opening_seed (
  dealer_sync_id TEXT PRIMARY KEY,
  dd_delta REAL NOT NULL DEFAULT 0,
  d_delta REAL NOT NULL DEFAULT 0,
  note TEXT,
  seeded_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

-- Example pattern (commented — requires human-approved dealer list):
-- INSERT INTO SyncDealerBalanceOp (SyncId, DealerSyncId, DdDelta, DDelta, SourceKind, SourceSyncId, DateText, UpdatedAt, SyncDirty)
-- SELECT lower(hex(randomblob(16))), d.SyncId, @dd, @d, 'opening_seed', 'opening:' || d.SyncId, d.Date, strftime('%Y-%m-%dT%H:%M:%fZ','now'), 1
-- FROM AddDealer d
-- WHERE d.SyncId = @dealer_sync_id
--   AND NOT EXISTS (SELECT 1 FROM SyncBalanceApplied m WHERE m.SourceSyncId = 'opening:' || d.SyncId);

SELECT 'opening_seed_script_documentation_only' AS notice;
