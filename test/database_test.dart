import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop/data/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('insert and read a product', () async {
    await db.into(db.products).insert(
          ProductsCompanion.insert(
            name: 'Rice 1kg',
            nameKey: 'rice 1kg',
            pricePaise: 6000,
          ),
        );
    final all = await db.select(db.products).get();
    expect(all.length, 1);
    expect(all.first.pricePaise, 6000);
    expect(all.first.stock, 0);
  });
}
