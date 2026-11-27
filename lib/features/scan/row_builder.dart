import 'bill_parser.dart';

/// One recognised word with its box on the photo.
class RawWord {
  const RawWord(this.text, this.left, this.right, this.top, this.bottom);
  final String text;
  final double left, right, top, bottom;
  double get cx => (left + right) / 2;
  double get cy => (top + bottom) / 2;
  double get height => bottom - top;
}

class _Placed {
  _Placed(this.word, this.y);
  final RawWord word;
  final double y;
}

/// Middle value of the slopes (rise / run) of long text lines.
/// Returns 0 when there are too few lines or the value is not believable.
double medianSlope(List<double> slopes) {
  if (slopes.length < 3) {
    return 0;
  }
  final s = [...slopes]..sort();
  final m = s[s.length ~/ 2];
  return m.abs() > 0.5 ? 0 : m;
}

/// Groups words into table rows. With a [slope] the photo is straightened
/// first, so rows of a tilted bill do not mix.
List<List<OcrCell>> buildRows(List<RawWord> words, {double slope = 0}) {
  final placed = [for (final w in words) _Placed(w, w.cy - w.cx * slope)]
    ..sort((a, b) => a.y.compareTo(b.y));
  final groups = <List<_Placed>>[];
  for (final p in placed) {
    if (groups.isNotEmpty) {
      final g = groups.last;
      var y = 0.0;
      var h = 0.0;
      for (final x in g) {
        y += x.y;
        h += x.word.height;
      }
      y /= g.length;
      h /= g.length;
      if ((p.y - y).abs() < h * 0.6) {
        g.add(p);
        continue;
      }
    }
    groups.add([p]);
  }
  return [
    for (final g in groups)
      [
        for (final p
            in (g..sort((a, b) => a.word.left.compareTo(b.word.left))))
          OcrCell(p.word.text, p.word.left, p.word.right),
      ],
  ];
}
