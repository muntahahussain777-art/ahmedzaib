import '../data/app_database.dart';
import '../models/models.dart';
import 'closing2_models.dart';

export 'closing2_models.dart';

class Closing2Service {
  static Future<Closing2Report> load({
    required String fromDate,
    required String toDate,
  }) async {
    final db = await AppDatabase.instance.database;

    final saleRows = await db.rawQuery('''
      SELECT
        IFNULL(SUM(
          CASE
            WHEN IFNULL(Litter,0) = 0 OR IFNULL(Rate,0) = 0 THEN IFNULL(Balance,0)
            ELSE IFNULL(Litter,0) * IFNULL(Rate,0)
          END
        ), 0) AS amt,
        IFNULL(SUM(IFNULL(Litter,0)), 0) AS lit
      FROM PetrolAdd
      WHERE IFNULL(IsInitialEntry, 1) = 1
        AND date(Date) >= date(?)
        AND date(Date) <= date(?)
    ''', [fromDate, toDate]);

    final purchaseRows = await db.rawQuery('''
      SELECT
        IFNULL(SUM(IFNULL(AddDisel,0) * IFNULL(Rate,0)), 0) AS amt,
        IFNULL(SUM(IFNULL(AddDisel,0)), 0) AS lit
      FROM AddStock
      WHERE date(Date) >= date(?)
        AND date(Date) <= date(?)
    ''', [fromDate, toDate]);

    final expenseRows = await db.rawQuery('''
      SELECT IFNULL(SUM(IFNULL(Amount,0)), 0) AS amt
      FROM Expensetable
      WHERE date(EDate) >= date(?)
        AND date(EDate) <= date(?)
    ''', [fromDate, toDate]);

    final customerAmt = asDouble(saleRows.first['amt']);
    final customerLit = asDouble(saleRows.first['lit']);
    final purchaseAmt = asDouble(purchaseRows.first['amt']);
    final purchaseLit = asDouble(purchaseRows.first['lit']);
    final expense = asDouble(expenseRows.first['amt']);

    final custAvg = customerLit > 0 ? customerAmt / customerLit : 0.0;
    final dealerAvg = purchaseLit > 0 ? purchaseAmt / purchaseLit : 0.0;
    final margin = custAvg - dealerAvg;
    final grossProfit = margin * customerLit;
    final netProfit = grossProfit - expense;

    final recv = <ClosingNamedAmount>[];
    final pay = <ClosingNamedAmount>[];

    final custBal = await db.rawQuery('''
      SELECT c.id AS cid, c.Name AS name,
             IFNULL(SUM(
               CASE
                 WHEN IFNULL(p.IsInitialEntry, 1) = 0 THEN 0
                 WHEN IFNULL(p.Litter, 0) = 0 AND IFNULL(p.Rate, 0) = 0
                   THEN IFNULL(p.Amount, 0) + IFNULL(p.Advance, 0)
                 ELSE IFNULL(p.Litter, 0) * IFNULL(p.Rate, 0) + IFNULL(p.Advance, 0)
               END
               -
               CASE
                 WHEN IFNULL(p.IsInitialEntry, 1) = 0 THEN
                   CASE
                     WHEN IFNULL(p.Credit, 0) <> 0 THEN IFNULL(p.Credit, 0)
                     ELSE IFNULL(p.Amount, 0) + IFNULL(p.Advance, 0)
                   END
                 ELSE IFNULL(p.Credit, 0)
               END
             ), 0) AS bal
      FROM PetrolAdd p
      INNER JOIN AddCustomer c ON c.id = p.CustomerId
      GROUP BY c.id, c.Name
      HAVING bal > 0
      ORDER BY bal DESC
    ''');
    for (final r in custBal) {
      final id = asInt(r['cid']) ?? 0;
      if (Closing2Session.hiddenCustomerIds.contains(id)) continue;
      recv.add(ClosingNamedAmount(
        key: 'cust_$id',
        name: (r['name'] ?? '').toString(),
        amount: asDouble(r['bal']),
        kind: ClosingEntryKind.customer,
        entityId: id,
      ));
    }

    final dealerBal = await db.rawQuery('''
      SELECT Did AS did, DealerName AS name,
             IFNULL(DDAmount,0) - IFNULL(DAmount,0) AS bal
      FROM AddDealer
      WHERE IFNULL(DDAmount,0) - IFNULL(DAmount,0) > 0
      ORDER BY bal DESC
    ''');
    for (final r in dealerBal) {
      final id = asInt(r['did']) ?? 0;
      if (Closing2Session.hiddenDealerIds.contains(id)) continue;
      pay.add(ClosingNamedAmount(
        key: 'deal_$id',
        name: (r['name'] ?? '').toString(),
        amount: asDouble(r['bal']),
        kind: ClosingEntryKind.dealer,
        entityId: id,
      ));
    }

    final banks = await db.rawQuery('''
      SELECT IFNULL(BankName,'Bank') AS name,
             IFNULL(SUM(Amount),0) AS bal
      FROM BankTransactions
      GROUP BY IFNULL(BankName,'Bank')
      HAVING bal != 0
    ''');
    for (final r in banks) {
      final bankName = 'Bank ${(r['name'] ?? '').toString()}';
      if (Closing2Session.hiddenBankNames.contains(bankName)) continue;
      final bal = asDouble(r['bal']);
      if (bal > 0) {
        recv.add(ClosingNamedAmount(
          key: 'bank_r_$bankName',
          name: bankName,
          amount: bal,
          kind: ClosingEntryKind.bank,
        ));
      } else if (bal < 0) {
        pay.add(ClosingNamedAmount(
          key: 'bank_p_$bankName',
          name: bankName,
          amount: bal.abs(),
          kind: ClosingEntryKind.bank,
        ));
      }
    }

    if (!Closing2Session.hideProfitLoss) {
      if (netProfit > 0) {
        pay.add(ClosingNamedAmount(
          key: 'profit',
          name: 'Profit Dealer',
          amount: netProfit,
          kind: ClosingEntryKind.profit,
        ));
      } else if (netProfit < 0) {
        recv.add(ClosingNamedAmount(
          key: 'loss',
          name: 'Loss Customer Payable',
          amount: netProfit.abs(),
          kind: ClosingEntryKind.loss,
        ));
      }
    }

    recv.addAll(Closing2Session.tempReceivables);
    pay.addAll(Closing2Session.tempPayables);

    final customerTotal = recv.fold<double>(0, (s, e) => s + e.amount);
    final dealerTotal = pay.fold<double>(0, (s, e) => s + e.amount);

    return Closing2Report(
      customerAmt: customerAmt,
      customerLit: customerLit,
      purchaseAmt: purchaseAmt,
      purchaseLit: purchaseLit,
      expense: expense,
      custAvg: custAvg,
      dealerAvg: dealerAvg,
      margin: margin,
      grossProfit: grossProfit,
      netProfit: netProfit,
      receivables: recv,
      payables: pay,
      customerTotal: customerTotal,
      dealerTotal: dealerTotal,
      balance: customerTotal - dealerTotal,
    );
  }
}
