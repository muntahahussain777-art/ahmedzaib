-- Isolated verification notes for Part 1 SyncApplyGuard scoping.
-- Run against a COPY of local SQLite (never production). Expected outcomes:

-- A) After EnsureLocalSyncReady / sync start: SyncApplyGuard row count = 0
--    (stale guard cleared; rows are NOT mass SyncDirty=1)
SELECT COUNT(*) AS guard_rows FROM SyncApplyGuard;

-- B) During remote apply transaction only, guard may briefly exist on the writer
--    connection; other connections must still mark SyncDirty=1 on business edits.
--    After apply commit: guard_rows = 0 again.

-- C) Two PetrolAdd rows with identical values but different SyncId must both remain
--    after app restart / pull (no value-fingerprint delete).
SELECT SyncId, CustomerId, Date, Amount, Litter, Rate, ReceiptNo, vehicle
FROM PetrolAdd
ORDER BY CustomerId, Date, Amount, SyncId;
