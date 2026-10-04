import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/vip_widgets.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  final _user = TextEditingController();
  bool _bioOn = false;
  bool _bioAvailable = false;
  bool _busy = false;
  String _message = '';
  String _username = 'admin';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final u = await AuthService.instance.getUsername();
    final bio = await AuthService.instance.fingerprintEnabled;
    final avail = await AuthService.instance.canUseFingerprint();
    if (!mounted) return;
    setState(() {
      _username = u;
      _user.text = u;
      _bioOn = bio;
      _bioAvailable = avail;
    });
  }

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    _user.dispose();
    super.dispose();
  }

  Future<void> _savePassword() async {
    final newPass = _next.text.trim();
    final confirm = _confirm.text.trim();
    if (newPass.isNotEmpty && newPass != confirm) {
      setState(() => _message = 'New + Confirm password same hone chahiye');
      return;
    }
    if (newPass.isEmpty && _user.text.trim() == _username) {
      setState(() => _message = 'Naya password ya username change karein');
      return;
    }
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      var verifyPass = _current.text;
      if (newPass.isNotEmpty) {
        await AuthService.instance.changePassword(
          currentPassword: _current.text,
          newPassword: newPass,
        );
        verifyPass = newPass;
      }
      if (_user.text.trim() != _username) {
        await AuthService.instance.changeUsername(
          currentPassword: verifyPass,
          newUsername: _user.text,
        );
      }
      _current.clear();
      _next.clear();
      _confirm.clear();
      await _bootstrap();
      if (!mounted) return;
      setState(() => _message = 'Update ho gaya');
    } catch (e) {
      setState(() => _message = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleFingerprint(bool enable) async {
    if (_current.text.isEmpty) {
      setState(() => _message = 'Fingerprint ke liye pehle current password likhein');
      return;
    }
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      if (enable) {
        await AuthService.instance.enableFingerprint(_current.text);
        setState(() {
          _bioOn = true;
          _message = 'Fingerprint enabled';
        });
      } else {
        await AuthService.instance.disableFingerprint(_current.text);
        setState(() {
          _bioOn = false;
          _message = 'Fingerprint disabled';
        });
      }
    } catch (e) {
      setState(() => _message = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return VipScaffold(
      title: 'Change Password',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text('Zaib Petroleum Service', style: GoogleFonts.cinzel(color: AppColors.goldSoft, fontSize: 13)),
          const SizedBox(height: 14),
          VipField(label: 'Username', controller: _user),
          VipField(label: 'Current Password *', controller: _current, obscureText: true),
          VipField(label: 'New Password', controller: _next, obscureText: true),
          VipField(label: 'Confirm New Password', controller: _confirm, obscureText: true),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : _savePassword,
              child: Text(_busy ? 'Saving...' : 'Save Password'),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.28)),
              color: AppColors.panel.withValues(alpha: 0.92),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fingerprint', style: GoogleFonts.manrope(color: AppColors.gold, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  _bioAvailable
                      ? 'Pehle current password likhein, phir fingerprint on karein.'
                      : 'Is device pe fingerprint available nahi.',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppColors.gold,
                  title: Text(_bioOn ? 'Fingerprint On' : 'Fingerprint Off', style: const TextStyle(color: AppColors.cream)),
                  value: _bioOn,
                  onChanged: (!_bioAvailable || _busy) ? null : _toggleFingerprint,
                ),
              ],
            ),
          ),
          if (_message.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_message, style: TextStyle(color: _message.contains('galat') || _message.contains('nahi') ? AppColors.danger : AppColors.goldSoft)),
          ],
        ],
      ),
    );
  }
}
