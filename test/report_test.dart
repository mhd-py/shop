import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop/data/bill_repository.dart';
import 'package:shop/data/database.dart';
import 'package:shop/data/ledger_repository.dart';
import 'package:shop/data/report_repository.dart';
import 'package:shop/data/tables/bill_items.dart';
import 'package:shop/data/tables/bills.dart';

void main() {
  late AppDatabase db;
  late ReportRepository reports;
  late int productId;
  late int customerId;
  final today = DateTime(2026, 11, 23, 10);
  final range = DateRange.today(today);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    reports = ReportRepository(db);
    productId = await db.into(db.products).insert(ProductsCompanion.insert(
          name: 'Biscuit',
          nameKey: 'biscuit',
          packSize: const Value(10),
          costPaise: 5000,
          sellPiecePaise: 800,
          sellPackPaise: const Value(7500),
          stock: const Value(100),
        ));
    customerId = await db
        .into(db.customers)
        .insert(CustomersCompanion.insert(name: 'Ravi', phone: '9876543210'));
  });
  tearDown(() => db.close());

  Future<void> sell(DateTime at, PaymentMethod m, List<CartLine> lines) async {
    await BillRepository(db, clock: () => at).checkout(
      lines: lines,
      method: m,
      receivedPaise: m == PaymentMethod.cash ? 1000000 : null,
      customerId: m == PaymentMethod.khata ? customerId : null,
    );
  }

  test('summary: totals, payment split, profit', () async {
    await sell(today, PaymentMethod.cash,
        [CartLine(productId, SaleUnit.piece, 3)]); // 2400, cost 1500
    await sell(today, PaymentMethod.upi,
        [CartLine(productId, SaleUnit.pack, 1)]); // 7500, cost 5000
    await sell(today, PaymentMethod.khata,
        [CartLine(productId, SaleUnit.piece, 2)]); // 1600, cost 1000
    final s = await reports.summary(range);
    expect(s.totalPaise, 11500);
    expect(s.billCount, 3);
    expect(s.averagePaise, 3833);
    expect(s.cashPaise, 2400);
    expect(s.upiPaise, 7500);
    expect(s.khataPaise, 1600);
    expect(s.profitPaise, 4000);
    expect(s.billsWithoutCost, 0);
  });

  test('period filter excludes other days', () async {
    await sell(DateTime(2026, 11, 22, 10), PaymentMethod.cash,
        [CartLine(productId, SaleUnit.piece, 1)]);
    await sell(today, PaymentMethod.cash,
        [CartLine(productId, SaleUnit.piece, 1)]);
    expect((await reports.summary(range)).billCount, 1);
    expect((await reports.summary(DateRange.yesterday(today))).billCount, 1);
    expect((await reports.summary(DateRange.last7Days(today))).billCount, 2);
  });

  test('older bills without cost never give a wrong profit', () async {
    final id = await db.into(db.bills).insert(BillsCompanion.insert(
          billNumber: '20261120-001',
          paymentMethod: PaymentMethod.cash,
          totalPaise: 1000,
          createdAt: Value(DateTime(2026, 11, 20, 10)),
        ));
    await db.into(db.billItems).insert(BillItemsCompanion.insert(
          billId: id,
          productName: 'Old',
          unit: SaleUnit.piece,
          quantity: 1,
          unitPricePaise: 1000,
          lineTotalPaise: 1000,
        ));
    final week = DateRange.last7Days(today);
    var s = await reports.summary(week);
    expect(s.profitPaise, isNull);
    expect(s.billsWithoutCost, 1);

    await sell(today, PaymentMethod.cash,
        [CartLine(productId, SaleUnit.piece, 3)]);
    s = await reports.summary(week);
    expect(s.profitPaise, 900); // only the bill that has a cost
    expect(s.billsWithoutCost, 1);
  });

  test('khata: outstanding, top debtors, collected', () async {
    await sell(today, PaymentMethod.khata,
        [CartLine(productId, SaleUnit.piece, 2)]); // owes 1600
    await LedgerRepository(db).receivePayment(customerId, 600);
    final k = await reports.khata(DateRange.today(DateTime.now()));
    expect(k.outstandingPaise, 1000);
    expect(k.collectedPaise, 600);
    expect(k.topDebtors.single.name, 'Ravi');
  });

  test('top items by quantity and profit', () async {
    await sell(today, PaymentMethod.cash, [
      CartLine(productId, SaleUnit.piece, 3),
      CartLine(productId, SaleUnit.pack, 1),
    ]);
    final q = await reports.topByQuantity(range);
    expect(q.single.pieces, 3);
    expect(q.single.packs, 1);
    expect(q.single.totalPieces, 13);
    final p = await reports.topByProfit(range);
    expect(p.single.profitPaise, 3400); // 900 + 2500
  });

  test('low stock, stock value, daily sales', () async {
    await db.into(db.products).insert(ProductsCompanion.insert(
          name: 'Soap',
          nameKey: 'soap',
          costPaise: 2000,
          sellPiecePaise: 2500,
          stock: const Value(2),
        ));
    final low = await reports.lowStock(5);
    expect(low.single.name, 'Soap');
    // Biscuit: 100 pieces at 500 = 50000. Soap: 2 at 2000 = 4000.
    expect(await reports.stockValueAtCost(), 54000);

    await sell(today, PaymentMethod.cash,
        [CartLine(productId, SaleUnit.piece, 1)]);
    final daily = await reports.dailySales(DateRange.last7Days(today));
    expect(daily.length, 7);
    expect(daily.last.totalPaise, 800);
    expect(daily.first.totalPaise, 0);
  });
}
