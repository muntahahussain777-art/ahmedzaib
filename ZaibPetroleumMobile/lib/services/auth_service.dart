import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppRole { admin, owner }

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  /// Fixed owner account — admin prefs se alag (admin change nahi hota)
  static const ownerUsername = 'owner';
  static const ownerPassword = 'zaibay';

  static const _kUser = 'auth_username';
  static const _kPass = 'auth_password';
  static const _kBio = 'auth_fingerprint_enabled';
  static const _kLastRole = 'auth_last_role';

  final LocalAuthentication _bio = LocalAuthentication();

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  /// Admin username (Change Password screen) — default admin
  Future<String> getUsername() async {
    final p = await _prefs;
    return p.getString(_kUser) ?? 'admin';
  }

  Future<String> getPassword() async {
    final p = await _prefs;
    return p.getString(_kPass) ?? 'admin';
  }

  Future<bool> get fingerprintEnabled async {
    final p = await _prefs;
    return p.getBool(_kBio) ?? false;
  }

  Future<AppRole> getLastRole() async {
    final p = await _prefs;
    final v = p.getString(_kLastRole);
    if (v == 'owner') return AppRole.owner;
    return AppRole.admin;
  }

  Future<void> setLastRole(AppRole role) async {
    final p = await _prefs;
    await p.setString(_kLastRole, role == AppRole.owner ? 'owner' : 'admin');
  }

  /// Returns role on success, null on fail. Admin prefs + fixed owner.
  Future<AppRole?> login(String username, String password) async {
    final u = username.trim();
    final p = password.trim();
    if (u.isEmpty || p.isEmpty) return null;

    // Owner pehle — fixed account (case-insensitive username)
    if (u.toLowerCase() == ownerUsername && p.toLowerCase() == ownerPassword) {
      await setLastRole(AppRole.owner);
      return AppRole.owner;
    }

    final adminUser = (await getUsername()).trim();
    final adminPass = (await getPassword()).trim();
    if (u.toLowerCase() == adminUser.toLowerCase() && p == adminPass) {
      await setLastRole(AppRole.admin);
      return AppRole.admin;
    }
    return null;
  }

  @Deprecated('Use login()')
  Future<bool> validate(String username, String password) async {
    return await login(username, password) != null;
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final pass = await getPassword();
    if (currentPassword != pass) {
      throw Exception('Current password galat hai');
    }
    if (newPassword.trim().isEmpty) {
      throw Exception('New password khali nahi ho sakta');
    }
    final p = await _prefs;
    await p.setString(_kPass, newPassword.trim());
  }

  Future<void> changeUsername({
    required String currentPassword,
    required String newUsername,
  }) async {
    final pass = await getPassword();
    if (currentPassword != pass) {
      throw Exception('Current password galat hai');
    }
    final u = newUsername.trim();
    if (u.isEmpty) throw Exception('Username khali nahi ho sakta');
    if (u.toLowerCase() == ownerUsername) {
      throw Exception('Ye username owner ke liye reserved hai');
    }
    final p = await _prefs;
    await p.setString(_kUser, u);
  }

  Future<bool> canUseFingerprint() async {
    try {
      final supported = await _bio.isDeviceSupported();
      final canCheck = await _bio.canCheckBiometrics;
      return supported && canCheck;
    } catch (_) {
      return false;
    }
  }

  /// Pehle password verify, phir fingerprint enable.
  Future<void> enableFingerprint(String currentPassword) async {
    final role = await loginGuessPassword(currentPassword);
    if (role == null) {
      throw Exception('Pehle sahi password likhein');
    }
    if (!await canUseFingerprint()) {
      throw Exception('Is phone pe fingerprint available nahi');
    }
    final ok = await authenticateFingerprint(reason: 'Fingerprint enable karne ke liye confirm karein');
    if (!ok) throw Exception('Fingerprint confirm nahi hua');
    final p = await _prefs;
    await p.setBool(_kBio, true);
    await setLastRole(role);
  }

  Future<void> disableFingerprint(String currentPassword) async {
    final role = await loginGuessPassword(currentPassword);
    if (role == null) {
      throw Exception('Password galat hai');
    }
    final p = await _prefs;
    await p.setBool(_kBio, false);
  }

  Future<AppRole?> loginGuessPassword(String password) async {
    final p = password.trim();
    final adminPass = (await getPassword()).trim();
    if (p == adminPass) return AppRole.admin;
    if (p.toLowerCase() == ownerPassword) return AppRole.owner;
    return null;
  }

  Future<bool> authenticateFingerprint({String reason = 'Login ke liye fingerprint'}) async {
    try {
      return await _bio.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  /// Fingerprint OK → last role (owner ya admin)
  Future<AppRole?> loginWithFingerprint() async {
    if (!await fingerprintEnabled) return null;
    final ok = await authenticateFingerprint();
    if (!ok) return null;
    return getLastRole();
  }
}
