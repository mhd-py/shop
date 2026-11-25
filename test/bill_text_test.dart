import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop/data/bill_repository.dart';
import 'package:shop/data/database.dart';
import 'package:shop/data/tables/bill_items.dart';
import 'package:shop/data/tables/bills.dart';
import 'package:shop/features/history/bill_text.dart';

void main() {
  test('receipt text shows items, discount and total', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final pid = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'Soap',
        nameKey: 'soap',
        costPaise: 6000,
        sellPiecePaise: 10000));
    await (db.update(db.products)..where((t) => t.id.equals(pid)))
        .write(const ProductsCompanion(stock: Value(5)));
    final repo = BillRepository(db);
    final b = await repo.checkout(
        lines: [CartLine(pid, SaleUnit.piece, 2)],
        method: PaymentMethod.upi,
        discountPaise: 2000);
    final items = await db.select(db.billItems).get();
    final t = billText(b, items, shopName: 'Test Shop');
    expect(t, contains('Test Shop'));
    expect(t, contains('Soap'));
    expect(t, contains('Discount: -₹20.00'));
    expect(t, contains('Total: ₹180.00'));
    await db.close();
  });
}
