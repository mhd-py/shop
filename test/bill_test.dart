import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop/data/bill_repository.dart';
import 'package:shop/data/customer_repository.dart';
import 'package:shop/data/database.dart';
import 'package:shop/data/product_repository.dart';
import 'package:shop/data/tables/bill_items.dart';
import 'package:shop/data/tables/bills.dart';

void main() {
  late AppDatabase db;
  late BillRepository bills;
  late ProductRepository products;
  late CustomerRepository customers;
  late DateTime now;
  late int biscuit; // pack of 10, 50 pieces in stock
  late int pen; // single items, 5 in stock

  Future<int> stockOf(int id) async => (await (db.select(db.products)
            ..where((t) => t.id.equals(id)))
          .getSingle())
      .stock;

  Future<int> addCustomer() async {
    await customers.add('Ravi', '9876543210');
    return (await customers.watchAll().first).single.id;
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime(2026, 11, 21, 10);
    bills = BillRepository(db, clock: () => now);
    products = ProductRepository(db);
    customers = CustomerRepository(db);
    await products.add(const ProductInput(
        name: 'Biscuit',
        packSize: 10,
        costPaise: 8000,
        sellPiecePaise: 1000,
        sellPackPaise: 9500,
        stockPieces: 50));
    await products.add(const ProductInput(
        name: 'Pen',
        packSize: 1,
        costPaise: 300,
        sellPiecePaise: 500,
        stockPieces: 5));
    biscuit = (await products.findByName('Biscuit'))!.id;
    pen = (await products.findByName('Pen'))!.id;
  });
  tearDown(() => db.close());

  test('checkout saves items and deducts stock (pack = packSize pieces)',
      () async {
    final bill = await bills.checkout(
      method: PaymentMethod.upi,
      lines: [
        CartLine(biscuit, SaleUnit.piece, 3),
        CartLine(biscuit, SaleUnit.pack, 1),
        CartLine(pen, SaleUnit.piece, 2),
      ],
    );
    expect(bill.totalPaise, 3000 + 9500 + 1000);
    expect(await stockOf(biscuit), 37);
    expect(await stockOf(pen), 3);
    final items = await db.select(db.billItems).get();
    expect(items.length, 3);
    expect(items[1].unit, SaleUnit.pack);
    expect(items[1].lineTotalPaise, 9500);
    expect(items[1].productName, 'Biscuit');
  });

  test('bill numbers count per day', () async {
    final a = await bills.checkout(
        method: PaymentMethod.upi, lines: [CartLine(pen, SaleUnit.piece, 1)]);
    final b = await bills.checkout(
        method: PaymentMethod.upi, lines: [CartLine(pen, SaleUnit.piece, 1)]);
    now = DateTime(2026, 11, 22, 9);
    final c = await bills.checkout(
        method: PaymentMethod.upi, lines: [CartLine(pen, SaleUnit.piece, 1)]);
    expect(a.billNumber, '20261121-001');
    expect(b.billNumber, '20261121-002');
    expect(c.billNumber, '20261122-001');
  });

  test('cash calculates change and rejects too little', () async {
    final lines = [CartLine(biscuit, SaleUnit.pack, 1)];
    final bill = await bills.checkout(
        method: PaymentMethod.cash, lines: lines, receivedPaise: 10000);
    expect(bill.changePaise, 500);
    expect(
        () => bills.checkout(
            method: PaymentMethod.cash, lines: lines, receivedPaise: 9000),
        throwsA(isA<BillException>()));
  });

  test('cart cannot exceed stock, even across piece and pack lines', () async {
    expect(
        () => bills.checkout(
            method: PaymentMethod.upi,
            lines: [CartLine(pen, SaleUnit.piece, 6)]),
        throwsA(isA<BillException>()));
    expect(
        () => bills.checkout(method: PaymentMethod.upi, lines: [
              CartLine(biscuit, SaleUnit.piece, 45),
              CartLine(biscuit, SaleUnit.pack, 1),
            ]),
        throwsA(isA<BillException>()));
    expect(await db.select(db.bills).get(), isEmpty);
    expect(await stockOf(biscuit), 50);
  });

  test('khata bill adds credit linked to the bill', () async {
    final cid = await addCustomer();
    final bill = await bills.checkout(
        method: PaymentMethod.khata,
        customerId: cid,
        lines: [CartLine(biscuit, SaleUnit.pack, 1)]);
    final c = await (db.select(db.customers)..where((t) => t.id.equals(cid)))
        .getSingle();
    expect(c.balancePaise, 9500);
    final entry = await db.select(db.ledgerEntries).getSingle();
    expect(entry.billId, bill.id);
    expect(entry.note, 'Bill ${bill.billNumber}');
    expect(bill.customerName, 'Ravi');
    expect(
        () => bills.checkout(
            method: PaymentMethod.khata,
            lines: [CartLine(pen, SaleUnit.piece, 1)]),
        throwsA(isA<BillException>()));
  });

  test('a failure at the very end rolls back everything', () async {
    final cid = await addCustomer();
    await expectLater(
      bills.checkout(
        method: PaymentMethod.khata,
        customerId: cid,
        lines: [CartLine(biscuit, SaleUnit.pack, 2)],
        debugBeforeCommit: () async => throw BillException('boom'),
      ),
      throwsA(isA<BillException>()),
    );
    expect(await db.select(db.bills).get(), isEmpty);
    expect(await db.select(db.billItems).get(), isEmpty);
    expect(await db.select(db.ledgerEntries).get(), isEmpty);
    expect(await stockOf(biscuit), 50);
    final c = await (db.select(db.customers)..where((t) => t.id.equals(cid)))
        .getSingle();
    expect(c.balancePaise, 0);
  });
}
