import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../data/app_database.dart';
import '../theme/app_theme.dart';
import '../widgets/vip_widgets.dart';

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  Map<String, int> _counts = {};
  String? _dbPath;
  bool _loading = true;
  bool _busy = false;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final path = await AppDatabase.instance.databasePath;
      final counts = await AppDatabase.instance.countMainTables();
      if (!mounted) return;
      setState(() {
        _dbPath = path;
        _counts = counts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'DB open error: $e';
      });
    }
  }

  Future<void> _restoreAnyBackup({required bool fromPc}) async {
    final file = await FilePicker.pickFile(
      dialogTitle: fromPc ? 'Select PC DiselPetrolPump backup (.db)' : 'Select Mobile/PC .db to restore',
      type: FileType.any,
    );
    if (file == null) return;

    final path = file.path;
    if (path == null || path.isEmpty) {
      if (!mounted) return;
      setState(() => _message = 'File path nahi mila.');
      return;
    }

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: Text(fromPc ? 'PC → Mobile Restore' : 'Restore Backup', style: const TextStyle(color: AppColors.gold)),
        content: const Text(
          'Current mobile data replace ho jayegi.\nDiselPetrolPump .db file select ki hai?',
          style: TextStyle(color: AppColors.cream),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restore Now')),
        ],
      ),
    );
    if (confirm != true) return;

    if (!mounted) return;
    setState(() {
      _busy = true;
      _message = 'Restoring...';
    });
    try {
      await AppDatabase.instance.restoreFromFile(path);
      await _refresh();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = fromPc
            ? 'PC backup restore ho gaya — saari entries mobile pe aa gayi.'
            : 'Backup restore ho gaya.';
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Restore successful')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Restore fail: $e';
      });
    }
  }

  Future<void> _backupAndShareToPc() async {
    setState(() {
      _busy = true;
      _message = 'Mobile backup bana raha hai...';
    });
    try {
      final path = await AppDatabase.instance.createBackupCopy();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message =
            'Mobile backup ready:\n$path\n\nAb share sheet se PC/Drive/WhatsApp pe bhej dein.\nPC pe usi .db ko Restore kar dein.';
      });
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: 'application/octet-stream')],
          text: 'Zaib Petroleum Mobile backup (DiselPetrolPump) — PC pe restore karein',
          subject: 'DiselPetrolPump Mobile Backup',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Backup/Share fail: $e';
      });
    }
  }

  Future<void> _saveBackupOnly() async {
    setState(() {
      _busy = true;
      _message = 'Backup bana raha hai...';
    });
    try {
      final path = await AppDatabase.instance.createBackupCopy();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Backup saved:\n$path';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Backup fail: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return VipScaffold(
      title: 'Backup / Restore',
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text('Zaib Petroleum Service', style: GoogleFonts.cinzel(color: AppColors.goldSoft, fontSize: 13)),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.gold.withValues(alpha: 0.25)),
                    color: AppColors.panel.withValues(alpha: 0.9),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Current DB', style: GoogleFonts.manrope(color: AppColors.gold, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(_dbPath ?? '-', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      const SizedBox(height: 12),
                      ..._counts.entries.map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('${e.key}: ${e.value}', style: const TextStyle(color: AppColors.cream, fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _busy ? null : () => _restoreAnyBackup(fromPc: true),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('PC → Mobile Restore (.db)'),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _busy ? null : _backupAndShareToPc,
                  icon: const Icon(Icons.share),
                  label: const Text('Mobile → PC Share Backup'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _saveBackupOnly,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.gold,
                    side: const BorderSide(color: AppColors.gold),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  ),
                  icon: const Icon(Icons.download),
                  label: const Text('Save Mobile Backup Only'),
                ),
                const SizedBox(height: 16),
                if (_busy) const LinearProgressIndicator(color: AppColors.gold),
                if (_message.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(_message, style: const TextStyle(color: AppColors.goldSoft, height: 1.35)),
                ],
                const SizedBox(height: 18),
                const Text(
                  'PC pe restore:\n'
                  '1) Mobile se Share Backup karein\n'
                  '2) PC pe file save karein\n'
                  '3) PC software → Backup And Restore → Restore\n'
                  '4) Same DiselPetrolPump.db entries aa jayengi',
                  style: TextStyle(color: AppColors.muted, height: 1.45, fontSize: 13),
                ),
              ],
            ),
    );
  }
}
