import 'package:flutter_test/flutter_test.dart';
import 'package:shop/features/scan/product_matcher.dart';

void main() {
  test('matching an empty name (a newly added line) does not crash', () {
    expect(() => ProductMatcher([]).match(''), returnsNormally);
    expect(() => ProductMatcher([]).match('   '), returnsNormally);
  });
}
