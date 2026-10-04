import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/models.dart';
import '../services/report_totals.dart';
import '../theme/app_theme.dart';

class VipBalanceBanner extends StatelessWidget {
  const VipBalanceBanner({
    super.key,
    required this.title,
    required this.lines,
  });

  final String title;
  final List<(String, String)> lines;

  factory VipBalanceBanner.customer(CustomerLedgerSummary s, {String title = 'Customer Balance'}) {
    return VipBalanceBanner(
      title: title,
      lines: [
        ('Total Amount', s.totalAmount.toStringAsFixed(0)),
        ('Total Credit', s.totalCredit.toStringAsFixed(0)),
        ('Balance', s.balance.toStringAsFixed(0)),
      ],
    );
  }

  factory VipBalanceBanner.dealer(DealerLedgerSummary s, {String title = 'Dealer Balance'}) {
    return VipBalanceBanner(
      title: title,
      lines: [
        ('DDAmount', s.ddAmount.toStringAsFixed(0)),
        ('DAmount', s.dAmount.toStringAsFixed(0)),
        ('Balance', s.balance.toStringAsFixed(0)),
      ],
    );
  }

  /// WinForms Stock jaisa: Add / Minus / Baqaya litter (paisa nahi)
  factory VipBalanceBanner.stockLitter(StockSummaryTotals t, {String title = 'Stock Litter'}) {
    return VipBalanceBanner(
      title: title,
      lines: [
        ('Add Litter', t.addLitter.toStringAsFixed(2)),
        ('Minus Litter', t.minusLitter.toStringAsFixed(2)),
        ('Baqaya', t.baqayaLitter.toStringAsFixed(2)),
      ],
    );
  }

  factory VipBalanceBanner.bulMal(BulMalSummary s, {String title = 'Bul Mal'}) {
    return VipBalanceBanner(
      title: title,
      lines: [
        ('In', s.totalIn.toStringAsFixed(0)),
        ('Out', s.totalOut.toStringAsFixed(0)),
        ('Balance', s.balance.toStringAsFixed(0)),
      ],
    );
  }

  /// Total Litter · Total Amount (Σ L×R) · Avg Rate = Amount / Litter
  factory VipBalanceBanner.litterAvg({
    required String title,
    required double litterSum,
    required double amountSum,
  }) {
    final avg = litterSum == 0 ? 0.0 : amountSum / litterSum;
    return VipBalanceBanner(
      title: title,
      lines: [
        ('Total Litter', litterSum.toStringAsFixed(2)),
        ('Total Amount', amountSum.toStringAsFixed(0)),
        ('Avg Rate', avg.toStringAsFixed(2)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
        gradient: LinearGradient(
          colors: [
            AppColors.panel.withValues(alpha: 0.98),
            AppColors.navy.withValues(alpha: 0.9),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.manrope(color: AppColors.gold, fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 8),
          Row(
            children: lines
                .map(
                  (e) => Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.$1, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                        const SizedBox(height: 2),
                        Text(e.$2, style: GoogleFonts.manrope(color: AppColors.cream, fontWeight: FontWeight.w800, fontSize: 15)),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class VipSearchDropdown<T extends Object> extends StatefulWidget {
  const VipSearchDropdown({
    super.key,
    required this.label,
    required this.items,
    required this.displayString,
    required this.onSelected,
    this.value,
    this.hint = 'Type to search...',
    this.allowClear = false,
  });

  final String label;
  final List<T> items;
  final T? value;
  final String Function(T) displayString;
  final ValueChanged<T?> onSelected;
  final String hint;
  final bool allowClear;

  @override
  State<VipSearchDropdown<T>> createState() => _VipSearchDropdownState<T>();
}

class _VipSearchDropdownState<T extends Object> extends State<VipSearchDropdown<T>> {
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.value == null ? '' : widget.displayString(widget.value as T),
    );
  }

  @override
  void didUpdateWidget(covariant VipSearchDropdown<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.value == null ? '' : widget.displayString(widget.value as T);
    if (_controller.text != next && !_focus.hasFocus) {
      _controller.text = next;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Iterable<T> _filter(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) return widget.items;
    final matched = widget.items.where((e) => widget.displayString(e).toLowerCase().contains(query)).toList();
    matched.sort((a, b) {
      final an = widget.displayString(a).toLowerCase();
      final bn = widget.displayString(b).toLowerCase();
      final ae = an == query ? 0 : (an.startsWith(query) ? 1 : 2);
      final be = bn == query ? 0 : (bn.startsWith(query) ? 1 : 2);
      if (ae != be) return ae.compareTo(be);
      return an.compareTo(bn);
    });
    return matched;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RawAutocomplete<T>(
        textEditingController: _controller,
        focusNode: _focus,
        displayStringForOption: widget.displayString,
        optionsBuilder: (value) => _filter(value.text),
        onSelected: (item) {
          widget.onSelected(item);
          _controller.text = widget.displayString(item);
        },
        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            style: const TextStyle(color: AppColors.cream),
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              suffixIcon: widget.allowClear && controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: AppColors.muted, size: 18),
                      onPressed: () {
                        controller.clear();
                        widget.onSelected(null);
                        setState(() {});
                      },
                    )
                  : const Icon(Icons.search, color: AppColors.gold),
            ),
            onChanged: (_) {
              final typed = controller.text.trim();
              if (typed.isEmpty) {
                if (widget.value != null) widget.onSelected(null);
                setState(() {});
                return;
              }
              // Exact typed name → auto select (haji ≠ haji nazar)
              T? exact;
              for (final item in widget.items) {
                if (widget.displayString(item).toLowerCase() == typed.toLowerCase()) {
                  exact = item;
                  break;
                }
              }
              if (exact != null) {
                if (widget.value != exact) widget.onSelected(exact);
              } else if (widget.value != null) {
                final current = widget.displayString(widget.value as T);
                if (typed != current) widget.onSelected(null);
              }
              setState(() {});
            },
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          final list = options.toList();
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              color: AppColors.panel,
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220, minWidth: 280),
                child: list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('No match', style: TextStyle(color: AppColors.muted)),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final item = list[i];
                          return ListTile(
                            dense: true,
                            title: Text(widget.displayString(item), style: const TextStyle(color: AppColors.cream)),
                            onTap: () => onSelected(item),
                          );
                        },
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}
