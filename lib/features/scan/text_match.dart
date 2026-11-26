import 'dart:math' as math;

/// Lowercase letters and digits only.
String compact(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

int editDistance(String a, String b) {
  if (a == b) {
    return 0;
  }
  if (a.isEmpty) {
    return b.length;
  }
  if (b.isEmpty) {
    return a.length;
  }
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = math.min(
        math.min(prev[j] + 1, cur[j - 1] + 1),
        prev[j - 1] + cost,
      );
    }
    prev = cur;
  }
  return prev[b.length];
}

/// 1.0 = identical, 0.0 = nothing in common.
double similarity(String a, String b) {
  final longest = math.max(a.length, b.length);
  if (longest == 0) {
    return 1;
  }
  return 1 - editDistance(a, b) / longest;
}
