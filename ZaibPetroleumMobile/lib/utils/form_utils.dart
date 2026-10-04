import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

Future<void> pickVipDate(BuildContext context, TextEditingController controller) async {
  final now = DateTime.now();
  final initial = DateTime.tryParse(controller.text) ?? now;
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
    controller.text = DateFormat('yyyy-MM-dd').format(picked);
  }
}

double parseNum(TextEditingController c) =>
    double.tryParse(c.text.trim().replaceAll(',', '')) ?? 0;

String fmtNum(double v) {
  if (v == 0) return '';
  return v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
}

Future<bool> confirmDelete(BuildContext context, String message) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.panel,
      title: const Text('Delete?', style: TextStyle(color: AppColors.gold)),
      content: Text(message, style: const TextStyle(color: AppColors.cream)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Save pe "Saving..." stuck na ho — error pe message, finally pe unlock.
/// [popOnSuccess]=false → WinForms jaisa: form open rahe, naam/date same.
Future<bool> runVipSave({
  required BuildContext context,
  required void Function(bool saving) setSaving,
  required Future<void> Function() action,
  bool popOnSuccess = true,
  String savedMessage = 'Saved',
}) async {
  setSaving(true);
  try {
    await action();
    if (!context.mounted) return false;
    if (popOnSuccess) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(savedMessage), duration: const Duration(milliseconds: 900)),
      );
    }
    return true;
  } catch (e) {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Save fail: $e')),
    );
    return false;
  } finally {
    if (context.mounted) setSaving(false);
  }
}

/// System back pe list refresh (continuous save session).
Widget keepOpenPopScope({
  required BuildContext context,
  required bool savedInSession,
  required bool isEdit,
  required Widget child,
}) {
  return PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) return;
      Navigator.of(context).pop(isEdit || savedInSession);
    },
    child: child,
  );
}
