-- OPTIONAL one-time: seed opening ops for NEW empty clients only.
-- DO NOT run on live fleets that already hold correct local DD/D — pull would double openings.
-- Prefer: new dealer inserts enqueue opening ops from the client going forward.
--
-- If you must run: first ensure every live client has SyncBalanceApplied markers for
-- source_sync_id = 'opening:'||dealer.sync_id matching current residual opening,
-- OR wipe local DBs and do a full re-pull after this seed.

-- (Intentionally empty executable body — see Part 3 rollout notes.)
SELECT 'skipped_live_opening_backfill' AS notice;
