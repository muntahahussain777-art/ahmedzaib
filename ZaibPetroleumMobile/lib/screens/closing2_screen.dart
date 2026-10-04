import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../services/closing2_service.dart';
import '../services/vip_export_service.dart';
import '../theme/app_theme.dart';
import '../utils/form_utils.dart';
import '../widgets/vip_widgets.dart';

class Closing2Screen extends StatefulWidget {
  const Closing2Screen({super.key});

  @override
  State<Closing2Screen> createState() => _Closing2ScreenState();
}

class _Closing2ScreenState extends State<Closing2Screen> {
  final _from = TextEditingController();
  final _to = TextEditingController();
  final _tempName = TextEditingController();
  final _tempAmount = TextEditingController();
  String _tempSide = 'Receivable';
  Closing2Report? _report;
  bool _loading = false;
  bool _exporting = false;
  String? _error;

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
    _from.dispose();
    _to.dispose();
    _tempName.dispose();
    _tempAmount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final from = DateTime.tryParse(_from.text);
    final to = DateTime.tryParse(_to.text);
    if (from == null || to == null || from.isAfter(to)) {
      setState(() => _error = 'From date To date se bari nahi honi chahiye.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await Closing2Service.load(fromDate: _from.text, toDate: _to.text);
      if (!mounted) return;
      setState(() {
        _report = report;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _addTemp() {
    final name = _tempName.text.trim();
    final amt = double.tryParse(_tempAmount.text.trim().replaceAll(',', '')) ?? 0;
    if (name.isEmpty || amt == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Temp name + amount likhein')));
      return;
    }
    Closing2Session.addTemp(name: name, amount: amt, receivable: _tempSide == 'Receivable');
    _tempName.clear();
    _tempAmount.clear();
    _load();
  }

  Future<void> _remove(ClosingNamedAmount e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Remove Entry?', style: TextStyle(color: AppColors.gold)),
        content: Text(
          e.isTemp
              ? '[Temp] ${e.name} hata dein?'
              : '${e.name} temporarily list se hata dein?\n(DB delete nahi hota)',
          style: const TextStyle(color: AppColors.cream),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok != true) return;
    Closing2Session.hideEntry(e);
    _load();
  }

  Future<void> _export({required bool pdf}) async {
    final r = _report;
    if (r == null) return;
    setState(() => _exporting = true);
    try {
      final path = pdf
          ? await VipExportService.closing2Pdf(r, from: _from.text, to: _to.text)
          : await VipExportService.closing2Excel(r, from: _from.text, to: _to.text);
      await VipExportService.shareFile(path, subject: 'Closing 2');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export fail: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _n(double v, {int d = 2}) => v.toStringAsFixed(d);

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return VipScaffold(
      title: 'Closing 2',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text('Zaib Petroleum Service', style: GoogleFonts.cinzel(color: AppColors.goldSoft, fontSize: 13)),
          const SizedBox(height: 12),
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
          ElevatedButton(onPressed: _loading ? null : _load, child: Text(_loading ? 'Loading...' : 'Load Closing')),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _exporting || r == null ? null : () => _export(pdf: true),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.gold, side: const BorderSide(color: AppColors.gold)),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('PDF'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _exporting || r == null ? null : () => _export(pdf: false),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.gold, side: const BorderSide(color: AppColors.gold)),
                  icon: const Icon(Icons.grid_on_outlined),
                  label: const Text('Excel'),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ],
          if (_loading) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator(color: AppColors.gold)),
          ],
          if (!_loading && r != null) ...[
            const SizedBox(height: 14),
            _sectionTitle('Profit Summary (Date Range)'),
            _kpiGrid([
              ('Sale Avg', _n(r.custAvg, d: 3)),
              ('Dealer Avg', _n(r.dealerAvg, d: 3)),
              ('Margin / L', _n(r.margin, d: 3)),
              ('Liters Sold', _n(r.customerLit)),
              ('Gross Profit', _n(r.grossProfit)),
              ('Expense', _n(r.expense)),
            ]),
            const SizedBox(height: 10),
            _netCard(r.netProfit),
            const SizedBox(height: 8),
            Text(
              'Sale ${_n(r.customerAmt)} / ${_n(r.customerLit)} L   •   Purchase ${_n(r.purchaseAmt)} / ${_n(r.purchaseLit)} L',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 18),
            _sectionTitle('Temp Entry'),
            DropdownButtonFormField<String>(
              initialValue: _tempSide,
              dropdownColor: AppColors.panel,
              decoration: const InputDecoration(labelText: 'Side'),
              items: const [
                DropdownMenuItem(value: 'Receivable', child: Text('Receivable (Customer)')),
                DropdownMenuItem(value: 'Payable', child: Text('Payable (Dealer)')),
              ],
              onChanged: (v) => setState(() => _tempSide = v ?? 'Receivable'),
            ),
            const SizedBox(height: 10),
            VipField(label: 'Temp Name', controller: _tempName),
            VipField(label: 'Temp Amount', controller: _tempAmount, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            ElevatedButton(onPressed: _addTemp, child: const Text('Add Temp Amount')),
            const SizedBox(height: 16),
            _sectionTitle('Closing Totals (All Time)'),
            _kpiGrid([
              ('Customer Total', _n(r.customerTotal)),
              ('Dealer Total', _n(r.dealerTotal)),
              ('Balance', _n(r.balance)),
            ]),
            const SizedBox(height: 16),
            _sideList('Receivable', r.receivables, AppColors.success),
            const SizedBox(height: 12),
            _sideList('Payable', r.payables, AppColors.danger),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: GoogleFonts.manrope(color: AppColors.gold, fontWeight: FontWeight.w800, fontSize: 15)),
      );

  Widget _netCard(double net) {
    final positive = net >= 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: (positive ? AppColors.success : AppColors.danger).withValues(alpha: 0.5)),
        color: AppColors.panel.withValues(alpha: 0.95),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(positive ? 'NET PROFIT' : 'NET LOSS', style: TextStyle(color: positive ? AppColors.success : AppColors.danger, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(_n(net.abs()), style: GoogleFonts.manrope(color: AppColors.gold, fontSize: 28, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _kpiGrid(List<(String, String)> items) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items
          .map(
            (e) => Container(
              width: (MediaQuery.of(context).size.width - 48) / 2,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: AppColors.panel.withValues(alpha: 0.9),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.$1, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                  const SizedBox(height: 4),
                  Text(e.$2, style: GoogleFonts.manrope(color: AppColors.cream, fontWeight: FontWeight.w800, fontSize: 15)),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _sideList(String title, List<ClosingNamedAmount> items, Color accent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        color: AppColors.panel.withValues(alpha: 0.88),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: accent, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (items.isEmpty)
            const Text('—', style: TextStyle(color: AppColors.muted))
          else
            ...items.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.isTemp ? '[Temp] ${e.name}' : e.name,
                        style: const TextStyle(color: AppColors.cream, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(_n(e.amount, d: 0), style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 12)),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () => _remove(e),
                      icon: const Icon(Icons.close_rounded, color: AppColors.danger, size: 18),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
