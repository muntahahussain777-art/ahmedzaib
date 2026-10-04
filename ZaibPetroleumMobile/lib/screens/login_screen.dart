import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/vip_widgets.dart';
import 'home_screen.dart';
import 'owner_screens.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _bioEnabled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final bio = await AuthService.instance.fingerprintEnabled;
    if (!mounted) return;
    setState(() {
      // Username khali — admin / owner dono khud type karein
      _user.clear();
      _pass.clear();
      _bioEnabled = bio;
      _loading = false;
      _error = null;
    });
    // Auto fingerprint mat chalao — warna last role (admin) hamesha khul jata,
    // owner password login nahi ho pata. Fingerprint button se manually.
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _goHome(AppRole role) async {
    unawaited(SyncService.instance.syncNow());
    if (!mounted) return;
    final home = role == AppRole.owner ? const OwnerHomeScreen() : const HomeScreen();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => home),
      (_) => false,
    );
  }

  Future<void> _loginPassword() async {
    final u = _user.text.trim();
    final p = _pass.text.trim();
    if (u.isEmpty || p.isEmpty) {
      setState(() => _error = 'Username aur password likhein');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final role = await AuthService.instance.login(u, p);
      if (!mounted) return;
      if (role != null) {
        await _goHome(role);
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Username ya password galat hai\nAdmin: admin / Owner: owner';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Login error: $e';
      });
    }
  }

  Future<void> _loginFingerprint({bool auto = false}) async {
    if (!_bioEnabled) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final role = await AuthService.instance.loginWithFingerprint();
    if (!mounted) return;
    if (role != null) {
      await _goHome(role);
      return;
    }
    setState(() {
      _loading = false;
      if (!auto) _error = 'Fingerprint fail — password se login karein';
    });
  }

  @override
  Widget build(BuildContext context) {
    return VipScaffold(
      title: 'Login',
      showBack: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
        children: [
          const SizedBox(height: 18),
          Center(
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
                boxShadow: [
                  BoxShadow(color: AppColors.gold.withValues(alpha: 0.18), blurRadius: 24, spreadRadius: 2),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset('assets/branding/app_logo.jpg', fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'ZAIB PETROLEUM SERVICE',
            textAlign: TextAlign.center,
            style: GoogleFonts.cinzel(
              color: AppColors.gold,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
            ),
          ),
          const SizedBox(height: 28),
          VipField(label: 'Username', controller: _user),
          VipField(
            label: 'Password',
            controller: _pass,
            hint: '••••••',
            obscureText: _obscure,
            suffix: IconButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppColors.gold),
            ),
          ),
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _loginPassword,
              child: Text(_loading ? 'Please wait...' : 'Login'),
            ),
          ),
          if (_bioEnabled) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _loading ? null : () => _loginFingerprint(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.gold,
                  side: const BorderSide(color: AppColors.gold),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.fingerprint),
                label: const Text('Fingerprint Login'),
              ),
            ),
          ],
          const SizedBox(height: 36),
          Text(
            'Developed by Irtaza Hussain',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
