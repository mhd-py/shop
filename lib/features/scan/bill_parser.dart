import 'text_match.dart';

/// One piece of text on the bill with its horizontal position.
class OcrCell {
  const OcrCell(this.text, this.left, this.right);
  final String text;
  final double left;
  final double right;
  double get center => (left + right) / 2;
}

enum Field { serial, name, mrp, qty, rate, total, other }

class BillLine {
  BillLine({
    required this.name,
    required this.qty,
    required this.totalPaise,
    this.mrpPaise,
    this.ratePaise,
    List<String>? warnings,
  }) : warnings = warnings ?? [];

  String name;
  int qty;
  int totalPaise;
  int? mrpPaise;
  int? ratePaise;
  final List<String> warnings;

  /// Real cost per piece: line total (tax included) divided by quantity.
  int get unitCostPaise =>
      qty > 0 ? (totalPaise / qty).round() : totalPaise;

  bool get needsReview => warnings.isNotEmpty;
}

class ParsedBill {
  const ParsedBill({
    this.lines = const [],
    this.problem,
    this.totalsChecked = false,
    this.totalsMatch = false,
  });
  final List<BillLine> lines;

  /// Set when the table could not be read at all.
  final String? problem;

  /// True when a bill total was found to compare with.
  final bool totalsChecked;

  /// True when the line totals add up to a total printed on the bill.
  final bool totalsMatch;
}

class _Col {
  _Col(this.field, this.center);
  final Field field;
  final double center;
}

class _Num {
  _Num(this.cell, this.value);
  final OcrCell cell;
  final double value;
}

/// Reads the item table of a printed bill. Header words are matched against
/// synonym lists, so different suppliers' wording still works.
class BillParser {
  static const _synonyms = <Field, List<String>>{
    Field.serial: ['sl', 'slno', 'si', 'sino', 'sr', 'srno', 'sn', 'sno'],
    Field.name: [
      'particular',
      'particulars',
      'productdesc',
      'productdescription',
      'description',
      'itemname',
      'itemdescription',
      'item',
      'product',
      'productname',
      'descriptionofgoods',
    ],
    Field.mrp: ['mrp'],
    Field.qty: ['qty', 'quantity', 'pcs', 'pkt', 'nos', 'units', 'cbbpkt'],
    Field.rate: ['rate', 'unitprice', 'price', 'basicrate', 'unitrate'],
    Field.total: [
      'total',
      'totalamount',
      'netamt',
      'netamount',
      'amount',
      'linetotal',
    ],
  };

  static final _numeric =
      RegExp(r'^\d{1,3}(,\d{3})+(\.\d+)?$|^\d+(\.\d+)?$');
  static final _stop = RegExp(r'total|rupees|certified');
  static final _serialPrefix = RegExp(r'^\d{1,3}[\s.|)]+(?=[A-Za-z])');

  /// Which field a header word stands for. Tolerates one OCR mistake in
  /// words of five or more letters.
  static Field fieldOf(String raw) {
    final k = raw.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (k.isEmpty) {
      return Field.other;
    }
    for (final e in _synonyms.entries) {
      for (final s in e.value) {
        if (k == s) {
          return e.key;
        }
        if (s.length >= 5 && k.length >= 5 && editDistance(k, s) <= 1) {
          return e.key;
        }
      }
    }
    return Field.other;
  }

  static double? _parse(String text) {
    final s = text.trim();
    if (!_numeric.hasMatch(s)) {
      return null;
    }
    return double.parse(s.replaceAll(',', ''));
  }

  static int _paise(double v) => (v * 100).round();

  /// [rows] are top to bottom; cells inside a row are left to right.
  ParsedBill parse(List<List<OcrCell>> rows) {
    var header = -1;
    var cols = <_Col>[];
    for (var i = 0; i < rows.length; i++) {
      final cs = [for (final c in rows[i]) _Col(fieldOf(c.text), c.center)];
      final found = {
        for (final c in cs)
          if (c.field != Field.other) c.field,
      };
      if (found.contains(Field.name) &&
          found.contains(Field.qty) &&
          found.length >= 3) {
        header = i;
        cols = cs;
        break;
      }
    }
    if (header < 0) {
      return const ParsedBill(
        problem: 'Could not find the item table. Try a clearer photo, '
            'or add the stock manually.',
      );
    }

    final lines = <BillLine>[];
    var footer = rows.length;
    for (var i = header + 1; i < rows.length; i++) {
      final text = rows[i].map((c) => c.text).join(' ').toLowerCase();
      if (_stop.hasMatch(text)) {
        footer = i;
        break;
      }
      final line = _readRow(rows[i], cols, lines);
      if (line != null) {
        lines.add(line);
      }
    }
    if (lines.isEmpty) {
      return const ParsedBill(
        problem: 'Found the table but no item rows. Try a clearer photo.',
      );
    }

    final sum = lines.fold<int>(0, (a, l) => a + l.totalPaise);
    var checked = false;
    var match = false;
    for (var i = footer; i < rows.length; i++) {
      for (final c in rows[i]) {
        final v = _parse(c.text);
        if (v == null) {
          continue;
        }
        checked = true;
        if ((_paise(v) - sum).abs() <= 100) {
          match = true;
        }
      }
    }
    return ParsedBill(lines: lines, totalsChecked: checked, totalsMatch: match);
  }

  BillLine? _readRow(List<OcrCell> row, List<_Col> cols, List<BillLine> lines) {
    final nums = <_Num>[];
    final words = <String>[];
    for (final c in row) {
      final v = _parse(c.text);
      if (v == null) {
        words.add(c.text.trim());
      } else {
        nums.add(_Num(c, v));
      }
    }
    final name = words.join(' ').trim().replaceFirst(_serialPrefix, '');

    // Text only: the item name continues from the line above.
    if (nums.isEmpty) {
      if (name.isNotEmpty && lines.isNotEmpty) {
        lines.last.name = '${lines.last.name} $name';
      }
      return null;
    }
    if (nums.length < 2) {
      return null;
    }
    if (RegExp(r'[A-Za-z]').allMatches(name).length < 2) {
      return null;
    }

    final byField = <Field, double>{};
    final warnings = <String>[];
    for (final n in nums) {
      _Col? best;
      var bestDistance = double.infinity;
      for (final c in cols) {
        final d = (c.center - n.cell.center).abs();
        if (d < bestDistance) {
          bestDistance = d;
          best = c;
        }
      }
      final f = best?.field ?? Field.other;
      if (f == Field.other || f == Field.serial || f == Field.name) {
        continue;
      }
      final old = byField[f];
      if (old == null) {
        byField[f] = n.value;
      } else if (f == Field.qty) {
        if (n.value > old) {
          byField[f] = n.value;
        }
      } else if (!warnings.contains('Columns unclear')) {
        warnings.add('Columns unclear');
      }
    }

    final qtyValue = byField[Field.qty];
    final rate = byField[Field.rate];
    var total = byField[Field.total];

    if (total == null) {
      if (rate != null && qtyValue != null) {
        total = rate * qtyValue;
      } else {
        nums.sort((a, b) => a.cell.center.compareTo(b.cell.center));
        total = nums.last.value;
      }
      warnings.add('Amount not found, please check');
    }

    var qty = 0;
    if (qtyValue == null) {
      warnings.add('Quantity not found');
    } else {
      qty = qtyValue.round();
      if (qtyValue != qtyValue.roundToDouble()) {
        warnings.add('Quantity is not a whole number');
      }
      if (qty <= 0) {
        warnings.add('Quantity is zero');
      }
    }

    if (rate != null && qty > 0) {
      final expected = rate * qty;
      if (total < expected * 0.98 || total > expected * 1.35) {
        warnings.add('Amount does not match rate x quantity');
      }
    }

    final mrp = byField[Field.mrp];
    return BillLine(
      name: name,
      qty: qty,
      totalPaise: _paise(total),
      mrpPaise: mrp == null ? null : _paise(mrp),
      ratePaise: rate == null ? null : _paise(rate),
      warnings: warnings,
    );
  }
}
