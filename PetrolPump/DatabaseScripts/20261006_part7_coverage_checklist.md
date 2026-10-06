# Part 7 — coverage + security checklist

## Protocol
- Writes: RPC `zaib_sync_apply(table, payload, expected_rev, request_id, allow_restore=false)`
- Server owns `server_rev`; client-supplied rev stripped/ignored
- Feed: `zaib_sync_feed.rev` via locked `zaib_sync_pub` (trigger only)
- Checkpoint: Flutter `chg_v2:`; WinForms `__change_feed_v2__`
- Deletion: `zaib_deleted_registry` + no ordinary resurrect; `RETURN NULL` cancels rejected BEFORE updates (no feed)

## Privileges (verified)
| Object | anon INSERT/UPDATE/DELETE | anon SELECT | anon EXECUTE |
|---|---|---|---|
| entity zaib_* tables | denied | allowed | — |
| zaib_sync_feed | denied | allowed | — |
| zaib_sync_pub | denied | denied | — |
| zaib_sync_apply | — | — | allowed |
| zaib_record_sync_change | — | — | revoked |

## Form → tables → sync/balance
(Same as Part 6 checklist; plus OCC ServerRev on local tables.)

| Path | Local | Cloud | Balance | Notes |
|---|---|---|---|---|
| Customer CRUD | AddCustomer | zaib_customers | — | RPC + ServerRev |
| Petrol | PetrolAdd | zaib_petrol_entries | customer formulas | distinct SyncIds |
| Dealer opening/manual | AddDealer + SyncDealerBalanceOp | zaib_dealers / balance_ops | DD/D | opening ops idempotent |
| Payout/Purchase/Direct | child ledgers | payouts/purchases/direct | ±D/±DD | markers |
| DealertoDealer | DealertoDealer | zaib_dealer_transfers | from D / to DD | reverse on delete |
| Closing2 | balance ops | zaib_dealer_balance_ops | deltas | |
| Tombstones | SyncTombstone | soft deleted_at | reverse once | durable until ack |

## Rollout
1. Migrations `part7a` / `part7b` / `part7c` applied on project `hvcfaslsgewdfblfdsdn`
2. Deploy WinForms + Flutter together (direct upserts now fail with permission denied — intentional)
3. Do not merge master until soak; do not reset DBs
