import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../data/app_database.dart';
import '../models/models.dart';
import '../services/report_totals.dart';
import '../theme/app_theme.dart';
import '../utils/form_utils.dart';
import '../widgets/sync_aware_reload.dart';
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

// ===================== CREDIT CUSTOMER =====================

class CreditCustomerListScreen extends StatefulWidget {
  const CreditCustomerListScreen({super.key});
  @override
  State<CreditCustomerListScreen> createState() => _CreditCustomerListScreenState();
}

class _CreditCustomerListScreenState extends State<CreditCustomerListScreen> with SyncAwareReload {
  final _search = TextEditingController();
  List<CreditCustomerEntry> _items = [];
  List<String> _nameSuggestions = [];
  CustomerLedgerSummary? _totals;
  String? _matchedName;
  bool _loading = true;
  bool _initial = true;

  @override
  void initState() {
    super.initState();
    _load(showSpinner: true);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Future<void> reloadAfterSync() => _load(showSpinner: false);

  Future<void> _load({bool showSpinner = false}) async {
    final gen = bumpLoadGeneration();
    if (showSpinner || _initial) {
      if (mounted) setState(() => _loading = true);
    }
    final rows = await AppDatabase.instance.getCredits(query: _search.text);
    final matched = await AppDatabase.instance.findCustomerByExactName(_search.text);
    final byName = matched?.id == null ? null : await AppDatabase.instance.getCustomerLedgerSummary(matched!.id!);
    final totals = byName ?? await AppDatabase.instance.getGlobalCustomerLedger();
    final customers = await AppDatabase.instance.getCustomers();
    if (!mounted || !isLoadCurrent(gen)) return;
    setState(() {
      _items = rows;
      _totals = totals;
      _matchedName = matched?.name;
      _nameSuggestions = customers.map((c) => c.name).where((n) => n.trim().isNotEmpty).toList();
      _loading = false;
      _initial = false;
    });
  }

  Future<void> _open({CreditCustomerEntry? item}) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => CreditCustomerFormScreen(entry: item)));
    if (ok == true) _load(showSpinner: true);
  }

  @override
  Widget build(BuildContext context) {
    return VipScaffold(
      title: 'Credit Customer',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.payments_outlined),
        label: const Text('Add Credit'),
      ),
      child: Column(
        children: [
          if (_totals != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: VipBalanceBanner.customer(
                _totals!,
                title: _matchedName != null ? 'Customer: $_matchedName' : 'All Customers',
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: VipSuggestSearchField(
              controller: _search,
              suggestions: _nameSuggestions,
              hint: 'Customer name type / suggest',
              onQueryChanged: (_) => _load(showSpinner: false),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
                : _items.isEmpty
                    ? const EmptyState(message: 'Credit entries nahi hain.\nCustomer select karke wasooli add karein.')
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final e = _items[i];
                          return _card(
                            onTap: () => _open(item: e),
                            onLongPress: () async {
                              if (!await confirmDelete(context, '${e.customerName} credit delete?')) return;
                              await AppDatabase.instance.deleteCredit(e.id!);
                              _load(showSpinner: true);
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.customerName, style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16)),
                                Text('${e.date}  •  Credit ${e.credit.toStringAsFixed(0)}  •  Bal ${e.balance.toStringAsFixed(0)}',
                                    style: const TextStyle(color: AppColors.muted, fontSize: 12)),
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

class CreditCustomerFormScreen extends StatefulWidget {
  const CreditCustomerFormScreen({super.key, this.entry});
  final CreditCustomerEntry? entry;
  @override
  State<CreditCustomerFormScreen> createState() => _CreditCustomerFormScreenState();
}

class _CreditCustomerFormScreenState extends State<CreditCustomerFormScreen> {
  final _date = TextEditingController();
  final _receipt = TextEditingController();
  final _credit = TextEditingController();
  final _balance = TextEditingController();
  final _note = TextEditingController();
  List<Customer> _customers = [];
  Customer? _selected;
  CustomerLedgerSummary? _summary;
  bool _loading = true;
  bool _saving = false;
  bool _savedInSession = false;
  bool get _edit => widget.entry?.id != null;

  double get _remaining => _summary?.balance ?? 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final customers = await AppDatabase.instance.getCustomers();
    final e = widget.entry;
    _date.text = e?.date ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
    _receipt.text = e?.receiptNo ?? '';
    _credit.text = e == null ? '' : fmtNum(e.credit);
    _balance.text = e == null ? '' : fmtNum(e.balance);
    _note.text = e?.note ?? '';
    Customer? selected;
    if (e != null) {
      for (final c in customers) {
        if (c.id == e.customerId) {
          selected = c;
          break;
        }
      }
    }
    CustomerLedgerSummary? summary;
    if (selected?.id != null) {
      summary = await AppDatabase.instance.getCustomerLedgerSummary(selected!.id!);
    }
    if (!mounted) return;
    setState(() {
      _customers = customers;
      _selected = selected;
      _summary = summary;
      _loading = false;
    });
    _recalcBalance();
  }

  Future<void> _onCustomerSelected(Customer? c) async {
    setState(() {
      _selected = c;
      _summary = null;
    });
    if (c?.id == null) {
      _recalcBalance();
      return;
    }
    final summary = await AppDatabase.instance.getCustomerLedgerSummary(c!.id!);
    if (!mounted) return;
    setState(() => _summary = summary);
    _recalcBalance();
  }

  void _recalcBalance() {
    final credit = parseNum(_credit);
    _balance.text = (_remaining - credit).toStringAsFixed(2);
    setState(() {});
  }

  @override
  void dispose() {
    _date.dispose();
    _receipt.dispose();
    _credit.dispose();
    _balance.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_selected?.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Customer select karein')));
      return;
    }
    if (parseNum(_credit) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Credit amount likhein')));
      return;
    }
    await runVipSave(
      context: context,
      setSaving: (v) { if (mounted) setState(() => _saving = v); },
      popOnSuccess: _edit,
      action: () async {
        final model = CreditCustomerEntry(
          id: widget.entry?.id,
          customerId: _selected!.id!,
          customerName: _selected!.name,
          date: _date.text.trim(),
          receiptNo: _receipt.text.trim(),
          credit: parseNum(_credit),
          balance: parseNum(_balance),
          note: _note.text.trim(),
        );
        if (_edit) {
          await AppDatabase.instance.updateCredit(model);
        } else {
          await AppDatabase.instance.insertCredit(model);
        }
      },
    ).then((ok) async {
      if (!ok || _edit || !mounted) return;
      _savedInSession = true;
      _receipt.clear();
      _credit.clear();
      _note.clear();
      if (_selected?.id != null) {
        final summary = await AppDatabase.instance.getCustomerLedgerSummary(_selected!.id!);
        if (mounted) {
          setState(() => _summary = summary);
          _recalcBalance();
        }
      } else if (mounted) {
        _recalcBalance();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return keepOpenPopScope(
      context: context,
      savedInSession: _savedInSession,
      isEdit: _edit,
      child: VipScaffold(
      title: _edit ? 'Edit Credit' : 'Credit Customer',
      backResult: _edit || _savedInSession,
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (_summary != null) VipBalanceBanner.customer(_summary!),
                VipSearchDropdown<Customer>(
                  label: 'Customer *',
                  items: _customers,
                  value: _selected,
                  displayString: (c) => c.name,
                  onSelected: _onCustomerSelected,
                ),
                VipField(label: 'Date', controller: _date, readOnly: true, onTap: () => pickVipDate(context, _date), suffix: const Icon(Icons.calendar_month, color: AppColors.gold)),
                VipField(label: 'Receipt No', controller: _receipt),
                VipField(label: 'Credit Amount *', controller: _credit, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => _recalcBalance()),
                VipField(label: 'Balance After', controller: _balance, readOnly: true),
                VipField(label: 'Note', controller: _note, maxLines: 2),
                ElevatedButton(onPressed: _saving || _customers.isEmpty ? null : _save, child: Text(_saving ? 'Saving...' : 'Save Credit')),
              ],
            ),
    ),
    );
  }
}

// ===================== DEALER PAYOUT =====================

class DealerPayoutListScreen extends StatefulWidget {
  const DealerPayoutListScreen({super.key});
  @override
  State<DealerPayoutListScreen> createState() => _DealerPayoutListScreenState();
}

class _DealerPayoutListScreenState extends State<DealerPayoutListScreen> with SyncAwareReload {
  final _search = TextEditingController();
  List<DealerPayout> _items = [];
  List<String> _nameSuggestions = [];
  bool _loading = true;
  bool _initial = true;

  @override
  void initState() {
    super.initState();
    _load(showSpinner: true);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Future<void> reloadAfterSync() => _load(showSpinner: false);

  Future<void> _load({bool showSpinner = false}) async {
    final gen = bumpLoadGeneration();
    if (showSpinner || _initial) {
      if (mounted) setState(() => _loading = true);
    }
    final rows = await AppDatabase.instance.getPayouts(query: _search.text);
    final dealers = await AppDatabase.instance.getDealers();
    if (!mounted || !isLoadCurrent(gen)) return;
    setState(() {
      _items = rows;
      _nameSuggestions = dealers.map((d) => d.name).where((n) => n.trim().isNotEmpty).toList();
      _loading = false;
      _initial = false;
    });
  }

  Future<void> _open({DealerPayout? item}) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => DealerPayoutFormScreen(entry: item)));
    if (ok == true) _load(showSpinner: true);
  }

  @override
  Widget build(BuildContext context) {
    return VipScaffold(
      title: 'Dealer Payout',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.outbox_outlined),
        label: const Text('Add Payout'),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: VipSuggestSearchField(
              controller: _search,
              suggestions: _nameSuggestions,
              hint: 'Dealer name type / suggest',
              onQueryChanged: (_) => _load(showSpinner: false),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
                : _items.isEmpty
                    ? const EmptyState(message: 'Payout entries nahi.\nDealer ko payment yahan add karein (DAmount +=).')
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final e = _items[i];
                          return _card(
                            onTap: () => _open(item: e),
                            onLongPress: () async {
                              if (!await confirmDelete(context, '${e.dealerName} payout delete?')) return;
                              await AppDatabase.instance.deletePayout(e);
                              _load(showSpinner: true);
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.dealerName, style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16)),
                                Text('${e.date}  •  Paid ${e.amountGiven.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
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

class DealerPayoutFormScreen extends StatefulWidget {
  const DealerPayoutFormScreen({super.key, this.entry});
  final DealerPayout? entry;
  @override
  State<DealerPayoutFormScreen> createState() => _DealerPayoutFormScreenState();
}

class _DealerPayoutFormScreenState extends State<DealerPayoutFormScreen> {
  final _date = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  List<Dealer> _dealers = [];
  Dealer? _selected;
  DealerLedgerSummary? _summary;
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
    final dealers = await AppDatabase.instance.getDealers();
    final e = widget.entry;
    _date.text = e?.date ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
    _amount.text = e == null ? '' : fmtNum(e.amountGiven);
    _note.text = e?.note ?? '';
    Dealer? selected;
    if (e != null) {
      for (final d in dealers) {
        if (d.id == e.dealerId) {
          selected = d;
          break;
        }
      }
    }
    DealerLedgerSummary? summary;
    if (selected?.id != null) {
      summary = await AppDatabase.instance.getDealerLedgerSummary(selected!.id!);
    }
    if (!mounted) return;
    setState(() {
      _dealers = dealers;
      _selected = selected;
      _summary = summary;
      _loading = false;
    });
  }

  Future<void> _onDealerSelected(Dealer? d) async {
    setState(() {
      _selected = d;
      _summary = null;
    });
    if (d?.id == null) return;
    final summary = await AppDatabase.instance.getDealerLedgerSummary(d!.id!);
    if (!mounted) return;
    setState(() => _summary = summary);
  }

  @override
  void dispose() {
    _date.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_selected?.id == null || parseNum(_amount) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dealer + amount zaroori hai')));
      return;
    }
    await runVipSave(
      context: context,
      setSaving: (v) { if (mounted) setState(() => _saving = v); },
      popOnSuccess: _edit,
      action: () async {
        final model = DealerPayout(
          id: widget.entry?.id,
          dealerId: _selected!.id!,
          dealerName: _selected!.name,
          amountGiven: parseNum(_amount),
          date: _date.text.trim(),
          note: _note.text.trim(),
        );
        if (_edit) {
          await AppDatabase.instance.updatePayout(widget.entry!, model);
        } else {
          await AppDatabase.instance.insertPayout(model);
        }
      },
    ).then((ok) async {
      if (!ok || _edit || !mounted) return;
      _savedInSession = true;
      _amount.clear();
      _note.clear();
      if (_selected?.id != null) {
        final summary = await AppDatabase.instance.getDealerLedgerSummary(_selected!.id!);
        if (mounted) setState(() => _summary = summary);
      } else if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return keepOpenPopScope(
      context: context,
      savedInSession: _savedInSession,
      isEdit: _edit,
      child: VipScaffold(
      title: _edit ? 'Edit Payout' : 'Dealer Payout',
      backResult: _edit || _savedInSession,
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (_summary != null) VipBalanceBanner.dealer(_summary!),
                VipSearchDropdown<Dealer>(
                  label: 'Dealer *',
                  items: _dealers,
                  value: _selected,
                  displayString: (d) => d.name,
                  onSelected: _onDealerSelected,
                ),
                VipField(label: 'Date', controller: _date, readOnly: true, onTap: () => pickVipDate(context, _date), suffix: const Icon(Icons.calendar_month, color: AppColors.gold)),
                VipField(label: 'Amount Given *', controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                VipField(label: 'Note', controller: _note, maxLines: 2),
                ElevatedButton(onPressed: _saving || _dealers.isEmpty ? null : _save, child: Text(_saving ? 'Saving...' : 'Save Payout')),
              ],
            ),
    ),
    );
  }
}

// ===================== DEALER AMOUNT (PURCHASE) =====================

class DealerAmountListScreen extends StatefulWidget {
  const DealerAmountListScreen({super.key});
  @override
  State<DealerAmountListScreen> createState() => _DealerAmountListScreenState();
}

class _DealerAmountListScreenState extends State<DealerAmountListScreen> with SyncAwareReload {
  final _search = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();
  List<DealerAmountEntry> _items = [];
  List<String> _nameSuggestions = [];
  DealerLedgerSummary? _dealerTotals;
  String? _matchedDealer;
  LitterRateAvgSummary? _avg;
  bool _loading = true;
  bool _initial = true;

  @override
  void initState() {
    super.initState();
    _load(showSpinner: true);
  }

  @override
  void dispose() {
    _search.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  @override
  Future<void> reloadAfterSync() => _load(showSpinner: false);

  Future<void> _load({bool showSpinner = false}) async {
    final gen = bumpLoadGeneration();
    if (showSpinner || _initial) {
      if (mounted) setState(() => _loading = true);
    }
    final from = _from.text.trim();
    final to = _to.text.trim();
    final rows = await AppDatabase.instance.getDealerAmounts(
      query: _search.text,
      from: from.isEmpty ? null : from,
      to: to.isEmpty ? null : to,
    );
    final dealerMatched = await AppDatabase.instance.findDealerByExactName(_search.text);
    final dealerTotals = dealerMatched?.id == null
        ? null
        : await AppDatabase.instance.getDealerLedgerSummary(dealerMatched!.id!);
    final avg = LitterRateAvgSummary.fromDealerAmount(rows);
    final dealers = await AppDatabase.instance.getDealers();
    if (!mounted || !isLoadCurrent(gen)) return;
    setState(() {
      _items = rows;
      _dealerTotals = dealerTotals;
      _matchedDealer = dealerMatched?.name;
      _avg = avg;
      _nameSuggestions = dealers.map((d) => d.name).where((n) => n.trim().isNotEmpty).toList();
      _loading = false;
      _initial = false;
    });
  }

  Future<void> _open({DealerAmountEntry? item}) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => DealerAmountFormScreen(entry: item)));
    if (ok == true) _load(showSpinner: true);
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim();
    final showAvg = _from.text.trim().isNotEmpty || _to.text.trim().isNotEmpty || q.isNotEmpty;
    return VipScaffold(
      title: 'DealerAmount',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.local_shipping_outlined),
        label: const Text('Add Purchase'),
      ),
      child: Column(
        children: [
          if (_dealerTotals != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: VipBalanceBanner.dealer(_dealerTotals!, title: 'Dealer: $_matchedDealer'),
            ),
          if (_avg != null && showAvg)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: VipBalanceBanner.litterAvg(
                title: 'Total Litter / Amount / Avg',
                litterSum: _avg!.litterSum,
                amountSum: _avg!.amountSum,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                VipSuggestSearchField(
                  controller: _search,
                  suggestions: _nameSuggestions,
                  hint: 'Dealer name type / suggest',
                  onQueryChanged: (_) => _load(showSpinner: false),
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
                          _load(showSpinner: true);
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
                          _load(showSpinner: true);
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
                    ? const EmptyState(message: 'Dealer purchase nahi.\nDealer se diesel purchase (AddStock) yahan.')
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final e = _items[i];
                          return _card(
                            onTap: () => _open(item: e),
                            onLongPress: () async {
                              if (!await confirmDelete(context, '${e.dealerName} purchase delete?')) return;
                              await AppDatabase.instance.deleteDealerAmount(e);
                              _load(showSpinner: true);
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.dealerName, style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16)),
                                Text('${e.date}  •  ${e.addDiesel.toStringAsFixed(2)} L × ${e.rate.toStringAsFixed(2)} = ${e.amount.toStringAsFixed(0)}',
                                    style: const TextStyle(color: AppColors.muted, fontSize: 12)),
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

class DealerAmountFormScreen extends StatefulWidget {
  const DealerAmountFormScreen({super.key, this.entry});
  final DealerAmountEntry? entry;
  @override
  State<DealerAmountFormScreen> createState() => _DealerAmountFormScreenState();
}

class _DealerAmountFormScreenState extends State<DealerAmountFormScreen> {
  final _date = TextEditingController();
  final _vehicle = TextEditingController();
  final _rate = TextEditingController();
  final _litter = TextEditingController();
  final _note = TextEditingController();
  List<Dealer> _dealers = [];
  Dealer? _selected;
  DealerLedgerSummary? _summary;
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
    final dealers = await AppDatabase.instance.getDealers();
    final e = widget.entry;
    _date.text = e?.date ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
    _vehicle.text = e?.vehicle ?? '';
    _rate.text = e == null ? '' : fmtNum(e.rate);
    _litter.text = e == null ? '' : fmtNum(e.addDiesel);
    _note.text = e?.note ?? '';
    Dealer? selected;
    if (e != null) {
      for (final d in dealers) {
        if (d.id == e.dealerId) {
          selected = d;
          break;
        }
      }
    }
    DealerLedgerSummary? summary;
    if (selected?.id != null) {
      summary = await AppDatabase.instance.getDealerLedgerSummary(selected!.id!);
    }
    if (!mounted) return;
    setState(() {
      _dealers = dealers;
      _selected = selected;
      _summary = summary;
      _loading = false;
    });
  }

  Future<void> _onDealerSelected(Dealer? d) async {
    setState(() {
      _selected = d;
      _summary = null;
    });
    if (d?.id == null) return;
    final summary = await AppDatabase.instance.getDealerLedgerSummary(d!.id!);
    if (!mounted) return;
    setState(() => _summary = summary);
  }

  @override
  void dispose() {
    _date.dispose();
    _vehicle.dispose();
    _rate.dispose();
    _litter.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_selected?.id == null || parseNum(_litter) == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dealer + litter zaroori hai')));
      return;
    }
    await runVipSave(
      context: context,
      setSaving: (v) { if (mounted) setState(() => _saving = v); },
      popOnSuccess: _edit,
      action: () async {
        final model = DealerAmountEntry(
          id: widget.entry?.id,
          dealerId: _selected!.id!,
          dealerName: _selected!.name,
          date: _date.text.trim(),
          vehicle: _vehicle.text.trim(),
          rate: parseNum(_rate),
          addDiesel: parseNum(_litter),
          note: _note.text.trim(),
        );
        if (_edit) {
          await AppDatabase.instance.updateDealerAmount(widget.entry!, model);
        } else {
          await AppDatabase.instance.insertDealerAmount(model);
        }
      },
    ).then((ok) async {
      if (!ok || _edit || !mounted) return;
      _savedInSession = true;
      _vehicle.clear();
      _litter.clear();
      _rate.clear();
      _note.clear();
      if (_selected?.id != null) {
        final summary = await AppDatabase.instance.getDealerLedgerSummary(_selected!.id!);
        if (mounted) setState(() => _summary = summary);
      } else if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final amount = parseNum(_rate) * parseNum(_litter);
    return keepOpenPopScope(
      context: context,
      savedInSession: _savedInSession,
      isEdit: _edit,
      child: VipScaffold(
      title: _edit ? 'Edit DealerAmount' : 'DealerAmount',
      backResult: _edit || _savedInSession,
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (_summary != null) VipBalanceBanner.dealer(_summary!),
                Text('Amount → DDAmount += ${amount.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.goldSoft)),
                const SizedBox(height: 8),
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
                  Expanded(child: VipField(label: 'Litter *', controller: _litter, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}))),
                  const SizedBox(width: 10),
                  Expanded(child: VipField(label: 'Rate', controller: _rate, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}))),
                ]),
                VipField(label: 'Note', controller: _note, maxLines: 2),
                ElevatedButton(onPressed: _saving || _dealers.isEmpty ? null : _save, child: Text(_saving ? 'Saving...' : 'Save Purchase')),
              ],
            ),
    ),
    );
  }
}

// ===================== DIRECT DEALER AMOUNT =====================

class DirectDealerListScreen extends StatefulWidget {
  const DirectDealerListScreen({super.key});
  @override
  State<DirectDealerListScreen> createState() => _DirectDealerListScreenState();
}

class _DirectDealerListScreenState extends State<DirectDealerListScreen> with SyncAwareReload {
  final _search = TextEditingController();
  List<DirectDealerAmount> _items = [];
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

  @override
  Future<void> reloadAfterSync() => _load(showSpinner: false);

  Future<void> _load({bool showSpinner = true}) async {
    final gen = bumpLoadGeneration();
    if (showSpinner && mounted) setState(() => _loading = true);
    final rows = await AppDatabase.instance.getDirects(query: _search.text);
    if (!mounted || !isLoadCurrent(gen)) return;
    setState(() {
      _items = rows;
      _loading = false;
    });
  }

  Future<void> _open({DirectDealerAmount? item}) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => DirectDealerFormScreen(entry: item)));
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return VipScaffold(
      title: 'Direct Dealer Amount',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.add_card_outlined),
        label: const Text('Add Direct'),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => _load(),
              decoration: const InputDecoration(hintText: 'Search dealer', prefixIcon: Icon(Icons.search, color: AppColors.gold)),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
                : _items.isEmpty
                    ? const EmptyState(message: 'Direct dealer amount nahi.\nDDAmount pe direct amount yahan.')
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final e = _items[i];
                          return _card(
                            onTap: () => _open(item: e),
                            onLongPress: () async {
                              if (!await confirmDelete(context, '${e.dealerName} direct amount delete?')) return;
                              await AppDatabase.instance.deleteDirect(e);
                              _load();
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.dealerName, style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16)),
                                Text('${e.date}  •  Amount ${e.amountGiven.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
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

class DirectDealerFormScreen extends StatefulWidget {
  const DirectDealerFormScreen({super.key, this.entry});
  final DirectDealerAmount? entry;
  @override
  State<DirectDealerFormScreen> createState() => _DirectDealerFormScreenState();
}

class _DirectDealerFormScreenState extends State<DirectDealerFormScreen> {
  final _date = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  List<Dealer> _dealers = [];
  Dealer? _selected;
  DealerLedgerSummary? _summary;
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
    final dealers = await AppDatabase.instance.getDealers();
    final e = widget.entry;
    _date.text = e?.date ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
    _amount.text = e == null ? '' : fmtNum(e.amountGiven);
    _note.text = e?.note ?? '';
    Dealer? selected;
    if (e != null) {
      for (final d in dealers) {
        if (d.id == e.dealerId) {
          selected = d;
          break;
        }
      }
    }
    DealerLedgerSummary? summary;
    if (selected?.id != null) {
      summary = await AppDatabase.instance.getDealerLedgerSummary(selected!.id!);
    }
    if (!mounted) return;
    setState(() {
      _dealers = dealers;
      _selected = selected;
      _summary = summary;
      _loading = false;
    });
  }

  Future<void> _onDealerSelected(Dealer? d) async {
    setState(() {
      _selected = d;
      _summary = null;
    });
    if (d?.id == null) return;
    final summary = await AppDatabase.instance.getDealerLedgerSummary(d!.id!);
    if (!mounted) return;
    setState(() => _summary = summary);
  }

  @override
  void dispose() {
    _date.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_selected?.id == null || parseNum(_amount) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dealer + amount zaroori hai')));
      return;
    }
    await runVipSave(
      context: context,
      setSaving: (v) { if (mounted) setState(() => _saving = v); },
      popOnSuccess: _edit,
      action: () async {
        final model = DirectDealerAmount(
          id: widget.entry?.id,
          dealerId: _selected!.id!,
          dealerName: _selected!.name,
          amountGiven: parseNum(_amount),
          date: _date.text.trim(),
          note: _note.text.trim(),
        );
        if (_edit) {
          await AppDatabase.instance.updateDirect(widget.entry!, model);
        } else {
          await AppDatabase.instance.insertDirect(model);
        }
      },
    ).then((ok) async {
      if (!ok || _edit || !mounted) return;
      _savedInSession = true;
      _amount.clear();
      _note.clear();
      if (_selected?.id != null) {
        final summary = await AppDatabase.instance.getDealerLedgerSummary(_selected!.id!);
        if (mounted) setState(() => _summary = summary);
      } else if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return keepOpenPopScope(
      context: context,
      savedInSession: _savedInSession,
      isEdit: _edit,
      child: VipScaffold(
      title: _edit ? 'Edit Direct Amount' : 'Direct Dealer Amount',
      backResult: _edit || _savedInSession,
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (_summary != null) VipBalanceBanner.dealer(_summary!),
                const Text('Ye amount dealer DDAmount mein add hota hai.', style: TextStyle(color: AppColors.muted)),
                const SizedBox(height: 8),
                VipSearchDropdown<Dealer>(
                  label: 'Dealer *',
                  items: _dealers,
                  value: _selected,
                  displayString: (d) => d.name,
                  onSelected: _onDealerSelected,
                ),
                VipField(label: 'Date', controller: _date, readOnly: true, onTap: () => pickVipDate(context, _date), suffix: const Icon(Icons.calendar_month, color: AppColors.gold)),
                VipField(label: 'Amount *', controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                VipField(label: 'Note', controller: _note, maxLines: 2),
                ElevatedButton(onPressed: _saving || _dealers.isEmpty ? null : _save, child: Text(_saving ? 'Saving...' : 'Save Direct Amount')),
              ],
            ),
    ),
    );
  }
}
