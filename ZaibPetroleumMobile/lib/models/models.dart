double asDouble(Object? v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

int? asInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

class CustomerLedgerSummary {
  final double totalAmount;
  final double totalCredit;
  final double balance;

  const CustomerLedgerSummary({
    required this.totalAmount,
    required this.totalCredit,
    required this.balance,
  });
}

class DealerLedgerSummary {
  final double ddAmount;
  final double dAmount;
  final double balance;

  const DealerLedgerSummary({
    required this.ddAmount,
    required this.dAmount,
    required this.balance,
  });
}

class Customer {
  final int? id;
  final String name;
  final String mobile;
  final String date;

  const Customer({
    this.id,
    required this.name,
    required this.mobile,
    required this.date,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'Name': name,
        'Mobile': mobile,
        'Date': date,
      };

  factory Customer.fromMap(Map<String, Object?> map) => Customer(
        id: asInt(map['id']),
        name: (map['Name'] ?? map['name'] ?? '') as String,
        mobile: (map['Mobile'] ?? map['mobile'] ?? '') as String,
        date: (map['Date'] ?? map['date'] ?? '') as String,
      );
}

class DieselSale {
  final int? id;
  final int customerId;
  final String customerName;
  final String date;
  final String receiptNo;
  final String vehicle;
  final double litter;
  final double rate;
  final double amount;
  final double advance;
  final double credit;
  final double balance;
  final String note;

  const DieselSale({
    this.id,
    required this.customerId,
    required this.customerName,
    required this.date,
    required this.receiptNo,
    required this.vehicle,
    required this.litter,
    required this.rate,
    required this.amount,
    required this.advance,
    required this.credit,
    required this.balance,
    required this.note,
  });

  Map<String, Object?> toMap() => {
        'pid': id,
        'CustomerId': customerId,
        'Date': date,
        'ReceiptNo': receiptNo,
        'vehicle': vehicle,
        'Litter': litter,
        'Rate': rate,
        'Amount': amount,
        'Advance': advance,
        'Credit': credit,
        'Balance': balance,
        'Note': note,
        'IsInitialEntry': 1,
        'Processed': 0,
      };

  factory DieselSale.fromMap(Map<String, Object?> map) => DieselSale(
        id: asInt(map['pid'] ?? map['id']),
        customerId: asInt(map['CustomerId']) ?? 0,
        customerName: (map['customer_name'] ?? map['CustomerName'] ?? '') as String,
        date: (map['Date'] ?? '') as String,
        receiptNo: (map['ReceiptNo'] ?? '') as String,
        vehicle: (map['vehicle'] ?? '') as String,
        litter: asDouble(map['Litter']),
        rate: asDouble(map['Rate']),
        amount: asDouble(map['Amount']),
        advance: asDouble(map['Advance']),
        credit: asDouble(map['Credit']),
        balance: asDouble(map['Balance']),
        note: (map['Note'] ?? '') as String,
      );
}

class Dealer {
  final int? id;
  final String name;
  final double ddAmount;
  final double dAmount;
  final String date;

  const Dealer({
    this.id,
    required this.name,
    required this.ddAmount,
    required this.dAmount,
    required this.date,
  });

  double get creditBalance => ddAmount - dAmount;

  Map<String, Object?> toMap() => {
        'Did': id,
        'DealerName': name,
        'DDAmount': ddAmount,
        'DAmount': dAmount,
        'Date': date,
      };

  factory Dealer.fromMap(Map<String, Object?> map) => Dealer(
        id: asInt(map['Did'] ?? map['id']),
        name: (map['DealerName'] ?? map['name'] ?? '') as String,
        ddAmount: asDouble(map['DDAmount'] ?? map['dd_amount']),
        dAmount: asDouble(map['DAmount'] ?? map['d_amount']),
        date: (map['Date'] ?? map['date'] ?? '') as String,
      );
}

class CreditCustomerEntry {
  final int? id;
  final int customerId;
  final String customerName;
  final String date;
  final String receiptNo;
  final double credit;
  final double balance;
  final String note;

  const CreditCustomerEntry({
    this.id,
    required this.customerId,
    required this.customerName,
    required this.date,
    required this.receiptNo,
    required this.credit,
    required this.balance,
    required this.note,
  });

  Map<String, Object?> toMap() => {
        'pid': id,
        'CustomerId': customerId,
        'Date': date,
        'ReceiptNo': receiptNo,
        'Credit': credit,
        'Balance': balance,
        'Note': note,
        'IsInitialEntry': 0,
        'Processed': 0,
      };

  factory CreditCustomerEntry.fromMap(Map<String, Object?> map) => CreditCustomerEntry(
        id: asInt(map['pid'] ?? map['id']),
        customerId: asInt(map['CustomerId']) ?? 0,
        customerName: (map['customer_name'] ?? '') as String,
        date: (map['Date'] ?? '') as String,
        receiptNo: (map['ReceiptNo'] ?? '') as String,
        credit: asDouble(map['Credit']),
        balance: asDouble(map['Balance']),
        note: (map['Note'] ?? '') as String,
      );
}

class DealerPayout {
  final int? id;
  final int dealerId;
  final String dealerName;
  final double amountGiven;
  final String date;
  final String note;

  const DealerPayout({
    this.id,
    required this.dealerId,
    required this.dealerName,
    required this.amountGiven,
    required this.date,
    required this.note,
  });

  Map<String, Object?> toMap() => {
        'LedgerID': id,
        'Did': dealerId,
        'AmounGiven': amountGiven,
        'Date': date,
        'Note': note,
      };

  factory DealerPayout.fromMap(Map<String, Object?> map) => DealerPayout(
        id: asInt(map['LedgerID'] ?? map['id']),
        dealerId: asInt(map['Did']) ?? 0,
        dealerName: (map['dealer_name'] ?? map['DealerName'] ?? '') as String,
        amountGiven: asDouble(map['AmounGiven'] ?? map['amount_given']),
        date: (map['Date'] ?? '') as String,
        note: (map['Note'] ?? '') as String,
      );
}

class DealerAmountEntry {
  final int? id;
  final int dealerId;
  final String dealerName;
  final String date;
  final String vehicle;
  final double rate;
  final double addDiesel;
  final String note;

  const DealerAmountEntry({
    this.id,
    required this.dealerId,
    required this.dealerName,
    required this.date,
    required this.vehicle,
    required this.rate,
    required this.addDiesel,
    required this.note,
  });

  double get amount => rate * addDiesel;

  Map<String, Object?> toMap() => {
        'Sid': id,
        'DealerId': dealerId,
        'Date': date,
        'Vehicle': vehicle,
        'Rate': rate,
        'AddDisel': addDiesel,
        'Note': note,
      };

  factory DealerAmountEntry.fromMap(Map<String, Object?> map) => DealerAmountEntry(
        id: asInt(map['Sid'] ?? map['id']),
        dealerId: asInt(map['DealerId']) ?? 0,
        dealerName: (map['dealer_name'] ?? map['DealerName'] ?? '') as String,
        date: (map['Date'] ?? '') as String,
        vehicle: (map['Vehicle'] ?? '') as String,
        rate: asDouble(map['Rate']),
        addDiesel: asDouble(map['AddDisel'] ?? map['add_diesel']),
        note: (map['Note'] ?? '') as String,
      );
}

class DirectDealerAmount {
  final int? id;
  final int dealerId;
  final String dealerName;
  final double amountGiven;
  final String date;
  final String note;

  const DirectDealerAmount({
    this.id,
    required this.dealerId,
    required this.dealerName,
    required this.amountGiven,
    required this.date,
    required this.note,
  });

  Map<String, Object?> toMap() => {
        'LedgerID': id,
        'Did': dealerId,
        'AmounGiven': amountGiven,
        'Date': date,
        'Note': note,
      };

  factory DirectDealerAmount.fromMap(Map<String, Object?> map) => DirectDealerAmount(
        id: asInt(map['LedgerID'] ?? map['id']),
        dealerId: asInt(map['Did']) ?? 0,
        dealerName: (map['dealer_name'] ?? map['DealerName'] ?? '') as String,
        amountGiven: asDouble(map['AmounGiven'] ?? map['amount_given']),
        date: (map['Date'] ?? '') as String,
        note: (map['Note'] ?? '') as String,
      );
}

class StockDieselEntry {
  final int? id;
  final int dealerId;
  final String dealerName;
  final String date;
  final String vehicle;
  final double rate;
  final double litter;
  final double credit;
  final double debit;
  final String note;
  final bool isMinus;

  const StockDieselEntry({
    this.id,
    required this.dealerId,
    required this.dealerName,
    required this.date,
    required this.vehicle,
    required this.rate,
    required this.litter,
    required this.credit,
    required this.debit,
    required this.note,
    this.isMinus = false,
  });

  Map<String, Object?> toMap() {
    var n = note;
    if (isMinus && !n.contains('[MINUS]')) n = '[MINUS] $n'.trim();
    return {
      'SID': id,
      'SDid': dealerId,
      'Date': date,
      'Vehicle': vehicle,
      'Rate': rate,
      'Litter': litter.abs(),
      'Credit': credit,
      'Debit': debit,
      'Note': n,
    };
  }

  factory StockDieselEntry.fromMap(Map<String, Object?> map) {
    final note = (map['Note'] ?? '') as String;
    final litter = asDouble(map['Litter']);
    final noteU = note.trimLeft().toUpperCase();
    // WinForms: litter < 0 OR note starts with [MINUS]
    final isMinus = litter < 0 || noteU.startsWith('[MINUS]');
    return StockDieselEntry(
      id: asInt(map['SID'] ?? map['id']),
      dealerId: asInt(map['SDid']) ?? 0,
      dealerName: (map['dealer_name'] ?? map['DealerName'] ?? '') as String,
      date: (map['Date'] ?? '') as String,
      vehicle: (map['Vehicle'] ?? '') as String,
      rate: asDouble(map['Rate']),
      litter: litter.abs(),
      credit: asDouble(map['Credit']),
      debit: asDouble(map['Debit']),
      note: note,
      isMinus: isMinus,
    );
  }
}

class BankTransaction {
  final int? id;
  final String transactionDate;
  final String transactionType;
  final int? customerId;
  final String customerName;
  final int? dealerId;
  final String dealerName;
  final double amount;
  final String note;
  final String bankName;

  const BankTransaction({
    this.id,
    required this.transactionDate,
    required this.transactionType,
    this.customerId,
    this.customerName = '',
    this.dealerId,
    this.dealerName = '',
    required this.amount,
    required this.note,
    required this.bankName,
  });

  Map<String, Object?> toMap() => {
        'Id': id,
        'TransactionDate': transactionDate,
        'TransactionType': transactionType,
        'CustomerId': customerId,
        'DealerId': dealerId,
        'Amount': amount,
        'Note': note,
        'BankName': bankName,
      };

  factory BankTransaction.fromMap(Map<String, Object?> map) => BankTransaction(
        id: asInt(map['Id'] ?? map['id']),
        transactionDate: (map['TransactionDate'] ?? '') as String,
        transactionType: (map['TransactionType'] ?? 'In') as String,
        customerId: asInt(map['CustomerId']),
        customerName: (map['customer_name'] ?? '') as String,
        dealerId: asInt(map['DealerId']),
        dealerName: (map['dealer_name'] ?? '') as String,
        amount: asDouble(map['Amount']),
        note: (map['Note'] ?? '') as String,
        bankName: (map['BankName'] ?? '') as String,
      );
}

class DashboardStats {
  final CustomerLedgerSummary customer;
  final DealerLedgerSummary dealer;
  final double saleLitter;
  final double purchaseLitter;
  final double saleAmount;
  final double purchaseAmount;

  const DashboardStats({
    required this.customer,
    required this.dealer,
    required this.saleLitter,
    required this.purchaseLitter,
    required this.saleAmount,
    required this.purchaseAmount,
  });
}

class DealerGroupReportRow {
  final int dealerId;
  final String dealerName;
  final double ddAmount;
  final double dAmount;
  final double balance;
  final String? stockDate;
  final String vehicle;
  final double litter;
  final double rate;
  final double amount;
  final String note;

  const DealerGroupReportRow({
    required this.dealerId,
    required this.dealerName,
    required this.ddAmount,
    required this.dAmount,
    required this.balance,
    this.stockDate,
    required this.vehicle,
    required this.litter,
    required this.rate,
    required this.amount,
    required this.note,
  });

  factory DealerGroupReportRow.fromMap(Map<String, Object?> map) => DealerGroupReportRow(
        dealerId: asInt(map['dealer_id']) ?? 0,
        dealerName: (map['dealer_name'] ?? '') as String,
        ddAmount: asDouble(map['dd_amount']),
        dAmount: asDouble(map['d_amount']),
        balance: asDouble(map['balance']),
        stockDate: map['stock_date']?.toString(),
        vehicle: (map['vehicle'] ?? '') as String,
        litter: asDouble(map['litter']),
        rate: asDouble(map['rate']),
        amount: asDouble(map['amount']),
        note: (map['note'] ?? '') as String,
      );
}

/// Owner read-only ledger line (customer / dealer).
class OwnerLedgerLine {
  final String partyName;
  final String date;
  final String vehicle;
  final String note;
  final double litter;
  final double rate;
  final double amount;
  final double credit;
  final double runningBalance;

  const OwnerLedgerLine({
    required this.partyName,
    required this.date,
    required this.vehicle,
    required this.note,
    required this.litter,
    required this.rate,
    required this.amount,
    required this.credit,
    required this.runningBalance,
  });
}

/// Bul Mal party (local-only). Multiple owners.
class BulMalOwner {
  final int? id;
  final String name;
  final String date;

  const BulMalOwner({this.id, required this.name, required this.date});

  Map<String, Object?> toMap() => {
        'id': id,
        'Name': name,
        'Date': date,
      };

  factory BulMalOwner.fromMap(Map<String, Object?> map) => BulMalOwner(
        id: asInt(map['id']),
        name: (map['Name'] ?? '') as String,
        date: (map['Date'] ?? '') as String,
      );
}

/// Bul Mal In / Out entry (local-only).
class BulMalEntry {
  final int? id;
  final int ownerId;
  final String ownerName;
  final String date;
  final String type; // In | Out
  final double amount;
  final String note;

  const BulMalEntry({
    this.id,
    required this.ownerId,
    required this.ownerName,
    required this.date,
    required this.type,
    required this.amount,
    required this.note,
  });

  bool get isOut => type.toLowerCase() == 'out';

  Map<String, Object?> toMap() => {
        'id': id,
        'OwnerId': ownerId,
        'Date': date,
        'Type': type,
        'Amount': amount.abs(),
        'Note': note,
      };

  factory BulMalEntry.fromMap(Map<String, Object?> map) => BulMalEntry(
        id: asInt(map['id']),
        ownerId: asInt(map['OwnerId']) ?? 0,
        ownerName: (map['owner_name'] ?? map['Name'] ?? '') as String,
        date: (map['Date'] ?? '') as String,
        type: (map['Type'] ?? 'In') as String,
        amount: asDouble(map['Amount']),
        note: (map['Note'] ?? '') as String,
      );
}

class BulMalSummary {
  final double totalIn;
  final double totalOut;
  final double balance;

  const BulMalSummary({
    required this.totalIn,
    required this.totalOut,
    required this.balance,
  });
}

const pakistaniBanks = <String>[
  'HBL',
  'UBL',
  'MCB',
  'Allied Bank',
  'Bank Alfalah',
  'Meezan Bank',
  'Askari Bank',
  'Faysal Bank',
  'Habib Metro',
  'Standard Chartered',
  'JazzCash',
  'EasyPaisa',
  'NayaPay',
  'SadaPay',
];
