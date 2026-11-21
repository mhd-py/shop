import 'package:flutter_test/flutter_test.dart';
import 'package:shop/main.dart';

void main() {
  testWidgets('App shows four navigation tabs', (tester) async {
    await tester.pumpWidget(const ShopApp());
    for (final label in ['Billing', 'Inventory', 'Khata', 'Settings']) {
      expect(find.text(label), findsWidgets);
    }
  });
}
