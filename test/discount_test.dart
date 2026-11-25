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
  late int pid;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = BillRepository(db);
    pid = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'Soap',
        nameKey: 'soap',
        costPaise: 6000,
        sellPiecePaise: 10000,
        stock: const Value(10)));
  });
  tearDown(() => db.close());

  test('cash bill with discount stores reduced total and right change',
      () async {
    final b = await repo.checkout(
      lines: [CartLine(pid, SaleUnit.piece, 2)],
      method: PaymentMethod.cash,
      receivedPaise: 20000,
      discountPaise: 2500,
    );
    expect(b.totalPaise, 17500);
    expect(b.discountPaise, 2500);
    expect(b.changePaise, 2500);
  });

  test('discount equal to or above subtotal is rejected', () async {
    expect(
      () => repo.checkout(
        lines: [CartLine(pid, SaleUnit.piece, 1)],
        method: PaymentMethod.upi,
        discountPaise: 10000,
      ),
      throwsA(isA<BillException>()),
    );
    expect(await repo.billCount(), 0);
  });

  test('khata credit uses the discounted total', () async {
    final cid = await db.into(db.customers).insert(
        CustomersCompanion.insert(name: 'Ravi', phone: '9876543210'));
    await repo.checkout(
      lines: [CartLine(pid, SaleUnit.piece, 2)],
      method: PaymentMethod.khata,
      customerId: cid,
      discountPaise: 5000,
    );
    final c = await (db.select(db.customers)..where((t) => t.id.equals(cid)))
        .getSingle();
    expect(c.balancePaise, 15000);
  });
}
