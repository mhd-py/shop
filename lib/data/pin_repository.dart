import 'dart:math';


import '../core/pin_crypto.dart';
import 'database.dart';

/// A message that is safe to show to the shopkeeper.
class PinException implements Exception {
  PinException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PinRepository {
  PinRepository(this._db);
  final AppDatabase _db;

  static const _pinSalt = 'pin_salt';
  static const _pinHash = 'pin_hash';
  static const _recSalt = 'rec_salt';
  static const _recHash = 'rec_hash';
  static const _fails = 'pin_fails';
  static const _lockUntil = 'pin_lock_until_ms';
  static const _all = [
    _pinSalt, _pinHash, _recSalt, _recHash, _fails, _lockUntil
  ];

  static String? validatePin(String p) =>
      RegExp(r'^\d{4}$').hasMatch(p) ? null : 'PIN must be 4 digits';

  Future<String?> _get(String key) async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.settingKey.equals(key)))
        .getSingleOrNull();
    return row?.settingValue;
  }

  Future<void> _set(String key, String value) =>
      _db.into(_db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(settingKey: key, settingValue: value),
          );

  Future<void> _del(List<String> keys) => (_db.delete(_db.appSettings)
        ..where((t) => t.settingKey.isIn(keys)))
      .go();

  Stream<bool> watchHasPin() => (_db.select(_db.appSettings)
        ..where((t) => t.settingKey.equals(_pinHash)))
      .watchSingleOrNull()
      .map((r) => r != null);

  Future<bool> hasPin() async => (await _get(_pinHash)) != null;

  String _wait(int ms) {
    final s = (ms / 1000).ceil();
    return s < 60 ? '$s seconds' : '${(s / 60).ceil()} minutes';
  }

  Future<void> _ensureNotLocked() async {
    final until = int.tryParse(await _get(_lockUntil) ?? '') ?? 0;
    final left = until - DateTime.now().millisecondsSinceEpoch;
    if (left > 0) {
      throw PinException('Too many wrong tries. Wait ${_wait(left)}.');
    }
  }

  Future<void> _clearFails() => _del([_fails, _lockUntil]);

  Future<void> _fail(String what) async {
    final n = (int.tryParse(await _get(_fails) ?? '') ?? 0) + 1;
    await _set(_fails, '$n');
    if (n >= 5) {
      final secs = min(30 * (1 << min(n - 5, 5)), 900);
      await _set(_lockUntil,
          (DateTime.now().millisecondsSinceEpoch + secs * 1000).toString());
      throw PinException('$what. Wait ${_wait(secs * 1000)}.');
    }
    throw PinException('$what (${5 - n} tries left)');
  }

  Future<void> _writePin(String pin) async {
    final salt = PinCrypto.newSalt();
    await _set(_pinSalt, salt);
    await _set(_pinHash, PinCrypto.hash(pin, salt));
  }

  Future<String> _writeRecovery() async {
    final code = PinCrypto.newRecoveryCode();
    final salt = PinCrypto.newSalt();
    await _set(_recSalt, salt);
    await _set(_recHash, PinCrypto.hash(PinCrypto.normalizeCode(code), salt));
    return code;
  }

  /// Turns the PIN on. Returns the recovery code (show it once).
  Future<String> setPin(String pin) async {
    final bad = validatePin(pin);
    if (bad != null) throw PinException(bad);
    late String code;
    await _db.transaction(() async {
      await _writePin(pin);
      code = await _writeRecovery();
      await _clearFails();
    });
    return code;
  }

  /// Throws [PinException] when the PIN is wrong or the app is in a wait.
  Future<void> verifyPin(String pin) async {
    await _ensureNotLocked();
    final salt = await _get(_pinSalt);
    final h = await _get(_pinHash);
    if (salt == null || h == null) return;
    if (PinCrypto.matches(pin, salt, h)) return _clearFails();
    await _fail('Wrong PIN');
  }

  Future<void> changePin(String current, String newPin) async {
    final bad = validatePin(newPin);
    if (bad != null) throw PinException(bad);
    await verifyPin(current);
    await _writePin(newPin);
  }

  Future<void> removePin(String current) async {
    await verifyPin(current);
    await _del(_all);
  }

  /// Throws when the recovery code is wrong.
  Future<void> checkRecovery(String code) async {
    await _ensureNotLocked();
    final salt = await _get(_recSalt);
    final h = await _get(_recHash);
    if (salt == null || h == null) {
      throw PinException('No recovery code is set');
    }
    if (PinCrypto.matches(PinCrypto.normalizeCode(code), salt, h)) {
      return _clearFails();
    }
    await _fail('Wrong recovery code');
  }

  /// Sets a new PIN and returns a fresh recovery code.
  Future<String> resetWithRecovery(String code, String newPin) async {
    final bad = validatePin(newPin);
    if (bad != null) throw PinException(bad);
    await checkRecovery(code);
    late String fresh;
    await _db.transaction(() async {
      await _writePin(newPin);
      fresh = await _writeRecovery();
    });
    return fresh;
  }

  /// Last resort: deletes ALL data, including the PIN.
  Future<void> eraseAllData() => _db.transaction(() async {
        await _db.customStatement('PRAGMA defer_foreign_keys = ON');
        for (final t in _db.allTables) {
          await _db.delete(t).go();
        }
      });
}
