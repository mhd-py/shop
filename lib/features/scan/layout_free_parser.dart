import 'bill_cleanup.dart';
import 'bill_parser.dart';

class _Num {
  _Num(this.cell, this.value);
  final OcrCell cell;
  final double value;
}

/// Finds the item table without header words: number columns are found by
/// position, then Qty / Rate / Amount are found by maths (qty x rate = amount).
class LayoutFreeParser {
  static final _numeric =
      RegExp(r'^\d{1,3}(,\d{3})+(\.\d+)?$|^\d+(\.\d+)?$');
  static final _stop = RegExp(r'total|rupees|certified');
  static final _serialPrefix = RegExp(r'^\d{1,3}[\s.|)]+(?=[A-Za-z])');
  static final _letters = RegExp(r'[A-Za-z]');

  /// Column tolerance as a fraction of the page width.
  static const _tolFraction = 0.015;

  static double? _value(String text) {
    final s = text.trim();
    if (!_numeric.hasMatch(s)) {
      return null;
    }
    return double.parse(s.replaceAll(',', ''));
  }

  static int _paise(double v) => (v * 100).round();

  static double _median(List<double> v) {
    final s = [...v]..sort();
    return s[s.length ~/ 2];
  }

  static final _serialCell = RegExp(r'^\d{1,3}[.)]?$');

  /// Drops the serial number and moves any other number printed before the
  /// item name (an MRP, an HSN code) after it, so the name comes first.
  static List<OcrCell> _normalizeRow(List<OcrCell> row) {
    final firstWord = row.indexWhere((c) => _letters.hasMatch(c.text));
    if (firstWord <= 0) {
      return row;
    }
    final moved = <OcrCell>[];
    for (var i = 0; i < firstWord; i++) {
      final text = row[i].text.trim();
      if (i == 0 && _serialCell.hasMatch(text)) {
        continue;
      }
      if (_value(text) != null) {
        moved.add(row[i]);
      }
    }
    return [...row.sublist(firstWord), ...moved];
  }

  static int _nearest(List<double> centers, double x, double limit) {
    var best = -1;
    var bestDistance = limit;
    for (var i = 0; i < centers.length; i++) {
      final d = (centers[i] - x).abs();
      if (d <= bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return best;
  }

  /// Numbers that come after the first word of the row (serials are ignored).
  static List<_Num> _numbersAfterName(List<OcrCell> row) {
    final out = <_Num>[];
    var named = false;
    for (final c in row) {
      final v = _value(c.text);
      if (v == null) {
        if (_letters.hasMatch(c.text)) {
          named = true;
        }
      } else if (named) {
        out.add(_Num(c, v));
      }
    }
    return out;
  }

  /// Returns null when no believable table is found.
  ParsedBill? parse(List<List<OcrCell>> input) {
    final rows = [for (final r in input) _normalizeRow(r)];
    var right = 1.0;
    for (final r in rows) {
      for (final c in r) {
        if (c.right > right) {
          right = c.right;
        }
      }
    }
    final tol = right * _tolFraction;

    // Rows that look like items: a name followed by at least two numbers.
    final cand = <int>[];
    var footer = rows.length;
    for (var i = 0; i < rows.length; i++) {
      final text = rows[i].map((c) => c.text).join(' ').toLowerCase();
      if (cand.isNotEmpty && _stop.hasMatch(text)) {
        footer = i;
        break;
      }
      if (_numbersAfterName(rows[i]).length >= 2) {
        cand.add(i);
      }
    }
    if (cand.isEmpty) {
      return null;
    }

    // Number columns: values that line up vertically.
    final all = <_Num>[
      for (final i in cand) ..._numbersAfterName(rows[i]),
    ]..sort((a, b) => a.cell.center.compareTo(b.cell.center));
    final groups = <List<_Num>>[];
    for (final n in all) {
      if (groups.isNotEmpty &&
          n.cell.center - groups.last.last.cell.center <= tol) {
        groups.last.add(n);
      } else {
        groups.add([n]);
      }
    }
    final need = cand.length == 1
        ? 1
        : (cand.length / 2).ceil().clamp(2, cand.length).toInt();
    final centers = <double>[
      for (final g in groups)
        if (g.length >= need)
          g.fold<double>(0, (s, n) => s + n.cell.center) / g.length,
    ];
    if (centers.length < 3 || centers.length > 18) {
      return null;
    }
    final k = centers.length;

    // Value of each column for each candidate row.
    final grid = <List<double?>>[];
    for (final i in cand) {
      final v = List<double?>.filled(k, null);
      for (final n in _numbersAfterName(rows[i])) {
        final c = _nearest(centers, n.cell.center, tol * 1.5);
        if (c >= 0 && v[c] == null) {
          v[c] = n.value;
        }
      }
      grid.add(v);
    }

    // Which columns are Qty, Rate and Amount? The one where qty x rate ~ amount.
    List<int>? bestKey;
    var bq = -1, br = -1, ba = -1, bestMatched = 0, bestUsed = 0;
    for (var q = 0; q < k; q++) {
      for (var r = 0; r < k; r++) {
        for (var a = 0; a < k; a++) {
          if (q == r || q == a || r == a) {
            continue;
          }
          var matched = 0, used = 0, whole = 0;
          final qs = <double>[];
          final rs = <double>[];
          for (final v in grid) {
            final vq = v[q], vr = v[r], va = v[a];
            if (vq == null || vr == null || va == null || vq <= 0 || vr <= 0) {
              continue;
            }
            used++;
            qs.add(vq);
            rs.add(vr);
            if (vq == vq.roundToDouble()) {
              whole++;
            }
            final e = vq * vr;
            if (va >= e * 0.98 && va <= e * 1.35) {
              matched++;
            }
          }
          if (matched == 0) {
            continue;
          }
          final order = _median(qs) <= _median(rs) ? 1 : 0;
          final key = [matched, whole, order, a];
          var better = bestKey == null;
          if (bestKey != null) {
            for (var j = 0; j < key.length; j++) {
              if (key[j] != bestKey[j]) {
                better = key[j] > bestKey[j];
                break;
              }
            }
          }
          if (better) {
            bestKey = key;
            bq = q;
            br = r;
            ba = a;
            bestMatched = matched;
            bestUsed = used;
          }
        }
      }
    }
    if (bestKey == null || bestMatched * 2 < bestUsed) {
      return null;
    }

    // MRP: another column that is 1x to 3x the rate on most rows.
    int? mrpCol;
    for (var c = 0; c < k; c++) {
      if (c == bq || c == br || c == ba) {
        continue;
      }
      var ok = 0, total = 0;
      for (final v in grid) {
        final vr = v[br], vc = v[c];
        if (vr == null || vc == null || vr <= 0) {
          continue;
        }
        total++;
        if (vc >= vr && vc <= vr * 3) {
          ok++;
        }
      }
      if (total > 0 && ok * 10 >= total * 7) {
        mrpCol = c;
        break;
      }
    }

    final lines = <BillLine>[];
    for (var i = cand.first; i < footer; i++) {
      final line = _readRow(rows[i], centers, tol, bq, br, ba, mrpCol, lines);
      if (line != null) {
        lines.add(line);
      }
    }
    if (lines.isEmpty) {
      return null;
    }

    final sum = lines.fold<int>(0, (s, l) => s + l.totalPaise);
    var checked = false;
    var match = false;
    for (var i = footer; i < rows.length; i++) {
      for (final c in rows[i]) {
        final v = _value(c.text);
        if (v == null) {
          continue;
        }
        checked = true;
        if ((_paise(v) - sum).abs() <= 100) {
          match = true;
        }
      }
    }
    if (lines.any((l) => l.qty <= 0)) {
      match = false;
    }
    return ParsedBill(lines: lines, totalsChecked: checked, totalsMatch: match);
  }

  BillLine? _readRow(List<OcrCell> row, List<double> centers, double tol,
      int q, int r, int a, int? m, List<BillLine> lines) {
    final words = <String>[];
    final orphans = <String>[];
    final got = <int, double>{};
    var named = false;
    for (final c in row) {
      final v = _value(c.text);
      if (v == null) {
        words.add(c.text.trim());
        if (_letters.hasMatch(c.text)) {
          named = true;
        }
        continue;
      }
      if (!named) {
        continue; // serial number
      }
      final col = _nearest(centers, c.center, tol * 1.5);
      if (col >= 0 && !got.containsKey(col)) {
        got[col] = v;
      } else {
        words.add(c.text.trim()); // a number that belongs to the name
        orphans.add(c.text.trim());
      }
    }
    var qv = got[q], rv = got[r];
    final av = got[a];
    if (qv == null && av != null) {
      for (final o in orphans) {
        final g = splitGlued(o, av);
        if (g != null) {
          qv = g.qty.toDouble();
          rv ??= g.rate;
          words.remove(o);
          break;
        }
      }
    }
    final name = cleanBillName(
        words.join(' ').trim().replaceFirst(_serialPrefix, ''),
        expectedSerial: lines.length + 1);

    if (qv == null && av == null) {
      // Text only: the item name continues from the line above.
      if (got.isEmpty &&
          lines.isNotEmpty &&
          _letters.allMatches(name).length >= 2) {
        lines.last.name = '${lines.last.name} $name';
      }
      return null;
    }
    if (_letters.allMatches(name).length < 2) {
      return null;
    }

    final warnings = <String>[];
    var qty = 0;
    if (qv == null) {
      warnings.add('Quantity not found');
    } else {
      qty = qv.round();
      if (qv != qv.roundToDouble()) {
        warnings.add('Quantity is not a whole number');
      }
      if (qty <= 0) {
        warnings.add('Quantity is zero');
      }
    }

    double total;
    if (av != null) {
      total = av;
    } else {
      total = (rv != null && qv != null) ? rv * qv : 0;
      warnings.add('Amount not found, please check');
    }
    if (rv != null && qty > 0 && av != null) {
      final expected = rv * qty;
      if (total < expected * 0.98 || total > expected * 1.35) {
        warnings.add('Amount does not match rate x quantity');
      }
    }

    final mrp = m == null ? null : got[m];
    return BillLine(
      name: name,
      qty: qty,
      totalPaise: _paise(total),
      mrpPaise: mrp == null ? null : _paise(mrp),
      ratePaise: rv == null ? null : _paise(rv),
      warnings: warnings,
    );
  }
}
