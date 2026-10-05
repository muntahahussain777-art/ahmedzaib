import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/app_database.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/sync_aware_reload.dart';
import '../widgets/vip_balance_search.dart';
import '../widgets/vip_widgets.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SyncAwareReload {
  DashboardStats? _stats;
  bool _loading = true;
  int? _year;
  int? _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _load();
  }

  @override
  Future<void> reloadAfterSync() => _load(showSpinner: false);

  Future<void> _load({bool showSpinner = true}) async {
    final gen = bumpLoadGeneration();
    if (showSpinner && mounted) setState(() => _loading = true);
    final stats = await AppDatabase.instance.getDashboardStats(year: _year, month: _month);
    if (!mounted || !isLoadCurrent(gen)) return;
    setState(() {
      _stats = stats;
      _loading = false;
    });
  }

  List<int> get _years {
    final y = DateTime.now().year;
    return [for (var i = y; i >= y - 8; i--) i];
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    return VipScaffold(
      title: 'Dashboard',
      child: _loading && s == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                Text('ZAIB PETROLEUM SERVICE', style: GoogleFonts.cinzel(color: AppColors.gold, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        initialValue: _year,
                        dropdownColor: AppColors.panel,
                        decoration: const InputDecoration(labelText: 'Year'),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('All Years')),
                          ..._years.map((y) => DropdownMenuItem<int?>(value: y, child: Text('$y'))),
                        ],
                        onChanged: (v) {
                          setState(() => _year = v);
                          _load();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        initialValue: _month,
                        dropdownColor: AppColors.panel,
                        decoration: const InputDecoration(labelText: 'Month'),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('All Months')),
                          for (var m = 1; m <= 12; m++)
                            DropdownMenuItem<int?>(value: m, child: Text(m.toString().padLeft(2, '0'))),
                        ],
                        onChanged: (v) {
                          setState(() => _month = v);
                          _load();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (s != null) ...[
                  VipBalanceBanner.customer(s.customer, title: 'Customer Totals'),
                  VipBalanceBanner(
                    title: 'Dealer Totals',
                    lines: [
                      ('Total Amount', s.dealer.ddAmount.toStringAsFixed(0)),
                      ('Total Credit', s.dealer.dAmount.toStringAsFixed(0)),
                      ('Balance', s.dealer.balance.toStringAsFixed(0)),
                    ],
                  ),
                  _metricCard('Sale Litter', s.saleLitter.toStringAsFixed(2), 'Purchase Litter', s.purchaseLitter.toStringAsFixed(2)),
                  _metricCard('Sale Amount', s.saleAmount.toStringAsFixed(0), 'Purchase Amount', s.purchaseAmount.toStringAsFixed(0)),
                  const SizedBox(height: 8),
                  Text('Litter Graph', style: GoogleFonts.manrope(color: AppColors.gold, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  _BarChart(
                    aLabel: 'Sale',
                    aValue: s.saleLitter,
                    bLabel: 'Purchase',
                    bValue: s.purchaseLitter,
                  ),
                  const SizedBox(height: 18),
                  Text('Amount Graph', style: GoogleFonts.manrope(color: AppColors.gold, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  _BarChart(
                    aLabel: 'Sale',
                    aValue: s.saleAmount,
                    bLabel: 'Purchase',
                    bValue: s.purchaseAmount,
                  ),
                ],
              ],
            ),
    );
  }

  Widget _metricCard(String aTitle, String aVal, String bTitle, String bVal) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.28)),
        color: AppColors.panel.withValues(alpha: 0.92),
      ),
      child: Row(
        children: [
          Expanded(child: _pair(aTitle, aVal)),
          Expanded(child: _pair(bTitle, bVal)),
        ],
      ),
    );
  }

  Widget _pair(String t, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(v, style: GoogleFonts.manrope(color: AppColors.cream, fontWeight: FontWeight.w800, fontSize: 16)),
        ],
      );
}

class _BarChart extends StatelessWidget {
  const _BarChart({
    required this.aLabel,
    required this.aValue,
    required this.bLabel,
    required this.bValue,
  });

  final String aLabel;
  final double aValue;
  final String bLabel;
  final double bValue;

  @override
  Widget build(BuildContext context) {
    final max = [aValue, bValue, 1.0].reduce((x, y) => x > y ? x : y);
    return Container(
      height: 180,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.28)),
        color: AppColors.panel.withValues(alpha: 0.92),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: _bar(aLabel, aValue, max, AppColors.gold)),
          const SizedBox(width: 22),
          Expanded(child: _bar(bLabel, bValue, max, AppColors.goldSoft)),
        ],
      ),
    );
  }

  Widget _bar(String label, double value, double max, Color color) {
    final h = (value / max) * 120;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(value.toStringAsFixed(value >= 100 ? 0 : 1), style: const TextStyle(color: AppColors.cream, fontSize: 12)),
        const SizedBox(height: 6),
        AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          height: h.clamp(6, 120),
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [color.withValues(alpha: 0.95), color.withValues(alpha: 0.45)],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      ],
    );
  }
}
