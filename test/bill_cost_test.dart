import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop/data/bill_repository.dart';
import 'package:shop/data/database.dart';
import 'package:shop/data/tables/bills.dart';
import 'package:shop/data/tables/bill_items.dart';

void main() {
  test('checkout stores the line cost snapshot', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final id = await db.into(db.products).insert(ProductsCompanion.insert(
          name: 'Biscuit',
          nameKey: 'biscuit',
          packSize: const Value(10),
          costPaise: 5000,
          sellPiecePaise: 800,
          sellPackPaise: const Value(7500),
          stock: const Value(100),
        ));
    await BillRepository(db).checkout(
      lines: [
        CartLine(id, SaleUnit.piece, 3),
        CartLine(id, SaleUnit.pack, 1),
      ],
      method: PaymentMethod.cash,
      receivedPaise: 100000,
    );
    final items = await (db.select(db.billItems)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    expect(items[0].costPaise, 1500); // 3 pieces of 500 each
    expect(items[1].costPaise, 5000); // 1 pack
  });
}
