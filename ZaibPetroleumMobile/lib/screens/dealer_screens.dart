import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../data/app_database.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../utils/form_utils.dart';
import '../widgets/sync_aware_reload.dart';
import '../widgets/vip_balance_search.dart';
import '../widgets/vip_widgets.dart';

// ===================== ADD DEALER =====================

class DealerListScreen extends StatefulWidget {
  const DealerListScreen({super.key});

  @override
  State<DealerListScreen> createState() => _DealerListScreenState();
}

class _DealerListScreenState extends State<DealerListScreen> with SyncAwareReload {
  final _search = TextEditingController();
  List<Dealer> _items = [];
  List<String> _nameSuggestions = [];
  DealerLedgerSummary? _totals;
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
    final allDealers = await AppDatabase.instance.getDealers();
    final rows = await AppDatabase.instance.getDealers(query: _search.text);
    final matched = await AppDatabase.instance.findDealerByExactName(_search.text);
    final byName = matched?.id == null ? null : await AppDatabase.instance.getDealerLedgerSummary(matched!.id!);
    final totals = byName ?? await AppDatabase.instance.getGlobalDealerLedger();
    if (!mounted || !isLoadCurrent(gen)) return;
    setState(() {
      _items = rows;
      _totals = totals;
      _matchedName = matched?.name;
      _nameSuggestions = allDealers.map((d) => d.name).where((n) => n.trim().isNotEmpty).toList();
      _loading = false;
      _initial = false;
    });
  }

  Future<void> _open({Dealer? item}) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => DealerFormScreen(dealer: item)),
    );
    if (ok == true) _load(showSpinner: true);
  }

  @override
  Widget build(BuildContext context) {
    return VipScaffold(
      title: 'Add Dealer',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.add_business),
        label: const Text('Add Dealer'),
      ),
      child: Column(
        children: [
          if (_totals != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: VipBalanceBanner.dealer(
                _totals!,
                title: _matchedName != null ? 'Dealer: $_matchedName' : 'All Dealers',
              ),
            ),
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
                    ? const EmptyState(message: 'Abhi koi dealer nahi.\nAdd Dealer se pehla dealer banayein.')
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final d = _items[i];
                          return _VipCard(
                            onTap: () => _open(item: d),
                            onLongPress: () async {
                              if (!await confirmDelete(context, '${d.name} delete?')) return;
                              try {
                                await AppDatabase.instance.deleteDealer(d.id!);
                                _load(showSpinner: true);
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                              }
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(d.name, style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16)),
                                const SizedBox(height: 4),
                                Text('DDAmount ${d.ddAmount.toStringAsFixed(0)}  |  DAmount ${d.dAmount.toStringAsFixed(0)}',
                                    style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                Text('Balance (DD-D): ${d.creditBalance.toStringAsFixed(0)}',
                                    style: const TextStyle(color: AppColors.goldSoft, fontSize: 12)),
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

class DealerFormScreen extends StatefulWidget {
  const DealerFormScreen({super.key, this.dealer});
  final Dealer? dealer;

  @override
  State<DealerFormScreen> createState() => _DealerFormScreenState();
}

class _DealerFormScreenState extends State<DealerFormScreen> {
  final _name = TextEditingController();
  final _dd = TextEditingController();
  final _d = TextEditingController();
  final _date = TextEditingController();
  bool _saving = false;
  bool get _edit => widget.dealer?.id != null;

  @override
  void initState() {
    super.initState();
    final d = widget.dealer;
    _name.text = d?.name ?? '';
    _dd.text = d == null ? '' : fmtNum(d.ddAmount);
    _d.text = d == null ? '0' : fmtNum(d.dAmount);
    _date.text = d?.date ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
  }

  @override
  void dispose() {
    _name.dispose();
    _dd.dispose();
    _d.dispose();
    _date.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dealer name zaroori hai')));
      return;
    }
    await runVipSave(
      context: context,
      setSaving: (v) { if (mounted) setState(() => _saving = v); },
      action: () async {
        final model = Dealer(
          id: widget.dealer?.id,
          name: _name.text.trim(),
          ddAmount: parseNum(_dd),
          dAmount: parseNum(_d),
          date: _date.text.trim(),
        );
        if (_edit) {
          await AppDatabase.instance.updateDealer(model);
        } else {
          await AppDatabase.instance.insertDealer(model);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dd = parseNum(_dd);
    final d = parseNum(_d);
    final summary = DealerLedgerSummary(ddAmount: dd, dAmount: d, balance: dd - d);
    return VipScaffold(
      title: _edit ? 'Edit Dealer' : 'Add Dealer',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text('Zaib Petroleum Service', style: GoogleFonts.cinzel(color: AppColors.goldSoft, fontSize: 13)),
          const SizedBox(height: 10),
          VipBalanceBanner.dealer(summary),
          VipField(label: 'Dealer Name *', controller: _name),
          VipField(label: 'DDAmount (Owed)', controller: _dd, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {})),
          VipField(label: 'DAmount (Paid)', controller: _d, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {})),
          VipField(label: 'Date', controller: _date, readOnly: true, onTap: () => pickVipDate(context, _date), suffix: const Icon(Icons.calendar_month, color: AppColors.gold)),
          ElevatedButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving...' : 'Save Dealer')),
        ],
      ),
    );
  }
}

class _VipCard extends StatelessWidget {
  const _VipCard({required this.child, this.onTap, this.onLongPress});
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
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
}
