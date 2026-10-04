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

class DieselSalesListScreen extends StatefulWidget {
  const DieselSalesListScreen({super.key});

  @override
  State<DieselSalesListScreen> createState() => _DieselSalesListScreenState();
}

class _DieselSalesListScreenState extends State<DieselSalesListScreen> {
  final _search = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();
  List<DieselSale> _items = [];
  CustomerLedgerSummary? _totals;
  LitterRateAvgSummary? _avg;
  String? _matchedCustomerName;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
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
    final from = _from.text.trim();
    final to = _to.text.trim();
    final rows = await AppDatabase.instance.getSales(
      query: _search.text,
      from: from.isEmpty ? null : from,
      to: to.isEmpty ? null : to,
    );
    final byName = await AppDatabase.instance.getCustomerLedgerByExactName(_search.text);
    final matched = await AppDatabase.instance.findCustomerByExactName(_search.text);
    final totals = byName ?? await AppDatabase.instance.getGlobalCustomerLedger();
    final avg = LitterRateAvgSummary.fromDiesel(rows);
    if (!mounted) return;
    setState(() {
      _items = rows;
      _totals = totals;
      _avg = avg;
      _matchedCustomerName = matched?.name;
      _loading = false;
    });
  }

  Future<void> _openForm({DieselSale? sale}) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => DieselSaleFormScreen(sale: sale)),
    );
    if (changed == true) _load();
  }

  Future<void> _delete(DieselSale s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Delete Sale?', style: TextStyle(color: AppColors.gold)),
        content: Text('${s.customerName} — ${s.amount.toStringAsFixed(0)} delete?', style: const TextStyle(color: AppColors.cream)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok != true || s.id == null) return;
    await AppDatabase.instance.deleteSale(s.id!);
    if (!mounted) return;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final searchName = _search.text.trim();
    final bannerTitle = _matchedCustomerName != null ? 'Customer: $_matchedCustomerName' : 'All Customers';
    return VipScaffold(
      title: 'Daily Diesel Sales',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.local_gas_station),
        label: const Text('Add Sale'),
      ),
      child: Column(
        children: [
          if (_totals != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: VipBalanceBanner.customer(_totals!, title: bannerTitle),
            ),
          if (_avg != null && (_from.text.trim().isNotEmpty || _to.text.trim().isNotEmpty || searchName.isNotEmpty))
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
                TextField(
                  controller: _search,
                  onChanged: (_) => _load(),
                  decoration: const InputDecoration(
                    hintText: 'Search customer / vehicle / receipt',
                    prefixIcon: Icon(Icons.search, color: AppColors.gold),
                  ),
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
                    ? const EmptyState(message: 'Abhi koi diesel sale nahi.\nPehle customer add karein, phir sale entry karein.')
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final s = _items[i];
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () => _openForm(sale: s),
                              onLongPress: () => _delete(s),
                              child: Ink(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.22)),
                                  color: AppColors.panel.withValues(alpha: 0.9),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              s.customerName,
                                              style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 16),
                                            ),
                                          ),
                                          Text(
                                            s.amount.toStringAsFixed(0),
                                            style: GoogleFonts.manrope(
                                              color: AppColors.gold,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${s.date}  •  ${s.litter.toStringAsFixed(2)} L  •  Rate ${s.rate.toStringAsFixed(2)}',
                                        style: const TextStyle(color: AppColors.muted, fontSize: 12),
                                      ),
                                      if (s.vehicle.isNotEmpty)
                                        Text('Vehicle: ${s.vehicle}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                      Text(
                                        'Credit ${s.credit.toStringAsFixed(0)}  |  Balance ${s.balance.toStringAsFixed(0)}',
                                        style: const TextStyle(color: AppColors.goldSoft, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
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

class DieselSaleFormScreen extends StatefulWidget {
  const DieselSaleFormScreen({super.key, this.sale});

  final DieselSale? sale;

  @override
  State<DieselSaleFormScreen> createState() => _DieselSaleFormScreenState();
}

class _DieselSaleFormScreenState extends State<DieselSaleFormScreen> {
  final _date = TextEditingController();
  final _receipt = TextEditingController();
  final _vehicle = TextEditingController();
  final _litter = TextEditingController();
  final _rate = TextEditingController();
  final _amount = TextEditingController();
  final _advance = TextEditingController();
  final _credit = TextEditingController();
  final _balance = TextEditingController();
  final _note = TextEditingController();

  List<Customer> _customers = [];
  Customer? _selected;
  CustomerLedgerSummary? _summary;
  bool _saving = false;
  bool _loading = true;
  bool _savedInSession = false;

  bool get _isEdit => widget.sale?.id != null;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final customers = await AppDatabase.instance.getCustomers();
    final sale = widget.sale;
    _date.text = sale?.date ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
    _receipt.text = sale?.receiptNo ?? '';
    _vehicle.text = sale?.vehicle ?? '';
    _litter.text = sale == null ? '' : _fmt(sale.litter);
    _rate.text = sale == null ? '' : _fmt(sale.rate);
    _amount.text = sale == null ? '' : _fmt(sale.amount);
    _advance.text = sale == null ? '' : _fmt(sale.advance);
    // Credit locked — daily sale mein type nahi; edit pe purani value dikhao
    _credit.text = sale == null ? '0' : _fmt(sale.credit);
    _balance.text = sale == null ? '' : _fmt(sale.balance);
    _note.text = sale?.note ?? '';

    Customer? selected;
    if (sale != null) {
      for (final c in customers) {
        if (c.id == sale.customerId) {
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
    _recalc();
  }

  Future<void> _onCustomerSelected(Customer? c) async {
    setState(() {
      _selected = c;
      _summary = null;
    });
    if (c?.id == null) return;
    final summary = await AppDatabase.instance.getCustomerLedgerSummary(c!.id!);
    if (!mounted) return;
    setState(() => _summary = summary);
  }

  @override
  void dispose() {
    _date.dispose();
    _receipt.dispose();
    _vehicle.dispose();
    _litter.dispose();
    _rate.dispose();
    _amount.dispose();
    _advance.dispose();
    _credit.dispose();
    _balance.dispose();
    _note.dispose();
    super.dispose();
  }

  String _fmt(double v) {
    if (v == 0) return '';
    return v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
  }

  double _num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '')) ?? 0;

  void _recalc() {
    final litter = _num(_litter);
    final rate = _num(_rate);
    final advance = _num(_advance);
    // New entry: credit always 0. Edit: locked existing credit (no typing).
    final credit = _isEdit ? _num(_credit) : 0.0;
    double amount = _num(_amount);

    if (litter > 0 && rate > 0) {
      amount = litter * rate;
      _amount.text = amount.toStringAsFixed(2);
    }

    final balance = (amount - credit) + advance;
    _balance.text = balance.toStringAsFixed(2);
    if (!_isEdit) _credit.text = '0';
    setState(() {});
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(_date.text) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 2),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.gold, surface: AppColors.panel),
        ),
        child: child!,
      ),
    );
    if (picked != null) _date.text = DateFormat('yyyy-MM-dd').format(picked);
  }

  Future<void> _save() async {
    if (_selected?.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pehle customer select karein')));
      return;
    }

    final litter = _num(_litter);
    final rate = _num(_rate);
    final amount = _num(_amount);
    if (litter <= 0 && rate <= 0 && amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Litter/Rate ya Amount mein se kuch likhein')),
      );
      return;
    }

    await runVipSave(
      context: context,
      setSaving: (v) { if (mounted) setState(() => _saving = v); },
      popOnSuccess: _isEdit,
      action: () async {
        final model = DieselSale(
          id: widget.sale?.id,
          customerId: _selected!.id!,
          customerName: _selected!.name,
          date: _date.text.trim(),
          receiptNo: _receipt.text.trim(),
          vehicle: _vehicle.text.trim(),
          litter: litter,
          rate: rate,
          amount: amount,
          advance: _num(_advance),
          credit: _isEdit ? _num(_credit) : 0,
          balance: _num(_balance),
          note: _note.text.trim(),
        );
        if (_isEdit) {
          await AppDatabase.instance.updateSale(model);
        } else {
          await AppDatabase.instance.insertSale(model);
        }
      },
    ).then((ok) async {
      if (!ok || _isEdit || !mounted) return;
      _savedInSession = true;
      // WinForms: naam + date same — sirf entry fields clear
      _receipt.clear();
      _vehicle.clear();
      _litter.clear();
      _rate.clear();
      _amount.clear();
      _advance.clear();
      _balance.clear();
      _note.clear();
      if (_selected?.id != null) {
        final summary = await AppDatabase.instance.getCustomerLedgerSummary(_selected!.id!);
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
      isEdit: _isEdit,
      child: VipScaffold(
      title: _isEdit ? 'Edit Diesel Sale' : 'Daily Diesel Sales',
      backResult: _isEdit || _savedInSession,
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                Text('Zaib Petroleum Service', style: GoogleFonts.cinzel(color: AppColors.goldSoft, fontSize: 13)),
                const SizedBox(height: 10),
                if (_summary != null) VipBalanceBanner.customer(_summary!),
                VipSearchDropdown<Customer>(
                  label: 'Customer *',
                  items: _customers,
                  value: _selected,
                  displayString: (c) => c.name,
                  onSelected: _onCustomerSelected,
                ),
                VipField(label: 'Date', controller: _date, readOnly: true, onTap: _pickDate, suffix: const Icon(Icons.calendar_month, color: AppColors.gold)),
                VipField(label: 'Receipt No', controller: _receipt),
                VipField(label: 'Vehicle', controller: _vehicle, hint: 'Vehicle number'),
                Row(
                  children: [
                    Expanded(
                      child: VipField(
                        label: 'Litter',
                        controller: _litter,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => _recalc(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: VipField(
                        label: 'Rate',
                        controller: _rate,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => _recalc(),
                      ),
                    ),
                  ],
                ),
                VipField(
                  label: 'Amount',
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => _recalc(),
                ),
                Row(
                  children: [
                    Expanded(
                      child: VipField(
                        label: 'Advance',
                        controller: _advance,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => _recalc(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: VipField(
                        label: 'Credit (Locked)',
                        controller: _credit,
                        readOnly: true,
                        hint: 'Daily sale mein credit band',
                      ),
                    ),
                  ],
                ),
                VipField(label: 'Balance', controller: _balance, readOnly: true),
                VipField(label: 'Note', controller: _note, maxLines: 2),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving || _customers.isEmpty ? null : _save,
                    child: Text(_saving ? 'Saving...' : 'Save Sale'),
                  ),
                ),
              ],
            ),
    ),
    );
  }
}
