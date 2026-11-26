import 'package:flutter_test/flutter_test.dart';
import 'package:shop/features/scan/bill_parser.dart';

OcrCell c(String text, double center) {
  final w = text.length * 3.5;
  return OcrCell(text, center - w, center + w);
}

void main() {
  final parser = BillParser();

  test('header words are recognised, with one OCR mistake allowed', () {
    expect(BillParser.fieldOf('Particulars'), Field.name);
    expect(BillParser.fieldOf('PRODUCT DESC'), Field.name);
    expect(BillParser.fieldOf('Partlcular'), Field.name);
    expect(BillParser.fieldOf('Unit Price'), Field.rate);
    expect(BillParser.fieldOf('NET AMT'), Field.total);
    expect(BillParser.fieldOf('M.R.P'), Field.mrp);
    expect(BillParser.fieldOf('CBB/PKT'), Field.qty);
    expect(BillParser.fieldOf('Taxable Amount'), Field.other);
    expect(BillParser.fieldOf('HSN'), Field.other);
  });

  test('Trends Today bill (stationery)', () {
    final bill = parser.parse([
      [
        c('Sl #', 85), c('Particular', 143), c('HSN', 365), c('Mrp', 423),
        c('Qty', 500), c('Rate', 553), c('Gross', 607), c('Gst', 668),
        c('Total', 740),
      ],
      [c('Val', 607), c('%', 668)],
      [
        c('1', 103), c('INDEX 65 GSM A4 500PCS PKT', 222), c('4802', 350),
        c('324.00', 430), c('1.0', 478), c('177.97', 545), c('177.97', 598),
        c('18.0', 672), c('210.01', 757),
      ],
      [
        c('2', 103), c('FC SCALE 15CM', 150), c('9017202', 365),
        c('5.00', 430), c('10.0', 478), c('3.18', 545), c('31.78', 598),
        c('18.0', 672), c('37.50', 757),
      ],
      [
        c('3', 103), c('BALAJI WAX CRAYONS MRP', 220), c('9609100', 365),
        c('12.00', 430), c('10.0', 478), c('7.00', 545), c('70.00', 598),
        c('0.0', 672), c('70.00', 757),
      ],
      [c('12/-', 130)],
      [c('Total Amount', 585), c('279.75', 750)],
      [c('TOTAL', 560), c('318.00', 750)],
    ]);
    expect(bill.problem, isNull);
    expect(bill.lines.length, 3);
    expect(bill.lines[0].name, 'INDEX 65 GSM A4 500PCS PKT');
    expect(bill.lines[0].qty, 1);
    expect(bill.lines[0].mrpPaise, 32400);
    expect(bill.lines[0].unitCostPaise, 21001);
    expect(bill.lines[1].qty, 10);
    expect(bill.lines[1].unitCostPaise, 375);
    expect(bill.lines[2].name, 'BALAJI WAX CRAYONS MRP 12/-');
    expect(bill.lines[2].unitCostPaise, 700);
    expect(bill.lines.any((l) => l.needsReview), isFalse);
    expect(bill.totalsChecked, isTrue);
    expect(bill.totalsMatch, isTrue);
  });

  test('Veegeo bill (many columns)', () {
    List<OcrCell> item(String mrp, String name, String hsn, String qty,
            String gross, String cgst, String total) =>
        [
          c(mrp, 120), c(name, 230), c(hsn, 367), c(qty, 415),
          c('3.09', 462), c(gross, 520), c('0.00', 570), c(gross, 621),
          c('9.00', 665), c(cgst, 705), c('9.00', 745), c(cgst, 776),
          c(total, 825),
        ];
    final bill = parser.parse([
      [
        c('SI No', 85), c('MRP', 115), c('PARTICULARS', 190),
        c('HSN SAC', 367), c('Qty', 415), c('Unit Price', 462),
        c('Gross Value', 520), c('Cash Dis', 570), c('Taxable Amount', 621),
        c('CGST %', 665), c('CGST Amt', 705), c('SGST %', 745),
        c('SGST Amt', 776), c('Total', 825),
      ],
      [
        c('120.00', 120), c('DABUR PASTE 50G(RS20*6+1)', 230),
        c('33061020', 367), c('2', 415), c('97.15', 462), c('194.30', 520),
        c('0.00', 570), c('194.30', 621), c('2.50', 665), c('4.85', 705),
        c('2.50', 745), c('4.85', 776), c('204.00', 825),
      ],
      item('5.00', 'WIN TOTEM P5 BL BALL PEN (5)', '96081019', '10', '30.94',
          '2.78', '36.50'),
      item('5.00', 'WIN TOTEM P5 BK BALL PEN (5)', '96081019', '20', '61.88',
          '5.56', '73.00'),
      item('5.00', 'WIN TOTEM P5 RED BALL PEN (5)', '96081019', '10', '30.94',
          '2.78', '36.50'),
      [
        c('Total', 90), c('42', 415), c('318.06', 520), c('0.00', 570),
        c('318.06', 621), c('15.97', 705), c('15.97', 776), c('350.00', 825),
      ],
    ]);
    expect(bill.problem, isNull);
    expect(bill.lines.length, 4);
    expect(bill.lines[0].qty, 2);
    expect(bill.lines[0].unitCostPaise, 10200);
    expect(bill.lines[1].name, 'WIN TOTEM P5 BL BALL PEN (5)');
    expect(bill.lines[1].qty, 10);
    expect(bill.lines[2].qty, 20);
    expect(bill.lines.any((l) => l.needsReview), isFalse);
    expect(bill.totalsMatch, isTrue);
  });

  test('a bad row is flagged, and totals mismatch is reported', () {
    final bill = parser.parse([
      [c('Item', 100), c('Qty', 300), c('Rate', 360), c('Total', 420)],
      [c('SOAP', 100), c('10', 300), c('20.00', 360), c('900.00', 420)],
      [c('Total', 100), c('200.00', 420)],
    ]);
    expect(bill.lines.single.needsReview, isTrue);
    expect(bill.totalsChecked, isTrue);
    expect(bill.totalsMatch, isFalse);
  });

  test('no table gives a plain message', () {
    final bill = parser.parse([
      [c('Hello', 10), c('World', 90)],
    ]);
    expect(bill.problem, isNotNull);
    expect(bill.lines, isEmpty);
  });
}
