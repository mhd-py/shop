import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

class PinCrypto {
  static final _rng = Random.secure();
  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  static String newSalt() =>
      base64.encode(List<int>.generate(16, (_) => _rng.nextInt(256)));

  static String hash(String secret, String salt) {
    final extra = utf8.encode(salt);
    List<int> d = utf8.encode('$salt:$secret');
    for (var i = 0; i < 10000; i++) {
      d = sha256.convert([...d, ...extra]).bytes;
    }
    return base64.encode(d);
  }

  static bool matches(String secret, String salt, String expected) {
    final a = hash(secret, salt);
    if (a.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// 10 characters shown as XXXXX-XXXXX (no 0/O/1/I/L to avoid mix-ups).
  static String newRecoveryCode() {
    final c = List.generate(10, (_) => _alphabet[_rng.nextInt(_alphabet.length)])
        .join();
    return '${c.substring(0, 5)}-${c.substring(5)}';
  }

  static String normalizeCode(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
}
