import '../models/models.dart';

class LedgerFooterTotals {
  final double totalAmount;
  final double totalCredit;
  final double totalBalance;

  const LedgerFooterTotals({
    required this.totalAmount,
    required this.totalCredit,
    required this.totalBalance,
  });

  static LedgerFooterTotals fromDiesel(List<DieselSale> rows) {
    var amount = 0.0;
    var credit = 0.0;
    for (final e in rows) {
      amount += (e.litter == 0 && e.rate == 0) ? e.amount : (e.litter * e.rate + e.advance);
      credit += e.credit;
    }
    return LedgerFooterTotals(totalAmount: amount, totalCredit: credit, totalBalance: amount - credit);
  }

  static LedgerFooterTotals fromDealerGroup(List<DealerGroupReportRow> rows) {
    final seen = <int>{};
    var amount = 0.0;
    var credit = 0.0;
    var balance = 0.0;
    for (final e in rows) {
      if (seen.contains(e.dealerId)) continue;
      seen.add(e.dealerId);
      amount += e.ddAmount;
      credit += e.dAmount;
      balance += e.balance;
    }
    return LedgerFooterTotals(totalAmount: amount, totalCredit: credit, totalBalance: balance);
  }
}

class StockSummaryTotals {
  final double addLitter;
  final double minusLitter;
  final double baqayaLitter;
  final double addAmount;
  final double minusAmount;
  final double netAmount;

  const StockSummaryTotals({
    required this.addLitter,
    required this.minusLitter,
    required this.baqayaLitter,
    required this.addAmount,
    required this.minusAmount,
    required this.netAmount,
  });

  /// Average rate = amount / litter
  double get addAvgRate => addLitter == 0 ? 0 : addAmount / addLitter;
  double get minusAvgRate => minusLitter == 0 ? 0 : minusAmount / minusLitter;

  static StockSummaryTotals fromRows(List<StockDieselEntry> rows) {
    var addL = 0.0;
    var minusL = 0.0;
    var addA = 0.0;
    var minusA = 0.0;
    for (final e in rows) {
      final litter = e.litter.abs();
      final amount = litter * e.rate;
      if (e.isMinus) {
        minusL += litter;
        minusA += amount;
      } else {
        addL += litter;
        addA += amount;
      }
    }
    return StockSummaryTotals(
      addLitter: addL,
      minusLitter: minusL,
      baqayaLitter: addL - minusL,
      addAmount: addA,
      minusAmount: minusA,
      netAmount: addA - minusA,
    );
  }
}

/// Litter sum → Amount (Σ litter×rate) → Avg = amount / litter
/// Skip rows where litter AND rate are both 0 (WinForms-style).
class LitterRateAvgSummary {
  final double litterSum;
  final double amountSum;

  const LitterRateAvgSummary({required this.litterSum, required this.amountSum});

  double get avgRate => litterSum == 0 ? 0 : amountSum / litterSum;

  static LitterRateAvgSummary fromDiesel(List<DieselSale> rows) {
    var litter = 0.0;
    var amount = 0.0;
    for (final e in rows) {
      if (e.litter == 0 && e.rate == 0) continue;
      litter += e.litter;
      amount += e.litter * e.rate;
    }
    return LitterRateAvgSummary(litterSum: litter, amountSum: amount);
  }

  static LitterRateAvgSummary fromDealerAmount(List<DealerAmountEntry> rows) {
    var litter = 0.0;
    var amount = 0.0;
    for (final e in rows) {
      if (e.addDiesel == 0 && e.rate == 0) continue;
      litter += e.addDiesel;
      amount += e.addDiesel * e.rate;
    }
    return LitterRateAvgSummary(litterSum: litter, amountSum: amount);
  }
}
