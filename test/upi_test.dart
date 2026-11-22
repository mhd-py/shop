import 'package:flutter_test/flutter_test.dart';
import 'package:shop/core/upi.dart';

void main() {
  test('UPI id validation', () {
    expect(validateUpiId('shop@upi'), isNull);
    expect(validateUpiId('9876543210@okaxis'), isNull);
    expect(validateUpiId(''), isNotNull);
    expect(validateUpiId('shop upi'), isNotNull);
    expect(validateUpiId('shop@'), isNotNull);
  });

  test('UPI link has the id, name and amount', () {
    final u = buildUpiUri(
        upiId: 'shop@upi', name: 'My Shop', amountPaise: 11050, note: 'Bill 1');
    expect(u.startsWith('upi://pay?pa=shop@upi&'), isTrue);
    expect(u, contains('pn=My%20Shop'));
    expect(u, contains('am=110.50'));
    expect(u, contains('cu=INR'));
  });
}
