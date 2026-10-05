# Part 6 — form/path → table → sync/balance coverage

Protocol: `zaib_sync_feed.rev` via locked `zaib_sync_pub` counter (same txn as business write).
Checkpoint: Flutter `chg_v2:REV`; WinForms `__change_feed_v2__`. Legacy `chg:` / `__change_feed__` repaired by replay from 0.

| Form / path | Local table(s) | Cloud table | Balance effect | Marker / op | Sync notes |
|---|---|---|---|---|---|
| Customer add/edit | AddCustomer | zaib_customers | none (customer) | — | LWW + feed |
| Petrol sale | PetrolAdd | zaib_petrol_entries | customer formulas | — | identical amounts keep distinct SyncIds |
| Dealer add / opening | AddDealer | zaib_dealers + zaib_dealer_balance_ops | DD/D opening | `opening:{dealerSync}` | enqueue opening op in same txn |
| Manual dealer DD/D | AddDealer | zaib_dealer_balance_ops | ±DD/±D | SourceSyncId / SyncId | never absolute LWW overwrite of aggregates |
| Payout (credit money) | DieselLedgerCredit | zaib_dealer_payouts | +D | SyncId | reconcile marker |
| Purchase (stock) | AddStock | zaib_dealer_purchases | +DD (qty×rate) | SyncId | |
| Direct payment | DieselLedgerDebit | zaib_dealer_direct | +DD | SyncId | |
| DealertoDealer | DealertoDealer | zaib_dealer_transfers | from +D; to +DD | `{id}:from` / `{id}:to` | delete reverses both |
| Closing2 | AddDealer + SyncDealerBalanceOp | zaib_dealer_balance_ops | closing deltas | ops SyncId | |
| Stock diesel | StockDiesel | zaib_stock_diesel | stock only | — | |
| Bank | BankTransactions | zaib_bank_transactions | bank only | — | |
| Expense | Expensetable | zaib_expenses | expense only | — | |
| Soft delete / tombstone | SyncTombstone | soft `deleted_at` | reverse markers | — | push before pull |
| Keyboard / bulk delete ledgers | child + tombstone | matching cloud | reverse once | SyncBalanceApplied | |

## Exclusions (not dealer DD/D writers)
- Customer petrol amounts, bank, expense, stock quantity (non-dealer).
- Reports / Designer / UI filters (unchanged).

## Opening residuals
- Read-only report: `20261006_part6_opening_reconciliation_READONLY.sql` (includes transfers).
- Do **not** blind-seed residuals. Human review for non-zero residuals without verified opening ops.

## Rollout order
1. Apply `20261006_part6_transactional_pub_feed.sql` (done on project `hvcfaslsgewdfblfdsdn`).
2. Deploy WinForms + Flutter clients that read `zaib_sync_feed` (this commit).
3. Older clients still append to legacy `zaib_sync_changes` via dual-write but must be upgraded — v1 MAX bootstrap remains unsafe.
4. Do not delete feed history or reset app DBs.
