import 'package:local_auth/local_auth.dart';

enum AuthOutcome { success, failed, unavailable }

/// Fingerprint / face / device passcode gate for card secrets.
/// A successful unlock is remembered for [grace] so one screen doesn't prompt twice.
class AppAuth {
  AppAuth._();

  static final LocalAuthentication _auth = LocalAuthentication();
  static const Duration grace = Duration(seconds: 60);
  static DateTime? _lastSuccess;

  static Future<AuthOutcome> unlock(String reason) async {
    final last = _lastSuccess;
    if (last != null && DateTime.now().difference(last) < grace) {
      return AuthOutcome.success;
    }
    try {
      // false when the phone has no screen lock at all: secrets stay locked.
      if (!await _auth.isDeviceSupported()) return AuthOutcome.unavailable;
      final ok = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false, // allow the device PIN / pattern / password as fallback
        persistAcrossBackgrounding: true,
      );
      if (ok) _lastSuccess = DateTime.now();
      return ok ? AuthOutcome.success : AuthOutcome.failed;
    } catch (_) {
      return AuthOutcome.failed;
    }
  }

  /// Forget the grace window, e.g. when the app goes to the background.
  static void lock() => _lastSuccess = null;
}
