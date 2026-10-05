# Part 7 — historical opening residual review (READ-ONLY)

Computed including purchases, direct, payouts, and dealer↔dealer transfers.
**Do not auto-seed.** Residuals below need human verification of true opening vs omitted ledger rows.

| Dealer | SyncId | residual_dd | residual_d | existing opening/manual ops |
|---|---|---:|---:|---|
| arif | 89744840-9891-400a-8bca-8586269c4ea6 | 0 | -900000 | none |
| bilwal | 6e52a296-26d7-4bdd-96bb-69d8fabf607d | -483024 | -1068560 | none |
| Habib Sheihk | e2deccc4-c6e9-4855-b08b-3d686e4e6638 | 0 | -1000000 | none |
| hakeem | c136dc4a-e224-4c2a-840c-9fddfbd864fe | 0 | -1254000 | none |
| shera khan | db953a1e-b63b-48ea-a21d-406c748ac37c | -707700 | -1000 | none |
| Wahab broker d | b72d61e7-30ac-483d-baff-80b0060b3eff | 0 | -814877 | none |
| Yaqoob | 158138af-607a-4bc4-82f7-429763ccb9d9 | -2324505 | 0 | none |

Other live dealers: zero residual under the same formula (48).

Script: `20261006_part6_opening_reconciliation_READONLY.sql` (transfers included).
