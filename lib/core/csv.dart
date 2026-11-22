/// Paise as a plain number, e.g. 12550 -> 125.50
String paiseToPlain(int paise) =>
    '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';

/// Excel-friendly CSV (UTF-8 BOM, CRLF). Cells starting with = + - @ are
/// prefixed with ' so spreadsheets never run them as formulas.
String csvEncode(List<List<String>> rows) =>
    '\uFEFF${rows.map((r) => r.map(_cell).join(',')).join('\r\n')}\r\n';

String _cell(String v) {
  var s = v;
  if (s.isNotEmpty && '=+-@'.contains(s[0]) && double.tryParse(s) == null) {
    s = "'$s";
  }
  if (s.contains(RegExp(r'[",\r\n]'))) s = '"${s.replaceAll('"', '""')}"';
  return s;
}
