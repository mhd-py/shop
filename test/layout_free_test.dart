import 'package:flutter_test/flutter_test.dart';
import 'package:shop/features/scan/bill_parser.dart';

OcrCell t(String s, double l, double r) => OcrCell(s, l, r);
OcrCell n(String s, double center) => OcrCell(s, center - 20, center + 20);

void main() {
  // A bill with NO header row: columns are MRP, Qty, Rate, Amount.
  final rows = <List<OcrCell>>[
    [
      t('1', 10, 25), t('Parle', 50, 90), t('G', 95, 105), t('Biscuit', 110, 170),
      n('10', 300), n('12', 380), n('8.00', 460), n('96.00', 540),
    ],
    [t('Family', 50, 100), t('Pack', 105, 140)],
    [
      t('2', 10, 25), t('Dairy', 50, 90), t('Milk', 95, 130),
      t('100', 135, 160), t('gm', 165, 185),
      n('20', 300), n('6', 380), n('15.50', 460), n('93.00', 540),
    ],
    [
      t('3', 10, 25), t('Lays', 50, 90), t('Chips', 95, 140),
      t('Large', 145, 185),
      n('30', 300), n('10', 380), n('22.00', 460), n('231.00', 540),
    ],
    [t('Total', 50, 100), n('420.00', 540)],
  ];

  test('finds qty, rate, amount by maths when there is no header', () {
    final bill = BillParser().parse(rows);
    expect(bill.problem, isNull);
    expect(bill.lines.length, 3);
    expect(bill.lines.map((l) => l.qty).toList(), [12, 6, 10]);
    expect(bill.lines.map((l) => l.totalPaise).toList(), [9600, 9300, 23100]);
    expect(bill.lines.map((l) => l.ratePaise).toList(), [800, 1550, 2200]);
    expect(bill.lines.map((l) => l.mrpPaise).toList(), [1000, 2000, 3000]);
    expect(bill.totalsChecked, isTrue);
    expect(bill.totalsMatch, isTrue);
  });

  test('joins wrapped names and keeps numbers that belong to the name', () {
    final bill = BillParser().parse(rows);
    expect(bill.lines[0].name, 'Parle G Biscuit Family Pack');
    expect(bill.lines[1].name, 'Dairy Milk 100 gm');
  });

  test('text only gives a problem, not a crash', () {
    final bill = BillParser().parse([
      [t('Thank', 10, 50), t('you', 60, 90)],
    ]);
    expect(bill.problem, isNotNull);
  });
}
