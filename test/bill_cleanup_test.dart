import 'package:flutter_test/flutter_test.dart';
import 'package:shop/features/scan/bill_cleanup.dart';

void main() {
  group('splitGlued', () {
    test('Trends INDEX row: 10177.97 with total 210.01', () {
      final g = splitGlued('10177.97', 210.01)!;
      expect(g.qty, 1);
      expect(g.rate, closeTo(177.97, 0.001));
    });
    test('no split fits the total', () {
      expect(splitGlued('10177.97', 5000), isNull);
    });
    test('ordinary numbers are left alone', () {
      expect(splitGlued('3.18', 3.18), isNull);
      expect(splitGlued('210.01', 210.01), isNull);
    });
  });

  group('cleanBillName', () {
    test('Trends INDEX name', () {
      expect(cleanBillName('INDEX 6S GSM A4 500PCS PKT4802 10177.97'),
          'INDEX 6S GSM A4 500PCS');
    });
    test('glued serial removed only when it is the expected row', () {
      expect(cleanBillName('3BALAJI WAX CRAYONS MRP', expectedSerial: 3),
          'BALAJI WAX CRAYONS MRP');
      expect(cleanBillName('3BALAJI WAX CRAYONS MRP', expectedSerial: 5),
          '3BALAJI WAX CRAYONS MRP');
    });
    test('real names starting with a digit are kept', () {
      expect(cleanBillName('3M TAPE', expectedSerial: 3), '3M TAPE');
      expect(cleanBillName('FC SCALE 15CM', expectedSerial: 2),
          'FC SCALE 15CM');
    });
  });
}
