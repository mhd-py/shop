import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop/data/bill_repository.dart';
import 'package:shop/data/database.dart';
import 'package:shop/data/tables/bill_items.dart';
import 'package:shop/data/tables/bills.dart';

void main() {
  late AppDatabase db;
  late BillRepository repo;
  late int productId;
  late int customerId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = BillRepository(db);
    productId = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'Soap, "Lux"',
        nameKey: 'soap lux',
        costPaise: 1000,
        sellPiecePaise: 1250,
        stock: const Value(10)));
    customerId = await db.into(db.customers).insert(
        CustomersCompanion.insert(name: 'Ravi', phone: '9876543210'));
  });
  tearDown(() => db.close());

  test('CSV has header, escaped item and bill total once', () async {
    expect(await repo.buildCsv(), isNull);
    await repo.checkout(
        lines: [CartLine(productId, SaleUnit.piece, 2)],
        method: PaymentMethod.cash,
        receivedPaise: 3000);
    final csv = (await repo.buildCsv())!;
    expect(csv, contains('Bill No,Date,Time'));
    expect(csv, contains('"Soap, ""Lux"""'));
    expect(csv, contains('25.00'));
  });

  test('clearAll keeps products, customers and Khata history', () async {
    await repo.checkout(
        lines: [CartLine(productId, SaleUnit.piece, 2)],
        method: PaymentMethod.khata,
        customerId: customerId);
    expect(await repo.billCount(), 1);
    expect(await repo.clearAll(), 1);
    expect(await repo.billCount(), 0);
    expect((await db.select(db.billItems).get()), isEmpty);
    expect((await db.select(db.products).get()).length, 1);
    final c = await db.select(db.customers).getSingle();
    expect(c.balancePaise, 2500);
    expect((await db.select(db.ledgerEntries).get()).length, 1);
  });
}
