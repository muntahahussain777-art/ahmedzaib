import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../data/app_database.dart';
import '../models/models.dart';
import '../services/report_totals.dart';
import '../services/vip_export_service.dart';
import '../theme/app_theme.dart';
import '../utils/form_utils.dart';
import '../widgets/vip_balance_search.dart';
import '../widgets/vip_widgets.dart';

class ReportsHubScreen extends StatelessWidget {
  const ReportsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Without Date Disel Report', 'Name / vehicle + 2 dates', const WithoutDateDieselReportScreen()),
      ('Dealer Complete Group Wise', 'Dealer group + stock lines', const DealerCompleteGroupWiseReportScreen()),
      ('Stock Report', 'Stock form search + date range', const StockReportScreen()),
    ];
    return VipScaffold(
      title: 'Reports',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text('ZAIB PETROLEUM SERVICE', style: GoogleFonts.cinzel(color: AppColors.gold, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          for (final e in items) ...[
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => e.$3)),
                child: Ink(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.gold.withValues(alpha: 0.28)),
                    color: AppColors.panel.withValues(alpha: 0.92),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.$1, style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 15)),
                            const SizedBox(height: 4),
                            Text(e.$2, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
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

Widget _reportFilters({
  required TextEditingController vehicle,
  required TextEditingController from,
  required TextEditingController to,
  required VoidCallback onSearch,
  required BuildContext context,
  Widget? nameField,
}) {
  return Column(
    children: [
      if (nameField != null) nameField,
      VipField(
        label: 'Vehicle No',
        controller: vehicle,
        hint: 'Exact vehicle (optional)',
      ),
      Row(
        children: [
          Expanded(
            child: VipField(
              label: 'From',
              controller: from,
              readOnly: true,
              onTap: () => pickVipDate(context, from),
              suffix: const Icon(Icons.calendar_month, color: AppColors.gold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: VipField(
              label: 'To',
              controller: to,
              readOnly: true,
              onTap: () => pickVipDate(context, to),
              suffix: const Icon(Icons.calendar_month, color: AppColors.gold),
            ),
          ),
        ],
      ),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: onSearch,
          icon: const Icon(Icons.filter_alt_outlined),
          label: const Text('Search Report'),
        ),
      ),
      const SizedBox(height: 8),
    ],
  );
}

Widget _exportRow({required VoidCallback? onPdf, required VoidCallback? onExcel}) {
  return Row(
    children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: onPdf,
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.gold, side: const BorderSide(color: AppColors.gold)),
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: const Text('VIP PDF'),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: OutlinedButton.icon(
          onPressed: onExcel,
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.gold, side: const BorderSide(color: AppColors.gold)),
          icon: const Icon(Icons.grid_on_outlined, size: 18),
          label: const Text('Excel'),
        ),
      ),
    ],
  );
}

Widget _vipTable({required List<String> headers, required List<List<String>> rows}) {
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DataTable(
      headingRowColor: WidgetStateProperty.all(AppColors.navy),
      dataRowMinHeight: 36,
      dataRowMaxHeight: 56,
      columnSpacing: 14,
      headingTextStyle: GoogleFonts.manrope(color: AppColors.gold, fontWeight: FontWeight.w800, fontSize: 11),
      dataTextStyle: const TextStyle(color: AppColors.cream, fontSize: 11),
      border: TableBorder.all(color: AppColors.gold.withValues(alpha: 0.25)),
      columns: headers.map((h) => DataColumn(label: Text(h))).toList(),
      rows: rows
          .map(
            (r) => DataRow(
              cells: r
                  .map(
                    (c) => DataCell(
                      SizedBox(width: 90, child: Text(c, maxLines: 2, overflow: TextOverflow.ellipsis)),
                    ),
                  )
                  .toList(),
            ),
          )
          .toList(),
    ),
  );
}

Widget _footerLine(String label, String value) {
  return Row(
    children: [
      Expanded(child: Text(label, style: GoogleFonts.manrope(color: AppColors.gold, fontWeight: FontWeight.w800, fontSize: 13))),
      Text(value, style: GoogleFonts.manrope(color: AppColors.cream, fontWeight: FontWeight.w800, fontSize: 14)),
    ],
  );
}

Widget _ledgerFooter(LedgerFooterTotals t) {
  String n(double v) => v.toStringAsFixed(0);
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
      color: AppColors.panel.withValues(alpha: 0.95),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _footerLine('Total Amount', n(t.totalAmount)),
        const SizedBox(height: 8),
        _footerLine('Total Credit', n(t.totalCredit)),
        const SizedBox(height: 8),
        _footerLine('Total Balance', n(t.totalBalance)),
      ],
    ),
  );
}

Widget _stockFooter(StockSummaryTotals t) {
  String lit(double v) => v.toStringAsFixed(2);
  String rs(double v) => v.toStringAsFixed(0);
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
      color: AppColors.panel.withValues(alpha: 0.95),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _footerLine('Add Litter', '${lit(t.addLitter)} L'),
        const SizedBox(height: 6),
        _footerLine('Minus Litter', '${lit(t.minusLitter)} L'),
        const SizedBox(height: 6),
        _footerLine('Baqaya Litter', '${lit(t.baqayaLitter)} L'),
        const SizedBox(height: 10),
        _footerLine('Add Amount', rs(t.addAmount)),
        const SizedBox(height: 6),
        _footerLine('Minus Amount', rs(t.minusAmount)),
        const SizedBox(height: 6),
        _footerLine('Total Balance Amount', rs(t.netAmount)),
      ],
    ),
  );
}

class WithoutDateDieselReportScreen extends StatefulWidget {
  const WithoutDateDieselReportScreen({super.key});
  @override
  State<WithoutDateDieselReportScreen> createState() => _WithoutDateDieselReportScreenState();
}

class _WithoutDateDieselReportScreenState extends State<WithoutDateDieselReportScreen> {
  final _vehicle = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();
  List<Customer> _customers = [];
  Customer? _selected;
  List<DieselSale> _rows = [];
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final customers = await AppDatabase.instance.getCustomers();
    if (!mounted) return;
    setState(() => _customers = customers);
    await _load();
  }

  @override
  void dispose() {
    _vehicle.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await AppDatabase.instance.searchDieselReport(
      name: _selected?.name,
      vehicle: _vehicle.text,
      from: _from.text.trim().isEmpty ? null : _from.text.trim(),
      to: _to.text.trim().isEmpty ? null : _to.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _export(bool pdf) async {
    setState(() => _exporting = true);
    try {
      final headers = VipExportService.dieselHeaders;
      final data = VipExportService.dieselRows(_rows);
      final tot = LedgerFooterTotals.fromDiesel(_rows);
      final path = pdf
          ? await VipExportService.tablePdf(
              title: 'Without Date Disel Report',
              headers: headers,
              rows: data,
              subtitle: 'Name: ${_selected?.name ?? '-'}  Vehicle: ${_vehicle.text}  ${_from.text} → ${_to.text}',
              footerLines: [
                ('Total Amount', tot.totalAmount.toStringAsFixed(0)),
                ('Total Credit', tot.totalCredit.toStringAsFixed(0)),
                ('Total Balance', tot.totalBalance.toStringAsFixed(0)),
              ],
            )
          : await VipExportService.tableExcel(title: 'Without_Date_Disel_Report', headers: headers, rows: data);
      await VipExportService.shareFile(path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final table = VipExportService.dieselRows(_rows);
    final tot = LedgerFooterTotals.fromDiesel(_rows);
    return VipScaffold(
      title: 'Without Date Disel Report',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                _reportFilters(
                  context: context,
                  vehicle: _vehicle,
                  from: _from,
                  to: _to,
                  onSearch: _load,
                  nameField: VipSearchDropdown<Customer>(
                    label: 'Customer Name',
                    items: _customers,
                    value: _selected,
                    displayString: (c) => c.name,
                    allowClear: true,
                    hint: 'Type / select exact name',
                    onSelected: (c) {
                      setState(() => _selected = c);
                      _load();
                    },
                  ),
                ),
                _exportRow(onPdf: _exporting || _rows.isEmpty ? null : () => _export(true), onExcel: _exporting || _rows.isEmpty ? null : () => _export(false)),
                const SizedBox(height: 8),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
                : _rows.isEmpty
                    ? const EmptyState(message: 'Koi record nahi mila.')
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        children: [
                          Text('PC columns • ${_rows.length} rows', style: const TextStyle(color: AppColors.goldSoft, fontSize: 12)),
                          const SizedBox(height: 8),
                          _vipTable(headers: VipExportService.dieselHeaders, rows: table),
                          _ledgerFooter(tot),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class DealerCompleteGroupWiseReportScreen extends StatefulWidget {
  const DealerCompleteGroupWiseReportScreen({super.key});
  @override
  State<DealerCompleteGroupWiseReportScreen> createState() => _DealerCompleteGroupWiseReportScreenState();
}

class _DealerCompleteGroupWiseReportScreenState extends State<DealerCompleteGroupWiseReportScreen> {
  final _vehicle = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();
  List<Dealer> _dealers = [];
  Dealer? _selected;
  List<DealerGroupReportRow> _rows = [];
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final dealers = await AppDatabase.instance.getDealers();
    if (!mounted) return;
    setState(() => _dealers = dealers);
    await _load();
  }

  @override
  void dispose() {
    _vehicle.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await AppDatabase.instance.searchDealerGroupReport(
      name: _selected?.name,
      vehicle: _vehicle.text,
      from: _from.text.trim().isEmpty ? null : _from.text.trim(),
      to: _to.text.trim().isEmpty ? null : _to.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _export(bool pdf) async {
    setState(() => _exporting = true);
    try {
      final headers = VipExportService.dealerHeaders;
      final data = VipExportService.dealerRows(_rows);
      final tot = LedgerFooterTotals.fromDealerGroup(_rows);
      final path = pdf
          ? await VipExportService.tablePdf(
              title: 'Dealer Complete Group Wise',
              headers: headers,
              rows: data,
              subtitle: 'Name: ${_selected?.name ?? '-'}  Vehicle: ${_vehicle.text}  ${_from.text} → ${_to.text}',
              footerLines: [
                ('Total Amount', tot.totalAmount.toStringAsFixed(0)),
                ('Total Credit', tot.totalCredit.toStringAsFixed(0)),
                ('Total Balance', tot.totalBalance.toStringAsFixed(0)),
              ],
            )
          : await VipExportService.tableExcel(title: 'Dealer_Complete_Group_Wise', headers: headers, rows: data);
      await VipExportService.shareFile(path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final table = VipExportService.dealerRows(_rows);
    final tot = LedgerFooterTotals.fromDealerGroup(_rows);
    return VipScaffold(
      title: 'Dealer Complete Group Wise',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                _reportFilters(
                  context: context,
                  vehicle: _vehicle,
                  from: _from,
                  to: _to,
                  onSearch: _load,
                  nameField: VipSearchDropdown<Dealer>(
                    label: 'Dealer Name',
                    items: _dealers,
                    value: _selected,
                    displayString: (d) => d.name,
                    allowClear: true,
                    hint: 'Type / select exact name',
                    onSelected: (d) {
                      setState(() => _selected = d);
                      _load();
                    },
                  ),
                ),
                _exportRow(onPdf: _exporting || _rows.isEmpty ? null : () => _export(true), onExcel: _exporting || _rows.isEmpty ? null : () => _export(false)),
                const SizedBox(height: 8),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
                : _rows.isEmpty
                    ? const EmptyState(message: 'Koi dealer record nahi mila.')
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        children: [
                          Text('PC columns • ${_rows.length} rows', style: const TextStyle(color: AppColors.goldSoft, fontSize: 12)),
                          const SizedBox(height: 8),
                          _vipTable(headers: VipExportService.dealerHeaders, rows: table),
                          _ledgerFooter(tot),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class StockReportScreen extends StatefulWidget {
  const StockReportScreen({super.key});
  @override
  State<StockReportScreen> createState() => _StockReportScreenState();
}

class _StockReportScreenState extends State<StockReportScreen> {
  final _vehicle = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();
  List<Dealer> _dealers = [];
  Dealer? _selected;
  List<StockDieselEntry> _rows = [];
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _from.text = today;
    _to.text = today;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final dealers = await AppDatabase.instance.getDealers();
    if (!mounted) return;
    setState(() => _dealers = dealers);
    await _load();
  }

  @override
  void dispose() {
    _vehicle.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await AppDatabase.instance.searchStockReport(
      name: _selected?.name,
      vehicle: _vehicle.text,
      from: _from.text.trim().isEmpty ? null : _from.text.trim(),
      to: _to.text.trim().isEmpty ? null : _to.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _export(bool pdf) async {
    setState(() => _exporting = true);
    try {
      final headers = VipExportService.stockHeaders;
      final data = VipExportService.stockRows(_rows);
      final tot = StockSummaryTotals.fromRows(_rows);
      final path = pdf
          ? await VipExportService.tablePdf(
              title: 'Stock Report',
              headers: headers,
              rows: data,
              subtitle: 'Name: ${_selected?.name ?? '-'}  Vehicle: ${_vehicle.text}  ${_from.text} → ${_to.text}',
              footerLines: [
                ('Add Litter', tot.addLitter.toStringAsFixed(2)),
                ('Minus Litter', tot.minusLitter.toStringAsFixed(2)),
                ('Baqaya Litter', tot.baqayaLitter.toStringAsFixed(2)),
                ('Add Amount', tot.addAmount.toStringAsFixed(0)),
                ('Minus Amount', tot.minusAmount.toStringAsFixed(0)),
                ('Total Balance Amount', tot.netAmount.toStringAsFixed(0)),
              ],
            )
          : await VipExportService.tableExcel(title: 'Stock_Report', headers: headers, rows: data);
      await VipExportService.shareFile(path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final table = VipExportService.stockRows(_rows);
    final tot = StockSummaryTotals.fromRows(_rows);
    return VipScaffold(
      title: 'Stock Report',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                _reportFilters(
                  context: context,
                  vehicle: _vehicle,
                  from: _from,
                  to: _to,
                  onSearch: _load,
                  nameField: VipSearchDropdown<Dealer>(
                    label: 'Dealer Name',
                    items: _dealers,
                    value: _selected,
                    displayString: (d) => d.name,
                    allowClear: true,
                    hint: 'Type / select exact name',
                    onSelected: (d) {
                      setState(() => _selected = d);
                      _load();
                    },
                  ),
                ),
                _exportRow(onPdf: _exporting || _rows.isEmpty ? null : () => _export(true), onExcel: _exporting || _rows.isEmpty ? null : () => _export(false)),
                const SizedBox(height: 8),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
                : _rows.isEmpty
                    ? const EmptyState(message: 'Koi stock record nahi mila.')
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        children: [
                          Text('PC columns • ${_rows.length} rows', style: const TextStyle(color: AppColors.goldSoft, fontSize: 12)),
                          const SizedBox(height: 8),
                          _vipTable(headers: VipExportService.stockHeaders, rows: table),
                          _stockFooter(tot),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
