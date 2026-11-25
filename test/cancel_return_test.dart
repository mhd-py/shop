import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop/data/bill_repository.dart';
import 'package:shop/data/database.dart';
import 'package:shop/data/ledger_repository.dart';
import 'package:shop/data/report_repository.dart';
import 'package:shop/data/tables/bill_items.dart';
import 'package:shop/data/tables/bills.dart';
import 'package:shop/data/tables/ledger_entries.dart';

void main() {
  late AppDatabase db;
  late BillRepository repo;
  late int pid;

  Future<int> stock() async => (await (db.select(db.products)
            ..where((t) => t.id.equals(pid)))
          .getSingle())
      .stock;
  Future<int> balance(int cid) async => (await (db.select(db.customers)
            ..where((t) => t.id.equals(cid)))
          .getSingle())
      .balancePaise;

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

  test('cancel cash bill restores stock and hands back everything', () async {
    final b = await repo.checkout(
        lines: [CartLine(pid, SaleUnit.piece, 2)],
        method: PaymentMethod.cash,
        receivedPaise: 20000);
    expect(await stock(), 8);
    final r = await repo.cancelBill(b.id);
    expect(await stock(), 10);
    expect(r.handBackPaise, 20000);
    expect(r.toKhataPaise, 0);
    expect(() => repo.cancelBill(b.id), throwsA(isA<BillException>()));
    final s = await ReportRepository(db).summary(DateRange.today(DateTime.now()));
    expect(s.billCount, 0);
    expect(s.totalPaise, 0);
  });

  test('cancel khata bill lowers balance and logs it', () async {
    final cid = await db.into(db.customers).insert(
        CustomersCompanion.insert(name: 'Ravi', phone: '9876543210'));
    final b = await repo.checkout(
        lines: [CartLine(pid, SaleUnit.piece, 2)],
        method: PaymentMethod.khata,
        customerId: cid);
    final r = await repo.cancelBill(b.id);
    expect(r.toKhataPaise, 20000);
    expect(r.handBackPaise, 0);
    expect(await balance(cid), 0);
    final hist = await db.select(db.ledgerEntries).get();
    expect(hist.last.type, LedgerType.billReturn);
  });

  test('cancel after part payment never makes balance negative', () async {
    final cid = await db.into(db.customers).insert(
        CustomersCompanion.insert(name: 'Ravi', phone: '9876543210'));
    final b = await repo.checkout(
        lines: [CartLine(pid, SaleUnit.piece, 2)],
        method: PaymentMethod.khata,
        customerId: cid);
    await LedgerRepository(db).receivePayment(cid, 5000);
    final r = await repo.cancelBill(b.id);
    expect(r.toKhataPaise, 15000);
    expect(r.handBackPaise, 5000);
    expect(await balance(cid), 0);
  });

  test('return shares the discount and restores stock', () async {
    final b = await repo.checkout(
        lines: [CartLine(pid, SaleUnit.piece, 2)],
        method: PaymentMethod.upi,
        discountPaise: 4000);
    final item = await db.select(db.billItems).getSingle();
    final r1 = await repo.returnItems(b.id, {item.id: 1});
    expect(r1.refundPaise, 8000);
    expect(await stock(), 9);
    final r2 = await repo.returnItems(b.id, {item.id: 1});
    expect(r2.refundPaise, 8000);
    expect(await stock(), 10);
    final bill = await (db.select(db.bills)..where((t) => t.id.equals(b.id)))
        .getSingle();
    expect(bill.returnedPaise, 16000);
    expect(() => repo.returnItems(b.id, {item.id: 1}),
        throwsA(isA<BillException>()));
  });

  test('returns reduce report sales and profit', () async {
    final b = await repo.checkout(
        lines: [CartLine(pid, SaleUnit.piece, 2)],
        method: PaymentMethod.cash,
        receivedPaise: 20000);
    final item = await db.select(db.billItems).getSingle();
    await repo.returnItems(b.id, {item.id: 1});
    final s = await ReportRepository(db).summary(DateRange.today(DateTime.now()));
    expect(s.totalPaise, 10000);
    expect(s.profitPaise, 4000);
  });

  test('khata return lowers balance by the refund', () async {
    final cid = await db.into(db.customers).insert(
        CustomersCompanion.insert(name: 'Ravi', phone: '9876543210'));
    final b = await repo.checkout(
        lines: [CartLine(pid, SaleUnit.piece, 3)],
        method: PaymentMethod.khata,
        customerId: cid);
    final item = await db.select(db.billItems).getSingle();
    await repo.returnItems(b.id, {item.id: 1});
    expect(await balance(cid), 20000);
  });
}
