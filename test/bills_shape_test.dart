import 'package:flutter_test/flutter_test.dart';
import 'package:shop/features/scan/bill_parser.dart';
import 'package:shop/features/scan/names_only.dart';
import 'package:shop/features/scan/row_builder.dart';

OcrCell t(String s, double l, double r) => OcrCell(s, l, r);
OcrCell n(String s, double c) => OcrCell(s, c - 20, c + 20);
List<OcrCell> data(List<String> v, List<double> x, [double shift = 0]) =>
    [for (var i = 0; i < v.length; i++) n(v[i], x[i] + shift)];

void main() {
  test('Veegeo style: MRP before the name, 12 tight columns', () {
    const x = <double>[360, 410, 470, 530, 575, 620, 665, 710, 755, 800, 850];
    final rows = <List<OcrCell>>[
      [
        t('1', 70, 85), n('120.00', 130),
        t('DABUR', 150, 200), t('PASTE', 205, 250),
        t('50G(RS20*6+1)', 255, 330),
        ...data(['33061020', '2', '97.15', '194.30', '0.00', '194.30', '2.50',
            '4.85', '2.50', '4.85', '204.00'], x),
      ],
      [
        t('2', 70, 85), n('5.00', 130),
        t('WIN', 150, 170), t('TOTEM', 175, 215), t('P5', 220, 240),
        t('BL', 245, 260),
        ...data(['96081019', '10', '3.09', '30.94', '0.00', '30.94', '9.00',
            '2.78', '9.00', '2.78', '36.50'], x),
      ],
      [
        t('3', 70, 85), n('5.00', 130),
        t('WIN', 150, 170), t('TOTEM', 175, 215), t('P5', 220, 240),
        t('BK', 245, 260),
        ...data(['96081019', '20', '3.09', '61.88', '0.00', '61.88', '9.00',
            '5.56', '9.00', '5.56', '73.00'], x),
      ],
      [t('Total', 80, 120), n('313.50', 850)],
    ];
    final bill = BillParser().parse(rows);
    expect(bill.problem, isNull);
    expect(bill.lines.length, 3);
    expect(bill.lines.map((l) => l.qty).toList(), [2, 10, 20]);
    expect(bill.lines.map((l) => l.totalPaise).toList(), [20400, 3650, 7300]);
    expect(bill.lines.map((l) => l.mrpPaise).toList(), [12000, 500, 500]);
    expect(bill.lines[0].name, 'DABUR PASTE 50G(RS20*6+1)');
    expect(bill.totalsMatch, isTrue);
  });

  test('Space Marketing style: Cs and Pc columns close together', () {
    const x = <double>[1085, 1150, 1207, 1287, 1370, 1500, 1620, 1740, 1880,
        2050, 2170, 2330, 2500];
    final rows = <List<OcrCell>>[
      [
        t('1', 80, 100), n('34054000', 210),
        t('Exo', 300, 340), t('Bar', 345, 385), t('BE', 390, 410),
        t('Ging', 415, 460),
        ...data(['5', '0', '12', '0', '3.92', '47.08', '10.00', '4.71', '0.00',
            '42.37', '18.00', '7.63', '50.00'], x),
      ],
      [
        t('2', 80, 100), n('34011942', 210),
        t('Morelight', 300, 360), t('Bar', 365, 395), t('130g', 400, 440),
        ...data(['10', '0', '6', '0', '7.85', '47.08', '7.69', '3.62', '0.00',
            '43.46', '18.00', '7.82', '51.28'], x, 6),
      ],
      [
        t('Total', 800, 860), n('0', 1150), n('18', 1207), n('0', 1287),
        n('94.16', 1500), n('101.00', 2500),
      ],
    ];
    final bill = BillParser().parse(rows);
    expect(bill.problem, isNull);
    expect(bill.lines.map((l) => l.qty).toList(), [12, 6]);
    expect(bill.lines.map((l) => l.totalPaise).toList(), [5000, 5128]);
    expect(bill.lines.map((l) => l.mrpPaise).toList(), [500, 1000]);
    expect(bill.totalsMatch, isTrue);
  });

  test('names only: Marie Gold style bill', () {
    final rows = <List<OcrCell>>[
      [t('SL', 30, 50), t('PRODUCT', 60, 120), t('DESC', 125, 160)],
      [t('19053100', 60, 120)],
      [
        t('1', 30, 40), t('50-50', 60, 100), t('141GM', 105, 150),
        t('40PK', 155, 190), n('0', 300), n('0', 360), n('0.00', 420),
      ],
      [
        t('2', 30, 40), t('MARIE', 60, 100), t('GOLD', 105, 140),
        t('250GM', 145, 190), t('36PK', 195, 230), n('0', 300), n('12', 360),
        n('25.00', 420),
      ],
      [n('40', 500), n('21.30', 560), n('255.56', 620)],
      [t('Sub', 30, 60), t('Total:', 65, 100), n('0', 300), n('18', 360)],
    ];
    final bill = namesOnly(rows)!;
    expect(bill.lines.map((l) => l.name).toList(),
        ['50-50 141GM 40PK', 'MARIE GOLD 250GM 36PK']);
    expect(bill.lines.every((l) => l.qty == 0 && l.needsReview), isTrue);
  });

  test('straightens a tilted photo into the right rows', () {
    RawWord w(String s, double cx, double cy) =>
        RawWord(s, cx - 10, cx + 10, cy - 10, cy + 10);
    // Slope 0.05: a word 400 px to the right sits 20 px lower.
    final words = [
      w('a1', 100, 105), w('a2', 500, 125), w('a3', 900, 145),
      w('b1', 100, 145), w('b2', 500, 165), w('b3', 900, 185),
    ];
    final rows = buildRows(words, slope: 0.05);
    expect(rows.length, 2);
    expect(rows[0].map((c) => c.text).toList(), ['a1', 'a2', 'a3']);
    expect(rows[1].map((c) => c.text).toList(), ['b1', 'b2', 'b3']);
  });

  test('median slope needs enough lines', () {
    expect(medianSlope([]), 0);
    expect(medianSlope([0.04, 0.05, 0.06]), 0.05);
  });
}
