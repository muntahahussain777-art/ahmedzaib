import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../data/app_database.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../utils/form_utils.dart';
import '../widgets/sync_aware_reload.dart';
import '../widgets/vip_widgets.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> with SyncAwareReload {
  final _search = TextEditingController();
  List<Customer> _items = [];
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
    final rows = await AppDatabase.instance.getCustomers(query: _search.text);
    if (!mounted || !isLoadCurrent(gen)) return;
    setState(() {
      _items = rows;
      _loading = false;
    });
  }

  Future<void> _openForm({Customer? customer}) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CustomerFormScreen(customer: customer)),
    );
    if (changed == true) _load();
  }

  Future<void> _delete(Customer c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Delete Customer?', style: TextStyle(color: AppColors.gold)),
        content: Text('${c.name} delete karna hai?', style: const TextStyle(color: AppColors.cream)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok != true || c.id == null) return;
    try {
      await AppDatabase.instance.deleteCustomer(c.id!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Customer delete ho gaya')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return VipScaffold(
      title: 'Customers',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add Customer'),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => _load(),
              decoration: const InputDecoration(
                hintText: 'Search name / mobile',
                prefixIcon: Icon(Icons.search, color: AppColors.gold),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
                : _items.isEmpty
                    ? const EmptyState(message: 'Abhi koi customer nahi.\nAdd Customer se pehla record banayein.')
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final c = _items[i];
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () => _openForm(customer: c),
                              onLongPress: () => _delete(c),
                              child: Ink(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.22)),
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.panel.withValues(alpha: 0.95),
                                      AppColors.navy.withValues(alpha: 0.85),
                                    ],
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: AppColors.gold.withValues(alpha: 0.18),
                                        child: Text(
                                          c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                                          style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(c.name, style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 16)),
                                            const SizedBox(height: 4),
                                            Text(c.mobile.isEmpty ? 'No mobile' : c.mobile, style: const TextStyle(color: AppColors.muted)),
                                            Text(c.date, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.edit_outlined, color: AppColors.goldSoft, size: 20),
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

class CustomerFormScreen extends StatefulWidget {
  const CustomerFormScreen({super.key, this.customer});

  final Customer? customer;

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _date = TextEditingController();
  bool _saving = false;

  bool get _isEdit => widget.customer?.id != null;

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    _name.text = c?.name ?? '';
    _mobile.text = c?.mobile ?? '';
    _date.text = c?.date ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
  }

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _date.dispose();
    super.dispose();
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
    if (picked != null) {
      _date.text = DateFormat('yyyy-MM-dd').format(picked);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name zaroori hai')));
      return;
    }
    await runVipSave(
      context: context,
      setSaving: (v) { if (mounted) setState(() => _saving = v); },
      action: () async {
        final model = Customer(
          id: widget.customer?.id,
          name: name,
          mobile: _mobile.text.trim(),
          date: _date.text.trim(),
        );
        if (_isEdit) {
          await AppDatabase.instance.updateCustomer(model);
        } else {
          await AppDatabase.instance.insertCustomer(model);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return VipScaffold(
      title: _isEdit ? 'Edit Customer' : 'Add Customer',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Zaib Petroleum Service',
            style: GoogleFonts.cinzel(color: AppColors.goldSoft, fontSize: 13, letterSpacing: 1.1),
          ),
          const SizedBox(height: 18),
          VipField(label: 'Name *', controller: _name, hint: 'Customer name'),
          VipField(
            label: 'Mobile',
            controller: _mobile,
            hint: '03xx-xxxxxxx',
            keyboardType: TextInputType.phone,
          ),
          VipField(
            label: 'Date',
            controller: _date,
            readOnly: true,
            onTap: _pickDate,
            suffix: const Icon(Icons.calendar_month, color: AppColors.gold),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving...' : 'Save Customer'),
            ),
          ),
        ],
      ),
    );
  }
}
