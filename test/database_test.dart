import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop/data/database.dart';
import 'package:shop/data/product_extensions.dart';
import 'package:shop/data/product_repository.dart';
import 'package:shop/data/settings_repository.dart';

ProductInput _rice({int stock = 10, int sell = 6500}) => ProductInput(
      name: 'Rice 1kg',
      packSize: 1,
      costPaise: 5500,
      sellPiecePaise: sell,
      stockPieces: stock,
    );

void main() {
  late AppDatabase db;
  late ProductRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ProductRepository(db);
  });
  tearDown(() => db.close());

  test('find product ignoring case and extra spaces', () async {
    await repo.add(_rice());
    final found = await repo.findByName('  rice   1KG ');
    expect(found, isNotNull);
    expect(found!.stock, 10);
  });

  test('database refuses two products with the same name', () async {
    await repo.add(_rice());
    expect(() => repo.add(_rice()), throwsA(anything));
  });

  test('merge adds stock and keeps old prices', () async {
    await repo.add(_rice());
    final existing = (await repo.findByName('rice 1kg'))!;
    await repo.merge(existing, _rice(stock: 5, sell: 7000),
        useNewPrices: false);
    final after = (await repo.findByName('rice 1kg'))!;
    expect(after.stock, 15);
    expect(after.sellPiecePaise, 6500);
  });

  test('merge can switch to the new prices', () async {
    await repo.add(_rice());
    final existing = (await repo.findByName('rice 1kg'))!;
    await repo.merge(existing, _rice(stock: 5, sell: 7000),
        useNewPrices: true);
    final after = (await repo.findByName('rice 1kg'))!;
    expect(after.stock, 15);
    expect(after.sellPiecePaise, 7000);
  });

  test('stock text shows packs and pieces', () {
    expect(formatStock(45, 20), '2 packs + 5 pcs');
    expect(formatStock(20, 20), '1 pack');
    expect(formatStock(7, 1), '7 pcs');
  });

  test('low stock limit defaults to 5 and can change', () async {
    final s = SettingsRepository(db);
    expect(await s.watchLowStockThreshold().first, 5);
    await s.setLowStockThreshold(8);
    expect(await s.watchLowStockThreshold().first, 8);
  });
}
