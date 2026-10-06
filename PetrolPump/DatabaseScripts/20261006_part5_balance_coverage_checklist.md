# Dealer / customer balance-writing path coverage (Part 5)

## Synced (cross-device)

| Path | Effect | Sync representation |
|------|--------|---------------------|
| Dealer Payout (DieselLedgerCredit) | DAmount += | Child row + SyncBalanceApplied |
| Direct dealer (DieselLedgerDebit) | DDAmount += | Child row + SyncBalanceApplied |
| Purchase / Dealer Amount (AddStock) | DDAmount += AddDisel*Rate | Child row + SyncBalanceApplied |
| Dealer master opening/manual | DD/D deltas | zaib_dealer_balance_ops |
| Closing2 → post to DieselLedgerDebit | DDAmount += | Same as Direct (+ marker in txn) |
| DealertoDealer transfer | from DAmount +=; to DDAmount += | zaib_dealer_transfers + markers `{id}:from` / `{id}:to` |

## Discovery / conflict

| Concern | Mechanism |
|---------|-----------|
| Late offline upload after peer cursor advanced | zaib_sync_changes + contiguous change_id watermark |
| Entity conflict | updated_at + device_id LWW (unchanged) |
| Pull staging | RemoteApplyResult; flush deletes only applied/safelyAlreadyHandled |

## Intentional exclusions / local-only

| Path | Notes |
|------|-------|
| BulMalOwner / BulMalEntry | Mobile local-only; never cloud |
| Customer PetrolAdd amounts | Customer ledger formulas; not dealer DD/D |
| BankTransactions | Synced rows; do not adjust dealer DD/D aggregates |
| StockDiesel | Synced; no dealer DD/D adjust |
| Historical opening residuals | 7 dealers need human review (see readonly report); no blind seed |

## Historical openings

- Read-only report: `20261006_part5_opening_reconciliation_READONLY.sql`
- Snapshot at Part 5: ~48 dealers zero residual; ~7 need review
- Do not run blind opening backfill on live fleets
