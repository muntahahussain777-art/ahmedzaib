import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../data/app_database.dart';
import '../models/models.dart';
import '../services/vip_export_service.dart';
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

// ===================== BUL MAL OWNERS =====================

class BulMalOwnerListScreen extends StatefulWidget {
  const BulMalOwnerListScreen({super.key});

  @override
  State<BulMalOwnerListScreen> createState() => _BulMalOwnerListScreenState();
}

class _BulMalOwnerListScreenState extends State<BulMalOwnerListScreen> {
  final _search = TextEditingController();
  List<BulMalOwner> _items = [];
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
    final rows = await AppDatabase.instance.getBulMalOwners(query: _search.text);
    if (!mounted) return;
    setState(() {
      _items = rows;
      _loading = false;
    });
  }

  Future<void> _openForm({BulMalOwner? owner}) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => BulMalOwnerFormScreen(owner: owner)),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return VipScaffold(
      title: 'Bul Mal Owners',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Add Owner'),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => _load(),
              decoration: const InputDecoration(
                hintText: 'Owner name search',
                prefixIcon: Icon(Icons.search, color: AppColors.gold),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
                : _items.isEmpty
                    ? const EmptyState(message: 'Pehle Bul Mal owner banao.\nSirf name likhein.')
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final o = _items[i];
                          return _card(
                            onTap: () => _openForm(owner: o),
                            onLongPress: () async {
                              if (!await confirmDelete(context, 'Owner delete?')) return;
                              try {
                                await AppDatabase.instance.deleteBulMalOwner(o.id!);
                                _load();
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                              }
                            },
                            child: Text(o.name, style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16)),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class BulMalOwnerFormScreen extends StatefulWidget {
  const BulMalOwnerFormScreen({super.key, this.owner});
  final BulMalOwner? owner;

  @override
  State<BulMalOwnerFormScreen> createState() => _BulMalOwnerFormScreenState();
}

class _BulMalOwnerFormScreenState extends State<BulMalOwnerFormScreen> {
  final _name = TextEditingController();
  bool _saving = false;
  bool get _edit => widget.owner?.id != null;

  @override
  void initState() {
    super.initState();
    _name.text = widget.owner?.name ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Owner name likhein')));
      return;
    }
    await runVipSave(
      context: context,
      setSaving: (v) {
        if (mounted) setState(() => _saving = v);
      },
      action: () async {
        final model = BulMalOwner(
          id: widget.owner?.id,
          name: name,
          date: widget.owner?.date ?? DateFormat('yyyy-MM-dd').format(DateTime.now()),
        );
        if (_edit) {
          await AppDatabase.instance.updateBulMalOwner(model);
        } else {
          await AppDatabase.instance.insertBulMalOwner(model);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return VipScaffold(
      title: _edit ? 'Edit Owner' : 'Add Bul Mal Owner',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          VipField(label: 'Owner Name *', controller: _name, hint: 'Name likhein'),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving...' : 'Save Owner'),
          ),
        ],
      ),
    );
  }
}

// ===================== BUL MAL ENTRIES =====================

class BulMalListScreen extends StatefulWidget {
  const BulMalListScreen({super.key});

  @override
  State<BulMalListScreen> createState() => _BulMalListScreenState();
}

class _BulMalListScreenState extends State<BulMalListScreen> {
  final _search = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();
  List<BulMalEntry> _items = [];
  BulMalSummary? _summary;
  BulMalOwner? _matchedOwner;
  bool _loading = true;
  bool _exporting = false;

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
    final matched = await AppDatabase.instance.findBulMalOwnerByExactName(_search.text);
    final rows = await AppDatabase.instance.getBulMalEntries(
      query: matched == null ? _search.text : '',
      ownerId: matched?.id,
      from: _from.text.trim().isEmpty ? null : _from.text.trim(),
      to: _to.text.trim().isEmpty ? null : _to.text.trim(),
    );
    final summary = await AppDatabase.instance.getBulMalSummary(
      ownerId: matched?.id,
      from: _from.text.trim().isEmpty ? null : _from.text.trim(),
      to: _to.text.trim().isEmpty ? null : _to.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _items = rows;
      _summary = summary;
      _matchedOwner = matched;
      _loading = false;
    });
  }

  Future<void> _open({BulMalEntry? item}) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => BulMalFormScreen(entry: item)),
    );
    if (ok == true) _load();
  }

  Future<void> _exportVip() async {
    if (_items.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final title = _matchedOwner == null ? 'Bul Mal Report' : 'Bul Mal — ${_matchedOwner!.name}';
      final path = await VipExportService.bulMalPdf(
        title: title,
        rows: _items,
        summary: _summary ?? const BulMalSummary(totalIn: 0, totalOut: 0, balance: 0),
        subtitle: '${_from.text} → ${_to.text}'.trim().isEmpty ? null : 'From ${_from.text}  To ${_to.text}',
      );
      await VipExportService.shareFile(path, subject: title);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return VipScaffold(
      title: 'Bul Mal',
      actions: [
        IconButton(
          tooltip: 'Owners',
          onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const BulMalOwnerListScreen()));
            _load();
          },
          icon: const Icon(Icons.people_outline, color: AppColors.gold),
        ),
        IconButton(
          tooltip: 'VIP PDF',
          onPressed: _exporting || _items.isEmpty ? null : _exportVip,
          icon: Icon(Icons.picture_as_pdf_outlined, color: _items.isEmpty ? AppColors.muted : AppColors.gold),
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.add),
        label: const Text('Add Entry'),
      ),
      child: Column(
        children: [
          if (_summary != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: VipBalanceBanner.bulMal(
                _summary!,
                title: _matchedOwner == null ? 'Bul Mal Totals' : 'Owner: ${_matchedOwner!.name}',
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
                    hintText: 'Exact owner name / note',
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
                    ? const EmptyState(message: 'Pehle Owner banao (top people icon),\nphir In/Out entries add karein.')
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final e = _items[i];
                          return _card(
                            onTap: () => _open(item: e),
                            onLongPress: () async {
                              if (!await confirmDelete(context, 'Bul Mal entry delete?')) return;
                              await AppDatabase.instance.deleteBulMalEntry(e.id!);
                              _load();
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        e.ownerName,
                                        style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16),
                                      ),
                                    ),
                                    Text(
                                      '${e.type} ${e.amount.toStringAsFixed(0)}',
                                      style: TextStyle(
                                        color: e.isOut ? AppColors.danger : AppColors.success,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  e.date,
                                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                                ),
                                if (e.note.trim().isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(e.note, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                                ],
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

class BulMalFormScreen extends StatefulWidget {
  const BulMalFormScreen({super.key, this.entry});
  final BulMalEntry? entry;

  @override
  State<BulMalFormScreen> createState() => _BulMalFormScreenState();
}

class _BulMalFormScreenState extends State<BulMalFormScreen> {
  final _date = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  List<BulMalOwner> _owners = [];
  BulMalOwner? _selected;
  BulMalSummary? _summary;
  String _type = 'In';
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
    final owners = await AppDatabase.instance.getBulMalOwners();
    final e = widget.entry;
    _date.text = e?.date ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
    _amount.text = e == null ? '' : fmtNum(e.amount);
    _note.text = e?.note ?? '';
    _type = e?.type ?? 'In';
    BulMalOwner? selected;
    if (e != null) {
      for (final o in owners) {
        if (o.id == e.ownerId) {
          selected = o;
          break;
        }
      }
    }
    BulMalSummary? summary;
    if (selected?.id != null) {
      summary = await AppDatabase.instance.getBulMalSummary(ownerId: selected!.id);
    }
    if (!mounted) return;
    setState(() {
      _owners = owners;
      _selected = selected;
      _summary = summary;
      _loading = false;
    });
  }

  Future<void> _onOwnerSelected(BulMalOwner? o) async {
    setState(() {
      _selected = o;
      _summary = null;
    });
    if (o?.id == null) return;
    final summary = await AppDatabase.instance.getBulMalSummary(ownerId: o!.id);
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
    if (_selected?.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pehle owner select karein')));
      return;
    }
    if (parseNum(_amount) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Amount likhein')));
      return;
    }
    await runVipSave(
      context: context,
      setSaving: (v) {
        if (mounted) setState(() => _saving = v);
      },
      popOnSuccess: _edit,
      action: () async {
        final model = BulMalEntry(
          id: widget.entry?.id,
          ownerId: _selected!.id!,
          ownerName: _selected!.name,
          date: _date.text.trim(),
          type: _type,
          amount: parseNum(_amount),
          note: _note.text.trim(),
        );
        if (_edit) {
          await AppDatabase.instance.updateBulMalEntry(model);
        } else {
          await AppDatabase.instance.insertBulMalEntry(model);
        }
      },
    ).then((ok) async {
      if (!ok || _edit || !mounted) return;
      _savedInSession = true;
      _amount.clear();
      _note.clear();
      // Owner + date + type same rahen (WinForms jaisa)
      final summary = await AppDatabase.instance.getBulMalSummary(ownerId: _selected!.id);
      if (mounted) setState(() => _summary = summary);
    });
  }

  @override
  Widget build(BuildContext context) {
    return keepOpenPopScope(
      context: context,
      savedInSession: _savedInSession,
      isEdit: _edit,
      child: VipScaffold(
        title: _edit ? 'Edit Bul Mal' : 'Bul Mal Entry',
        backResult: _edit || _savedInSession,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  if (_summary != null)
                    VipBalanceBanner.bulMal(
                      _summary!,
                      title: _selected == null ? 'Bul Mal' : 'Owner: ${_selected!.name}',
                    ),
                  if (_owners.isEmpty) ...[
                    const Text(
                      'Pehle top pe Owners se name banao.',
                      style: TextStyle(color: AppColors.danger),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const BulMalOwnerListScreen()));
                        final owners = await AppDatabase.instance.getBulMalOwners();
                        if (!mounted) return;
                        setState(() => _owners = owners);
                      },
                      icon: const Icon(Icons.people_outline, color: AppColors.gold),
                      label: const Text('Add Owners', style: TextStyle(color: AppColors.gold)),
                    ),
                    const SizedBox(height: 12),
                  ],
                  VipSearchDropdown<BulMalOwner>(
                    label: 'Owner *',
                    items: _owners,
                    value: _selected,
                    displayString: (o) => o.name,
                    onSelected: _onOwnerSelected,
                  ),
                  VipField(
                    label: 'Date',
                    controller: _date,
                    readOnly: true,
                    onTap: () => pickVipDate(context, _date),
                    suffix: const Icon(Icons.calendar_month, color: AppColors.gold),
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey(_type),
                    initialValue: _type,
                    dropdownColor: AppColors.panel,
                    decoration: const InputDecoration(labelText: 'In / Out *'),
                    items: const [
                      DropdownMenuItem(value: 'In', child: Text('In')),
                      DropdownMenuItem(value: 'Out', child: Text('Out')),
                    ],
                    onChanged: (v) => setState(() => _type = v ?? 'In'),
                  ),
                  const SizedBox(height: 12),
                  VipField(
                    label: 'Amount *',
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  VipField(label: 'Note', controller: _note, maxLines: 2),
                  ElevatedButton(
                    onPressed: _saving || _owners.isEmpty ? null : _save,
                    child: Text(_saving ? 'Saving...' : 'Save Entry'),
                  ),
                ],
              ),
      ),
    );
  }
}
