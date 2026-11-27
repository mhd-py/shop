import 'bill_parser.dart';

final _serial = RegExp(r'^\d{1,3}[.)]?$');
final _moneyOrCode = RegExp(r'^\d[\d,]*\.\d+$|^\d{5,}$');
final _smallInt = RegExp(r'^\d{1,2}$');
final _stop = RegExp(r'total|rupees|certified');
final _letters = RegExp(r'[A-Za-z]');

/// Last resort when the numbers cannot be read: finds the item names
/// (rows numbered 1, 2, 3...) and leaves quantity and cost for the owner.
ParsedBill? namesOnly(List<List<OcrCell>> rows) {
  final lines = <BillLine>[];
  for (final row in rows) {
    final tokens = [
      for (final c in row) ...c.text.trim().split(RegExp(r'\s+')),
    ].where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) {
      continue;
    }
    if (lines.isNotEmpty && _stop.hasMatch(tokens.join(' ').toLowerCase())) {
      break;
    }
    if (!_serial.hasMatch(tokens.first)) {
      continue;
    }
    final n = int.tryParse(tokens.first.replaceAll(RegExp(r'\D'), ''));
    if (n != lines.length + 1) {
      continue;
    }
    final name = <String>[];
    for (final t in tokens.skip(1)) {
      if (name.isEmpty && _moneyOrCode.hasMatch(t)) {
        continue; // an MRP or HSN printed before the name
      }
      if (name.isNotEmpty && _moneyOrCode.hasMatch(t)) {
        break;
      }
      name.add(t);
    }
    while (name.isNotEmpty && _smallInt.hasMatch(name.last)) {
      name.removeLast();
    }
    final text = name.join(' ');
    if (_letters.allMatches(text).length < 3) {
      continue;
    }
    lines.add(BillLine(
      name: text,
      qty: 0,
      totalPaise: 0,
      warnings: ['Fill in quantity and cost from the bill'],
    ));
  }
  if (lines.isEmpty) {
    return null;
  }
  return ParsedBill(lines: lines);
}
