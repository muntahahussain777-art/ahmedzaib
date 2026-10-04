import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../data/app_database.dart';
import '../models/models.dart';
import '../services/report_totals.dart';
import '../theme/app_theme.dart';
import '../utils/form_utils.dart';
import '../widgets/vip_balance_search.dart';
import '../widgets/vip_widgets.dart';

Widget _card({required Widget child, VoidCallback? onTap, VoidCallback? onLongPress}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.22)),
          color: AppColors.panel.withValues(alpha: 0.9),
        ),
        child: child,
      ),
    ),
  );
}

// ===================== STOCK DIESEL =====================

class StockListScreen extends StatefulWidget {
  const StockListScreen({super.key});
  @override
  State<StockListScreen> createState() => _StockListScreenState();
}

class _StockListScreenState extends State<StockListScreen> {
  final _search = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();
  List<StockDieselEntry> _items = [];
  StockSummaryTotals? _summary;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _from.text = today;
    _to.text = today;
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await AppDatabase.instance.searchStockReport(
      query: _search.text,
      from: _from.text.trim().isEmpty ? null : _from.text.trim(),
      to: _to.text.trim().isEmpty ? null : _to.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _items = rows;
      _summary = StockSummaryTotals.fromRows(rows);
      _loading = false;
    });
  }

  Future<void> _open({StockDieselEntry? item}) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => StockFormScreen(entry: item)));
    if (ok == true) _load();
  }

  Widget _topSummary(StockSummaryTotals t) {
    String lit(double v) => v.toStringAsFixed(2);
    String rs(double v) => v.toStringAsFixed(0);
    String avg(double v) => v.toStringAsFixed(2);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
        gradient: LinearGradient(
          colors: [AppColors.panel.withValues(alpha: 0.98), AppColors.navy.withValues(alpha: 0.9)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Stock Totals + Avg', style: GoogleFonts.manrope(color: AppColors.gold, fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 8),
          Text('ADD  Litter ${lit(t.addLitter)}  |  Amt ${rs(t.addAmount)}  |  Avg ${avg(t.addAvgRate)}',
              style: const TextStyle(color: AppColors.success, fontSize: 12)),
          const SizedBox(height: 4),
          Text('MINUS  Litter ${lit(t.minusLitter)}  |  Amt ${rs(t.minusAmount)}  |  Avg ${avg(t.minusAvgRate)}',
              style: const TextStyle(color: AppColors.danger, fontSize: 12)),
          const SizedBox(height: 4),
          Text('Baqaya Litter: ${lit(t.baqayaLitter)} L  |  Net Amt: ${rs(t.netAmount)}',
              style: const TextStyle(color: AppColors.cream, fontSize: 12)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return VipScaffold(
      title: 'Stock',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.inventory_2_outlined),
        label: const Text('Add Stock'),
      ),
      child: Column(
        children: [
          if (_summary != null) _topSummary(_summary!),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                TextField(
                  controller: _search,
                  onChanged: (_) => _load(),
                  decoration: const InputDecoration(hintText: 'Exact dealer / vehicle', prefixIcon: Icon(Icons.search, color: AppColors.gold)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: VipField(
                        label: 'From',
                        controller: _from,
                        readOnly: true,
                        onTap: () async {
                          await pickVipDate(context, _from);
                          _load();
                        },
                        suffix: const Icon(Icons.calendar_month, color: AppColors.gold),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: VipField(
                        label: 'To',
                        controller: _to,
                        readOnly: true,
                        onTap: () async {
                          await pickVipDate(context, _to);
                          _load();
                        },
                        suffix: const Icon(Icons.calendar_month, color: AppColors.gold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
                : _items.isEmpty
                    ? const EmptyState(message: 'Stock entries nahi.\nStock diesel add/minus yahan.')
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final e = _items[i];
                          return _card(
                            onTap: () => _open(item: e),
                            onLongPress: () async {
                              if (!await confirmDelete(context, 'Stock entry delete?')) return;
                              await AppDatabase.instance.deleteStock(e.id!);
                              _load();
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(e.dealerName, style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16)),
                                    ),
                                    Text(
                                      e.isMinus ? 'MINUS' : 'ADD',
                                      style: TextStyle(
                                        color: e.isMinus ? AppColors.danger : AppColors.success,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '${e.date}  •  ${e.litter.toStringAsFixed(2)} L  •  Rate ${e.rate.toStringAsFixed(2)}',
                                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class StockFormScreen extends StatefulWidget {
  const StockFormScreen({super.key, this.entry});
  final StockDieselEntry? entry;
  @override
  State<StockFormScreen> createState() => _StockFormScreenState();
}

class _StockFormScreenState extends State<StockFormScreen> {
  final _date = TextEditingController();
  final _vehicle = TextEditingController();
  final _rate = TextEditingController();
  final _litter = TextEditingController();
  final _credit = TextEditingController();
  final _debit = TextEditingController();
  final _note = TextEditingController();
  List<Dealer> _dealers = [];
  Dealer? _selected;
  StockSummaryTotals? _litterSummary;
  bool _isMinus = false;
  bool _loading = true;
  bool _saving = false;
  bool _savedInSession = false;
  bool get _edit => widget.entry?.id != null;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<StockSummaryTotals> _loadLitterSummary(Dealer? d) async {
    if (d?.id == null) {
      return const StockSummaryTotals(
        addLitter: 0,
        minusLitter: 0,
        baqayaLitter: 0,
        addAmount: 0,
        minusAmount: 0,
        netAmount: 0,
      );
    }
    // WinForms jaisa: saari StockDiesel rows (date filter nahi) → Baqaya litter
    final rows = await AppDatabase.instance.searchStockReport(name: d!.name);
    return StockSummaryTotals.fromRows(rows);
  }

  Future<void> _bootstrap() async {
    final stockDealer = await AppDatabase.instance.ensureStockDealer();
    final dealers = await AppDatabase.instance.getDealers();
    final e = widget.entry;
    _date.text = e?.date ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
    _vehicle.text = e?.vehicle ?? '';
    _rate.text = e == null ? '' : fmtNum(e.rate);
    _litter.text = e == null ? '' : fmtNum(e.litter);
    _credit.text = e == null ? '' : fmtNum(e.credit);
    _debit.text = e == null ? '' : fmtNum(e.debit);
    _note.text = e?.note ?? '';
    _isMinus = e?.isMinus ?? false;
    Dealer? selected;
    if (e != null) {
      for (final d in dealers) {
        if (d.id == e.dealerId) {
          selected = d;
          break;
        }
      }
    } else {
      selected = stockDealer;
      for (final d in dealers) {
        if (d.id == stockDealer.id) {
          selected = d;
          break;
        }
      }
    }
    final litterSummary = await _loadLitterSummary(selected);
    if (!mounted) return;
    setState(() {
      _dealers = dealers;
      _selected = selected;
      _litterSummary = litterSummary;
      _loading = false;
    });
  }

  Future<void> _onDealerSelected(Dealer? d) async {
    setState(() {
      _selected = d;
      _litterSummary = null;
    });
    final litterSummary = await _loadLitterSummary(d);
    if (!mounted) return;
    setState(() => _litterSummary = litterSummary);
  }

  @override
  void dispose() {
    _date.dispose();
    _vehicle.dispose();
    _rate.dispose();
    _litter.dispose();
    _credit.dispose();
    _debit.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_selected?.id == null || parseNum(_litter) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dealer + litter zaroori hai')));
      return;
    }
    await runVipSave(
      context: context,
      setSaving: (v) { if (mounted) setState(() => _saving = v); },
      popOnSuccess: _edit,
      action: () async {
        final model = StockDieselEntry(
          id: widget.entry?.id,
          dealerId: _selected!.id!,
          dealerName: _selected!.name,
          date: _date.text.trim(),
          vehicle: _vehicle.text.trim(),
          rate: parseNum(_rate),
          litter: parseNum(_litter),
          credit: parseNum(_credit),
          debit: parseNum(_debit),
          note: _note.text.trim(),
          isMinus: _isMinus,
        );
        if (_edit) {
          await AppDatabase.instance.updateStock(model);
        } else {
          await AppDatabase.instance.insertStock(model);
        }
      },
    ).then((ok) async {
      if (!ok || _edit || !mounted) return;
      _savedInSession = true;
      _vehicle.clear();
      _litter.clear();
      _rate.clear();
      _credit.clear();
      _debit.clear();
      _note.clear();
      // Stock dealer + date same — litter baqaya refresh
      final litterSummary = await _loadLitterSummary(_selected);
      if (mounted) setState(() => _litterSummary = litterSummary);
    });
  }

  @override
  Widget build(BuildContext context) {
    return keepOpenPopScope(
      context: context,
      savedInSession: _savedInSession,
      isEdit: _edit,
      child: VipScaffold(
      title: _edit ? 'Edit Stock' : 'Stock',
      backResult: _edit || _savedInSession,
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (_litterSummary != null) VipBalanceBanner.stockLitter(_litterSummary!),
                SwitchListTile(
                  value: _isMinus,
                  activeThumbColor: AppColors.gold,
                  title: const Text('Minus / Sale stock', style: TextStyle(color: AppColors.cream)),
                  subtitle: const Text('Off = Add litter, On = Minus litter', style: TextStyle(color: AppColors.muted)),
                  onChanged: (v) => setState(() => _isMinus = v),
                ),
                VipSearchDropdown<Dealer>(
                  label: 'Dealer *',
                  items: _dealers,
                  value: _selected,
                  displayString: (d) => d.name,
                  onSelected: _onDealerSelected,
                ),
                VipField(label: 'Date', controller: _date, readOnly: true, onTap: () => pickVipDate(context, _date), suffix: const Icon(Icons.calendar_month, color: AppColors.gold)),
                VipField(label: 'Vehicle', controller: _vehicle),
                Row(children: [
                  Expanded(child: VipField(label: 'Litter *', controller: _litter, keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                  const SizedBox(width: 10),
                  Expanded(child: VipField(label: 'Rate', controller: _rate, keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                ]),
                Row(children: [
                  Expanded(child: VipField(label: 'Credit', controller: _credit, keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                  const SizedBox(width: 10),
                  Expanded(child: VipField(label: 'Debit', controller: _debit, keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                ]),
                VipField(label: 'Note', controller: _note, maxLines: 2),
                ElevatedButton(onPressed: _saving || _dealers.isEmpty ? null : _save, child: Text(_saving ? 'Saving...' : 'Save Stock')),
              ],
            ),
    ),
    );
  }
}

// ===================== BANK =====================

class BankListScreen extends StatefulWidget {
  const BankListScreen({super.key});
  @override
  State<BankListScreen> createState() => _BankListScreenState();
}

class _BankListScreenState extends State<BankListScreen> {
  final _search = TextEditingController();
  List<BankTransaction> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await AppDatabase.instance.getBanks(query: _search.text);
    if (!mounted) return;
    setState(() {
      _items = rows;
      _loading = false;
    });
  }

  Future<void> _open({BankTransaction? item}) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => BankFormScreen(entry: item)));
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return VipScaffold(
      title: 'Bank Account',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.account_balance_outlined),
        label: const Text('Add Bank Entry'),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => _load(),
              decoration: const InputDecoration(hintText: 'Search bank / customer / dealer', prefixIcon: Icon(Icons.search, color: AppColors.gold)),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
                : _items.isEmpty
                    ? const EmptyState(message: 'Bank entries nahi.\nIn/Out transaction yahan add karein.')
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final e = _items[i];
                          final who = [
                            if (e.customerName.isNotEmpty) e.customerName,
                            if (e.dealerName.isNotEmpty) e.dealerName,
                          ].join(' / ');
                          return _card(
                            onTap: () => _open(item: e),
                            onLongPress: () async {
                              if (!await confirmDelete(context, 'Bank entry delete?')) return;
                              await AppDatabase.instance.deleteBank(e.id!);
                              _load();
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(e.bankName, style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16)),
                                    ),
                                    Text(
                                      '${e.transactionType} ${e.amount.abs().toStringAsFixed(0)}',
                                      style: TextStyle(
                                        color: e.amount >= 0 ? AppColors.success : AppColors.danger,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                Text('${e.transactionDate}${who.isEmpty ? '' : '  •  $who'}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class BankFormScreen extends StatefulWidget {
  const BankFormScreen({super.key, this.entry});
  final BankTransaction? entry;
  @override
  State<BankFormScreen> createState() => _BankFormScreenState();
}

class _BankFormScreenState extends State<BankFormScreen> {
  final _date = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  List<Customer> _customers = [];
  List<Dealer> _dealers = [];
  Customer? _customer;
  Dealer? _dealer;
  CustomerLedgerSummary? _customerSummary;
  DealerLedgerSummary? _dealerSummary;
  String _type = 'In';
  String _bank = pakistaniBanks.first;
  bool _loading = true;
  bool _saving = false;
  bool _savedInSession = false;
  bool get _edit => widget.entry?.id != null;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final customers = await AppDatabase.instance.getCustomers();
    final dealers = await AppDatabase.instance.getDealers();
    final e = widget.entry;
    _date.text = e?.transactionDate ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
    _amount.text = e == null ? '' : fmtNum(e.amount.abs());
    _note.text = e?.note ?? '';
    _type = e?.transactionType ?? 'In';
    _bank = e?.bankName.isNotEmpty == true ? e!.bankName : pakistaniBanks.first;
    if (!pakistaniBanks.contains(_bank)) {
      // keep custom bank name from entry
    }
    Customer? customer;
    Dealer? dealer;
    if (e?.customerId != null) {
      for (final c in customers) {
        if (c.id == e!.customerId) {
          customer = c;
          break;
        }
      }
    }
    if (e?.dealerId != null) {
      for (final d in dealers) {
        if (d.id == e!.dealerId) {
          dealer = d;
          break;
        }
      }
    }
    CustomerLedgerSummary? customerSummary;
    DealerLedgerSummary? dealerSummary;
    if (customer?.id != null) {
      customerSummary = await AppDatabase.instance.getCustomerLedgerSummary(customer!.id!);
    }
    if (dealer?.id != null) {
      dealerSummary = await AppDatabase.instance.getDealerLedgerSummary(dealer!.id!);
    }
    if (!mounted) return;
    setState(() {
      _customers = customers;
      _dealers = dealers;
      _customer = customer;
      _dealer = dealer;
      _customerSummary = customerSummary;
      _dealerSummary = dealerSummary;
      _loading = false;
    });
  }

  Future<void> _onCustomerSelected(Customer? c) async {
    setState(() {
      _customer = c;
      _customerSummary = null;
    });
    if (c?.id == null) return;
    final summary = await AppDatabase.instance.getCustomerLedgerSummary(c!.id!);
    if (!mounted) return;
    setState(() => _customerSummary = summary);
  }

  Future<void> _onDealerSelected(Dealer? d) async {
    setState(() {
      _dealer = d;
      _dealerSummary = null;
    });
    if (d?.id == null) return;
    final summary = await AppDatabase.instance.getDealerLedgerSummary(d!.id!);
    if (!mounted) return;
    setState(() => _dealerSummary = summary);
  }

  @override
  void dispose() {
    _date.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final abs = parseNum(_amount);
    if (abs <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Amount likhein')));
      return;
    }
    final signed = _type == 'Out' ? -abs : abs;
    if (_type == 'Out') {
      final bal = await AppDatabase.instance.getBankBalance(_bank);
      if (!mounted) return;
      final projected = (_edit ? bal - widget.entry!.amount : bal) + signed;
      if (projected < 0) {
        final go = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppColors.panel,
            title: const Text('Balance low', style: TextStyle(color: AppColors.gold)),
            content: Text('Bank balance negative ho sakta hai (${projected.toStringAsFixed(0)}). Continue?', style: const TextStyle(color: AppColors.cream)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
            ],
          ),
        );
        if (go != true) return;
      }
    }

    await runVipSave(
      context: context,
      setSaving: (v) { if (mounted) setState(() => _saving = v); },
      popOnSuccess: _edit,
      action: () async {
        final model = BankTransaction(
          id: widget.entry?.id,
          transactionDate: _date.text.trim(),
          transactionType: _type,
          customerId: _customer?.id,
          customerName: _customer?.name ?? '',
          dealerId: _dealer?.id,
          dealerName: _dealer?.name ?? '',
          amount: signed,
          note: _note.text.trim(),
          bankName: _bank,
        );
        if (_edit) {
          await AppDatabase.instance.updateBank(model);
        } else {
          await AppDatabase.instance.insertBank(model);
        }
      },
    ).then((ok) {
      if (!ok || _edit || !mounted) return;
      _savedInSession = true;
      _amount.clear();
      _note.clear();
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final banks = {...pakistaniBanks, if (_bank.isNotEmpty) _bank}.toList();
    return keepOpenPopScope(
      context: context,
      savedInSession: _savedInSession,
      isEdit: _edit,
      child: VipScaffold(
      title: _edit ? 'Edit Bank Entry' : 'Bank Account',
      backResult: _edit || _savedInSession,
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (_customerSummary != null) VipBalanceBanner.customer(_customerSummary!),
                if (_dealerSummary != null) VipBalanceBanner.dealer(_dealerSummary!),
                DropdownButtonFormField<String>(
                  key: ValueKey(_bank),
                  initialValue: banks.contains(_bank) ? _bank : banks.first,
                  dropdownColor: AppColors.panel,
                  decoration: const InputDecoration(labelText: 'Bank / Wallet *'),
                  items: banks.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                  onChanged: (v) => setState(() => _bank = v ?? _bank),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey(_type),
                  initialValue: _type,
                  dropdownColor: AppColors.panel,
                  decoration: const InputDecoration(labelText: 'Type *'),
                  items: const [
                    DropdownMenuItem(value: 'In', child: Text('In')),
                    DropdownMenuItem(value: 'Out', child: Text('Out')),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? 'In'),
                ),
                const SizedBox(height: 12),
                VipField(label: 'Date', controller: _date, readOnly: true, onTap: () => pickVipDate(context, _date), suffix: const Icon(Icons.calendar_month, color: AppColors.gold)),
                VipField(label: 'Amount *', controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                VipSearchDropdown<Customer>(
                  label: 'Customer (optional)',
                  items: _customers,
                  value: _customer,
                  displayString: (c) => c.name,
                  onSelected: _onCustomerSelected,
                  allowClear: true,
                  hint: 'Type name to search...',
                ),
                VipSearchDropdown<Dealer>(
                  label: 'Dealer (optional)',
                  items: _dealers,
                  value: _dealer,
                  displayString: (d) => d.name,
                  onSelected: _onDealerSelected,
                  allowClear: true,
                  hint: 'Type name to search...',
                ),
                VipField(label: 'Note', controller: _note, maxLines: 2),
                ElevatedButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving...' : 'Save Bank Entry')),
              ],
            ),
    ),
    );
  }
}
