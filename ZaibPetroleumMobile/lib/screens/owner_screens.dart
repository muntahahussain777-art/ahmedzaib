import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/app_database.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import '../services/vip_export_service.dart';
import '../theme/app_theme.dart';
import '../utils/form_utils.dart';
import '../widgets/vip_balance_search.dart';
import '../widgets/vip_widgets.dart';
import 'login_screen.dart';

/// Owner home — sirf 2 view forms (edit/delete nahi). Admin home alag.
class OwnerHomeScreen extends StatelessWidget {
  const OwnerHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tiles = <(IconData, String, String, Widget)>[
      (Icons.people_alt_rounded, 'Customer Ledger', 'Name search • dates • VIP PDF (view only)', const OwnerCustomerLedgerScreen()),
      (Icons.local_shipping_outlined, 'Dealer Ledger', 'Name search • dates • VIP PDF (view only)', const OwnerDealerLedgerScreen()),
    ];

    return VipScaffold(
      title: 'Owner View',
      showBack: false,
      actions: [
        IconButton(
          tooltip: 'Fingerprint',
          onPressed: () => _ownerFingerprintDialog(context),
          icon: const Icon(Icons.fingerprint, color: AppColors.gold),
        ),
        IconButton(
          tooltip: 'Logout',
          onPressed: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (_) => false,
            );
          },
          icon: const Icon(Icons.logout_rounded, color: AppColors.gold),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF243356), Color(0xFF121A2E)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OWNER — VIEW ONLY',
                  style: GoogleFonts.cinzel(
                    color: AppColors.gold,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Entries dekh sakte ho • Edit / Delete nahi',
                  style: GoogleFonts.manrope(color: AppColors.muted, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  'Developed by Irtaza Hussain',
                  style: GoogleFonts.manrope(color: AppColors.muted, fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          for (final t in tiles) ...[
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () async {
                  unawaited(SyncService.instance.syncNow());
                  if (!context.mounted) return;
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => t.$4));
                },
                child: Ink(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: AppColors.panel.withValues(alpha: 0.9),
                    border: Border.all(color: AppColors.gold.withValues(alpha: 0.22)),
                  ),
                  child: Row(
                    children: [
                      Icon(t.$1, color: AppColors.gold, size: 28),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.$2, style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text(t.$3, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.goldSoft, size: 16),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

Future<void> _ownerFingerprintDialog(BuildContext context) async {
  final pass = TextEditingController();
  final bioOn = await AuthService.instance.fingerprintEnabled;
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.panel,
      title: Text(bioOn ? 'Fingerprint Off?' : 'Fingerprint On?', style: const TextStyle(color: AppColors.gold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            bioOn ? 'Owner password likhein, fingerprint band karne ke liye.' : 'Owner password (zaibay) likhein, fingerprint on karne ke liye.',
            style: const TextStyle(color: AppColors.cream, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: pass,
            obscureText: true,
            style: const TextStyle(color: AppColors.cream),
            decoration: const InputDecoration(
              labelText: 'Password',
              labelStyle: TextStyle(color: AppColors.goldSoft),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(bioOn ? 'Off' : 'On', style: const TextStyle(color: AppColors.gold))),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    if (bioOn) {
      await AuthService.instance.disableFingerprint(pass.text);
    } else {
      await AuthService.instance.enableFingerprint(pass.text);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(bioOn ? 'Fingerprint off' : 'Fingerprint on — ab owner login ho sakta hai')),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
  }
}

// ---------------- Customer (owner) ----------------

class OwnerCustomerLedgerScreen extends StatefulWidget {
  const OwnerCustomerLedgerScreen({super.key});

  @override
  State<OwnerCustomerLedgerScreen> createState() => _OwnerCustomerLedgerScreenState();
}

class _OwnerCustomerLedgerScreenState extends State<OwnerCustomerLedgerScreen> {
  final _from = TextEditingController();
  final _to = TextEditingController();
  final _vehicleText = TextEditingController();
  List<Customer> _customers = [];
  List<String> _vehicles = [];
  Customer? _selected;
  String? _vehicleSelected;
  List<OwnerLedgerLine> _rows = [];
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final customers = await AppDatabase.instance.getCustomers();
    final vehicles = await AppDatabase.instance.distinctCustomerVehicles();
    if (!mounted) return;
    setState(() {
      _customers = customers;
      _vehicles = vehicles;
    });
    await _load();
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    _vehicleText.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final veh = (_vehicleSelected ?? _vehicleText.text).trim();
      final rows = await AppDatabase.instance.ownerCustomerLedger(
        name: _selected?.name,
        vehicle: veh.isEmpty ? null : veh,
        from: _from.text.trim().isEmpty ? null : _from.text.trim(),
        to: _to.text.trim().isEmpty ? null : _to.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rows = [];
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Load fail: $e')));
    }
  }

  Future<void> _onCustomer(Customer? c) async {
    setState(() => _selected = c);
    final vehicles = await AppDatabase.instance.distinctCustomerVehicles(customerName: c?.name);
    if (!mounted) return;
    setState(() {
      _vehicles = vehicles;
      if (_vehicleSelected != null && !_vehicles.contains(_vehicleSelected)) {
        _vehicleSelected = null;
        _vehicleText.clear();
      }
    });
    await _load();
  }

  Future<void> _exportPdf() async {
    setState(() => _exporting = true);
    try {
      final titleName = _selected?.name ?? 'All Customers';
      final path = await VipExportService.ownerLedgerPdf(
        title: 'Owner Customer Ledger',
        partyLabel: titleName,
        rows: _rows,
        subtitle: 'Vehicle: ${_vehicleSelected ?? _vehicleText.text}  ${_from.text} → ${_to.text}',
      );
      await VipExportService.shareFile(path, subject: 'Owner Customer Ledger');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totAmt = _rows.fold<double>(0, (s, e) => s + e.amount);
    final totCred = _rows.fold<double>(0, (s, e) => s + e.credit);
    final bal = _rows.isEmpty ? 0.0 : _rows.last.runningBalance;
    return VipScaffold(
      title: 'Customer Ledger',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                VipSearchDropdown<Customer>(
                  label: 'Customer Name',
                  items: _customers,
                  value: _selected,
                  displayString: (c) => c.name,
                  allowClear: true,
                  hint: 'Name type / suggest',
                  onSelected: _onCustomer,
                ),
                VipSearchDropdown<String>(
                  label: 'Vehicle No',
                  items: _vehicles,
                  value: _vehicleSelected,
                  displayString: (v) => v,
                  allowClear: true,
                  hint: 'Vehicle type / suggest',
                  onSelected: (v) {
                    setState(() {
                      _vehicleSelected = v;
                      _vehicleText.text = v ?? '';
                    });
                    _load();
                  },
                ),
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
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.search),
                        label: const Text('Search'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _exporting || _rows.isEmpty ? null : _exportPdf,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.gold,
                          side: const BorderSide(color: AppColors.gold),
                        ),
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                        label: const Text('VIP PDF'),
                      ),
                    ),
                  ],
                ),
                if (_selected != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: VipBalanceBanner.customer(
                      CustomerLedgerSummary(totalAmount: totAmt, totalCredit: totCred, balance: bal),
                      title: 'Customer: ${_selected!.name}',
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
                : _rows.isEmpty
                    ? const EmptyState(message: 'Koi entry nahi — name / date search karein.')
                    : _OwnerLedgerTable(
                        rows: _rows,
                        totalAmount: totAmt,
                        totalCredit: totCred,
                        balance: bal,
                      ),
          ),
        ],
      ),
    );
  }
}

// ---------------- Dealer (owner) ----------------

class OwnerDealerLedgerScreen extends StatefulWidget {
  const OwnerDealerLedgerScreen({super.key});

  @override
  State<OwnerDealerLedgerScreen> createState() => _OwnerDealerLedgerScreenState();
}

class _OwnerDealerLedgerScreenState extends State<OwnerDealerLedgerScreen> {
  final _from = TextEditingController();
  final _to = TextEditingController();
  final _vehicleText = TextEditingController();
  List<Dealer> _dealers = [];
  List<String> _vehicles = [];
  Dealer? _selected;
  String? _vehicleSelected;
  List<OwnerLedgerLine> _rows = [];
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final dealers = await AppDatabase.instance.getDealers();
    final vehicles = await AppDatabase.instance.distinctDealerVehicles();
    if (!mounted) return;
    setState(() {
      _dealers = dealers;
      _vehicles = vehicles;
    });
    await _load();
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    _vehicleText.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final veh = (_vehicleSelected ?? _vehicleText.text).trim();
      final rows = await AppDatabase.instance.ownerDealerLedger(
        name: _selected?.name,
        vehicle: veh.isEmpty ? null : veh,
        from: _from.text.trim().isEmpty ? null : _from.text.trim(),
        to: _to.text.trim().isEmpty ? null : _to.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rows = [];
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Load fail: $e')));
    }
  }

  Future<void> _onDealer(Dealer? d) async {
    setState(() => _selected = d);
    final vehicles = await AppDatabase.instance.distinctDealerVehicles(dealerName: d?.name);
    if (!mounted) return;
    setState(() {
      _vehicles = vehicles;
      if (_vehicleSelected != null && !_vehicles.contains(_vehicleSelected)) {
        _vehicleSelected = null;
        _vehicleText.clear();
      }
    });
    await _load();
  }

  Future<void> _exportPdf() async {
    setState(() => _exporting = true);
    try {
      final titleName = _selected?.name ?? 'All Dealers';
      final path = await VipExportService.ownerLedgerPdf(
        title: 'Owner Dealer Ledger',
        partyLabel: titleName,
        rows: _rows,
        subtitle: 'Vehicle: ${_vehicleSelected ?? _vehicleText.text}  ${_from.text} → ${_to.text}',
      );
      await VipExportService.shareFile(path, subject: 'Owner Dealer Ledger');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totAmt = _rows.fold<double>(0, (s, e) => s + e.amount);
    final totCred = _rows.fold<double>(0, (s, e) => s + e.credit);
    final bal = _rows.isEmpty ? 0.0 : _rows.last.runningBalance;
    return VipScaffold(
      title: 'Dealer Ledger',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                VipSearchDropdown<Dealer>(
                  label: 'Dealer Name',
                  items: _dealers,
                  value: _selected,
                  displayString: (d) => d.name,
                  allowClear: true,
                  hint: 'Name type / suggest',
                  onSelected: _onDealer,
                ),
                VipSearchDropdown<String>(
                  label: 'Vehicle No',
                  items: _vehicles,
                  value: _vehicleSelected,
                  displayString: (v) => v,
                  allowClear: true,
                  hint: 'Vehicle type / suggest',
                  onSelected: (v) {
                    setState(() {
                      _vehicleSelected = v;
                      _vehicleText.text = v ?? '';
                    });
                    _load();
                  },
                ),
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
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.search),
                        label: const Text('Search'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _exporting || _rows.isEmpty ? null : _exportPdf,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.gold,
                          side: const BorderSide(color: AppColors.gold),
                        ),
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                        label: const Text('VIP PDF'),
                      ),
                    ),
                  ],
                ),
                if (_selected != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: VipBalanceBanner.dealer(
                      DealerLedgerSummary(ddAmount: totAmt, dAmount: totCred, balance: bal),
                      title: 'Dealer: ${_selected!.name}',
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
                : _rows.isEmpty
                    ? const EmptyState(message: 'Koi entry nahi — name / date search karein.')
                    : _OwnerLedgerTable(
                        rows: _rows,
                        totalAmount: totAmt,
                        totalCredit: totCred,
                        balance: bal,
                      ),
          ),
        ],
      ),
    );
  }
}

/// PDF jaisa table — Note + Credit red
class _OwnerLedgerTable extends StatelessWidget {
  const _OwnerLedgerTable({
    required this.rows,
    required this.totalAmount,
    required this.totalCredit,
    required this.balance,
  });

  final List<OwnerLedgerLine> rows;
  final double totalAmount;
  final double totalCredit;
  final double balance;

  static String _n(double v) => v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);

  @override
  Widget build(BuildContext context) {
    const headers = ['Name', 'Date', 'Vehicle', 'Note', 'Litter', 'Rate', 'Amount', 'Credit', 'Balance'];
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      children: [
        Text('Table • ${rows.length} rows', style: const TextStyle(color: AppColors.goldSoft, fontSize: 12)),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(AppColors.navy),
            dataRowMinHeight: 36,
            dataRowMaxHeight: 56,
            columnSpacing: 12,
            headingTextStyle: GoogleFonts.manrope(color: AppColors.gold, fontWeight: FontWeight.w800, fontSize: 11),
            dataTextStyle: const TextStyle(color: AppColors.cream, fontSize: 11),
            border: TableBorder.all(color: AppColors.gold.withValues(alpha: 0.25)),
            columns: headers.map((h) => DataColumn(label: Text(h))).toList(),
            rows: [
              for (final e in rows)
                DataRow(
                  cells: [
                    _cell(e.partyName.isEmpty ? '—' : e.partyName, width: 110),
                    _cell(e.date, width: 88),
                    _cell(e.vehicle.isEmpty ? '—' : e.vehicle, width: 90),
                    _cell(e.note, width: 100, red: e.note.trim().isNotEmpty),
                    _cell(_n(e.litter), width: 70),
                    _cell(_n(e.rate), width: 70),
                    _cell(_n(e.amount), width: 80),
                    _cell(_n(e.credit), width: 80, red: true),
                    _cell(_n(e.runningBalance), width: 90),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
            color: AppColors.panel.withValues(alpha: 0.95),
          ),
          child: Column(
            children: [
              _foot('Total Amount', _n(totalAmount)),
              const SizedBox(height: 8),
              _foot('Total Credit', _n(totalCredit), red: true),
              const SizedBox(height: 8),
              _foot('Balance', _n(balance)),
            ],
          ),
        ),
      ],
    );
  }

  static DataCell _cell(String text, {double width = 90, bool red = false}) {
    return DataCell(
      SizedBox(
        width: width,
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: red ? AppColors.danger : AppColors.cream,
            fontSize: 11,
            fontWeight: red ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  static Widget _foot(String label, String value, {bool red = false}) {
    return Row(
      children: [
        Expanded(child: Text(label, style: GoogleFonts.manrope(color: AppColors.gold, fontWeight: FontWeight.w800, fontSize: 13))),
        Text(
          value,
          style: GoogleFonts.manrope(
            color: red ? AppColors.danger : AppColors.cream,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
