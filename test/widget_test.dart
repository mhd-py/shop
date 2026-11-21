import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop/data/database.dart';
import 'package:shop/main.dart';

void main() {
  testWidgets('App shows four navigation tabs', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(ShopApp(database: db));
    for (final label in ['Billing', 'Inventory', 'Khata', 'Settings']) {
      expect(find.text(label), findsWidgets);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
