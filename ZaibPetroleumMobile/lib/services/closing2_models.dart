enum ClosingEntryKind {
  customer,
  dealer,
  bank,
  tempCustomer,
  tempDealer,
  profit,
  loss,
}

class ClosingNamedAmount {
  final String key;
  final String name;
  final double amount;
  final ClosingEntryKind kind;
  final int? entityId;
  final bool isTemp;

  const ClosingNamedAmount({
    required this.key,
    required this.name,
    required this.amount,
    required this.kind,
    this.entityId,
    this.isTemp = false,
  });
}

class Closing2Report {
  final double customerAmt;
  final double customerLit;
  final double purchaseAmt;
  final double purchaseLit;
  final double expense;
  final double custAvg;
  final double dealerAvg;
  final double margin;
  final double grossProfit;
  final double netProfit;
  final List<ClosingNamedAmount> receivables;
  final List<ClosingNamedAmount> payables;
  final double customerTotal;
  final double dealerTotal;
  final double balance;

  const Closing2Report({
    required this.customerAmt,
    required this.customerLit,
    required this.purchaseAmt,
    required this.purchaseLit,
    required this.expense,
    required this.custAvg,
    required this.dealerAvg,
    required this.margin,
    required this.grossProfit,
    required this.netProfit,
    required this.receivables,
    required this.payables,
    required this.customerTotal,
    required this.dealerTotal,
    required this.balance,
  });
}

/// Session-only temp/hidden (PC Closing2 jaisa — DB delete nahi).
class Closing2Session {
  static final List<ClosingNamedAmount> tempReceivables = [];
  static final List<ClosingNamedAmount> tempPayables = [];
  static final Set<int> hiddenCustomerIds = {};
  static final Set<int> hiddenDealerIds = {};
  static final Set<String> hiddenBankNames = {};
  static bool hideProfitLoss = false;

  static void addTemp({required String name, required double amount, required bool receivable}) {
    final n = name.trim();
    if (n.isEmpty || amount == 0) return;
    final list = receivable ? tempReceivables : tempPayables;
    final existing = list.where((e) => e.name.toLowerCase() == n.toLowerCase()).toList();
    if (existing.isNotEmpty) {
      final old = existing.first;
      list.remove(old);
      list.add(ClosingNamedAmount(
        key: old.key,
        name: old.name,
        amount: old.amount + amount,
        kind: receivable ? ClosingEntryKind.tempCustomer : ClosingEntryKind.tempDealer,
        isTemp: true,
      ));
    } else {
      list.add(ClosingNamedAmount(
        key: 'temp_${receivable ? 'r' : 'p'}_${DateTime.now().microsecondsSinceEpoch}',
        name: n,
        amount: amount,
        kind: receivable ? ClosingEntryKind.tempCustomer : ClosingEntryKind.tempDealer,
        isTemp: true,
      ));
    }
  }

  static void removeByKey(String key) {
    tempReceivables.removeWhere((e) => e.key == key);
    tempPayables.removeWhere((e) => e.key == key);
  }

  static void hideEntry(ClosingNamedAmount e) {
    if (e.isTemp) {
      removeByKey(e.key);
      return;
    }
    switch (e.kind) {
      case ClosingEntryKind.customer:
        if (e.entityId != null) hiddenCustomerIds.add(e.entityId!);
        break;
      case ClosingEntryKind.dealer:
        if (e.entityId != null) hiddenDealerIds.add(e.entityId!);
        break;
      case ClosingEntryKind.bank:
        hiddenBankNames.add(e.name);
        break;
      case ClosingEntryKind.profit:
      case ClosingEntryKind.loss:
        hideProfitLoss = true;
        break;
      case ClosingEntryKind.tempCustomer:
      case ClosingEntryKind.tempDealer:
        removeByKey(e.key);
        break;
    }
  }
}
