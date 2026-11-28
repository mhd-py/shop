// Small helpers shared by the bill parsers.

/// A quantity and rate that the OCR printed as one number.
class GluedNumber {
  const GluedNumber(this.qty, this.rate);
  final int qty;
  final double rate;
}

final _gluedShape = RegExp(r'^\d{5,}(\.\d{1,3})?$');
const _taxFactors = [1.0, 1.05, 1.12, 1.18, 1.28];

/// Splits a number like 10177.97 into qty 1 and rate 177.97, but only when
/// qty x rate (plus 0/5/12/18/28% tax) matches [total]. Returns null when
/// no split fits, or when more than one fits.
GluedNumber? splitGlued(String text, double total) {
  final s = text.trim().replaceAll(',', '');
  if (!_gluedShape.hasMatch(s) || total <= 0) {
    return null;
  }
  final found = <GluedNumber>[];
  for (var i = 1; i <= 3 && i < s.length - 2; i++) {
    final qty = int.tryParse(s.substring(0, i));
    final rate = double.tryParse(s.substring(i));
    if (qty == null || rate == null || qty < 1 || rate <= 0) {
      continue;
    }
    final ratio = total / (qty * rate);
    for (final f in _taxFactors) {
      if ((ratio / f - 1).abs() <= 0.02) {
        found.add(GluedNumber(qty, rate));
        break;
      }
    }
  }
  return found.length == 1 ? found.first : null;
}

final _junkWord = RegExp(r'^(\d{3,}(,\d{3})*\.\d{2}|\d{6,})$');
final _unitHsn =
    RegExp(r'\s*\b(PKT|PCS|NOS|BOX|PC)\d{4,8}$', caseSensitive: false);
final _gluedSerial = RegExp(r'^(\d{1,3})(?=[A-Za-z]{2})');

/// Removes serial numbers, money values and HSN codes that leaked into a
/// product name. [expectedSerial] is this row's position (1, 2, 3...).
String cleanBillName(String raw, {int expectedSerial = 0}) {
  var n = raw.trim();
  if (expectedSerial > 0) {
    final m = _gluedSerial.firstMatch(n);
    if (m != null && int.parse(m.group(1)!) == expectedSerial) {
      n = n.substring(m.end);
    }
  }
  n = n.split(RegExp(r'\s+')).where((w) => !_junkWord.hasMatch(w)).join(' ');
  return n.replaceFirst(_unitHsn, '').trim();
}
