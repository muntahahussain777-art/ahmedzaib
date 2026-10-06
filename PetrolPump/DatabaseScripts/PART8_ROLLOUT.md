# Part 8 rollout — trusted server_rev, no public restore, client OCC

## Order (already applied to project `hvcfaslsgewdfblfdsdn` on 2026-10-06)

1. `20261006_part7_occ_delete_feed_lockdown.sql` (prior)
2. `20261006_part8_stamp_occ_no_restore.sql` (this part; repeatable)

## What Part 8 does

- Trusted stamp GUC `zaib.stamping_rev` so BEFORE LWW no longer wipes internal `server_rev` UPDATE.
- Public `zaib_sync_apply(..., p_allow_restore=true)` always returns `restore_not_allowed`.
- Request fingerprint binding (`payload_hash` / table / sync_id).
- ROW_COUNT checks so cancelled UPDATE cannot return `accepted`.
- Additive repair: entity `server_rev` ← latest `zaib_sync_feed.rev` for that SyncId.
- Admin-only `zaib_sync_apply_admin` granted to `service_role` only (not anon/authenticated).

## Clients

- WinForms + Flutter: remove blind `expected_rev_required` overwrite retry.
- Persist observed remote `server_rev` on pull only when local row is clean (`SyncDirty=0`).
- Stamp local `ServerRev` from RPC only on accept/duplicate (or explicit adopt-server conflict reconcile).

## Local SQLite

- No DB reset. Existing `ServerRev` column migration from prior parts is sufficient.
- Backup DB + WAL before any local schema change (standard Part 1 procedure).

## Do not

- Merge to master / force-push.
- Expose service-role keys to clients.
- Auto-restore historical deleted SyncIds.
- Seed residual dealer openings without human amount verification.
