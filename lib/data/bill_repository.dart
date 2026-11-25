import 'package:drift/drift.dart';

import '../core/csv.dart';
import 'database.dart';
import 'ledger_repository.dart';
import 'product_extensions.dart';
import 'tables/bill_items.dart';
import 'tables/bills.dart';

/// A message that is safe to show to the shopkeeper.
class BillException implements Exception {
  BillException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One cart line. Prices are read from the database at checkout.
class CartLine {
  const CartLine(this.productId, this.unit, this.quantity);
  final int productId;
  final SaleUnit unit;
  final int quantity;
}

/// What to do with money after a cancel or return.
class RefundResult {
  const RefundResult(this.refundPaise, this.toKhataPaise);
  final int refundPaise;

  /// Taken off the customer's Khata balance.
  final int toKhataPaise;

  /// Cash/UPI to give back to the customer.
  int get handBackPaise => refundPaise - toKhataPaise;
}

class _Draft {
  _Draft(this.product, this.unit, this.quantity, this.price, this.cost);
  final Product product;
  final SaleUnit unit;
  final int quantity;
  final int price;
  final int cost;
}

class BillRepository {
  BillRepository(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now,
        _ledger = LedgerRepository(_db);

  final AppDatabase _db;
  final DateTime Function() _clock;
  final LedgerRepository _ledger;

  /// Creates the bill, its items, deducts stock and (for Khata) posts the
  /// credit, all in ONE transaction. Any error undoes everything.
  /// [debugBeforeCommit] exists only so tests can force a late failure.
  Future<Bill> checkout({
    required List<CartLine> lines,
    required PaymentMethod method,
    int? receivedPaise,
    int? customerId,
    int discountPaise = 0,
    Future<void> Function()? debugBeforeCommit,
  }) =>
      _db.transaction(() async {
        if (lines.isEmpty) throw BillException('The cart is empty');

        final products = <int, Product>{};
        final needed = <int, int>{}; // productId -> pieces
        final drafts = <_Draft>[];
        var total = 0;

        for (final l in lines) {
          if (l.quantity <= 0) throw BillException('Quantity must be 1 or more');
          var p = products[l.productId];
          if (p == null) {
            p = await (_db.select(_db.products)
                  ..where((t) => t.id.equals(l.productId)))
                .getSingleOrNull();
            if (p == null) throw BillException('A product is no longer available');
            products[p.id] = p;
          }
          final int price;
          final int pieces;
          final int cost;
          if (l.unit == SaleUnit.pack) {
            final packPrice = p.sellPackPaise;
            if (p.packSize <= 1 || packPrice == null) {
              throw BillException('${p.name} is not sold in packs');
            }
            price = packPrice;
            cost = p.costPaise * l.quantity;
            pieces = p.packSize * l.quantity;
          } else {
            price = p.sellPiecePaise;
            final sz = p.packSize < 1 ? 1 : p.packSize;
            cost = (p.costPaise * l.quantity * 2 + sz) ~/ (sz * 2);
            pieces = l.quantity;
          }
          needed[p.id] = (needed[p.id] ?? 0) + pieces;
          total += price * l.quantity;
          drafts.add(_Draft(p, l.unit, l.quantity, price, cost));
        }

        for (final e in needed.entries) {
          final p = products[e.key]!;
          if (e.value > p.stock) {
            throw BillException('Only ${p.stockText} of ${p.name} in stock');
          }
        }
        if (total <= 0) throw BillException('Bill total must be above zero');
        if (discountPaise < 0) {
          throw BillException('Discount cannot be negative');
        }
        if (discountPaise >= total) {
          throw BillException('Discount must be less than the bill total');
        }
        total -= discountPaise;

        int? received;
        int? change;
        Customer? customer;
        switch (method) {
          case PaymentMethod.cash:
            if (receivedPaise == null || receivedPaise < total) {
              throw BillException('Received amount is less than the total');
            }
            received = receivedPaise;
            change = receivedPaise - total;
          case PaymentMethod.upi:
            break;
          case PaymentMethod.khata:
            if (customerId == null) throw BillException('Select a customer');
            customer = await (_db.select(_db.customers)
                  ..where((t) => t.id.equals(customerId)))
                .getSingleOrNull();
            if (customer == null) throw BillException('Customer not found');
        }

        final now = _clock();
        final number = await _nextNumber(now);
        final billId = await _db.into(_db.bills).insert(BillsCompanion.insert(
              billNumber: number,
              paymentMethod: method,
              totalPaise: total,
              discountPaise: Value(discountPaise),
              receivedPaise: Value(received),
              changePaise: Value(change),
              customerId: Value(customer?.id),
              customerName: Value(customer?.name),
              createdAt: Value(now),
            ));

        for (final d in drafts) {
          await _db.into(_db.billItems).insert(BillItemsCompanion.insert(
                billId: billId,
                productId: Value(d.product.id),
                productName: d.product.name,
                unit: d.unit,
                quantity: d.quantity,
                unitPricePaise: d.price,
                lineTotalPaise: d.price * d.quantity,
                costPaise: Value(d.cost),
              ));
        }

        for (final e in needed.entries) {
          final p = products[e.key]!;
          await (_db.update(_db.products)..where((t) => t.id.equals(p.id)))
              .write(ProductsCompanion(stock: Value(p.stock - e.value)));
        }

        if (customer != null) {
          await _ledger.addCredit(customer.id, total,
              note: 'Bill $number', billId: billId);
        }

        if (debugBeforeCommit != null) await debugBeforeCommit();

        return (_db.select(_db.bills)..where((t) => t.id.equals(billId)))
            .getSingle();
      });

  /// Newest first.
  Stream<List<Bill>> watchBills() => (_db.select(_db.bills)
        ..orderBy([(t) => OrderingTerm.desc(t.id)]))
      .watch();

  Stream<Bill?> watchBill(int id) =>
      (_db.select(_db.bills)..where((t) => t.id.equals(id)))
          .watchSingleOrNull();

  Stream<List<BillItem>> watchItems(int billId) => (_db.select(_db.billItems)
        ..where((t) => t.billId.equals(billId))
        ..orderBy([(t) => OrderingTerm.asc(t.id)]))
      .watch();

  Future<Bill> _loadBill(int id) async {
    final b = await (_db.select(_db.bills)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (b == null) throw BillException('Bill not found');
    if (b.cancelledAt != null) throw BillException('This bill is cancelled');
    return b;
  }

  Future<void> _restock(BillItem i, int qty) async {
    final pid = i.productId;
    if (qty <= 0 || pid == null) return;
    final p = await (_db.select(_db.products)..where((t) => t.id.equals(pid)))
        .getSingleOrNull();
    if (p == null) return;
    final size = p.packSize < 1 ? 1 : p.packSize;
    final pieces = i.unit == SaleUnit.pack ? qty * size : qty;
    await (_db.update(_db.products)..where((t) => t.id.equals(pid)))
        .write(ProductsCompanion(stock: Value(p.stock + pieces)));
  }

  Future<RefundResult> _refund(Bill b, int refund, String note) async {
    var toKhata = 0;
    final cid = b.customerId;
    if (b.paymentMethod == PaymentMethod.khata && cid != null && refund > 0) {
      toKhata =
          await _ledger.reduceForBill(cid, refund, billId: b.id, note: note);
    }
    return RefundResult(refund, toKhata);
  }

  /// Cancels the whole bill: stock goes back, Khata balance is reduced.
  Future<RefundResult> cancelBill(int billId) => _db.transaction(() async {
        final b = await _loadBill(billId);
        final items = await (_db.select(_db.billItems)
              ..where((t) => t.billId.equals(billId)))
            .get();
        for (final i in items) {
          await _restock(i, i.quantity - i.returnedQty);
        }
        await (_db.update(_db.bills)..where((t) => t.id.equals(billId)))
            .write(BillsCompanion(cancelledAt: Value(_clock())));
        return _refund(b, b.totalPaise - b.returnedPaise,
            'Cancelled bill ${b.billNumber}');
      });

  /// Returns items. [qtyByItemId] maps BillItem id to quantity returned now.
  /// The refund is the price minus the item's share of the bill discount.
  Future<RefundResult> returnItems(int billId, Map<int, int> qtyByItemId) =>
      _db.transaction(() async {
        final b = await _loadBill(billId);
        final items = await (_db.select(_db.billItems)
              ..where((t) => t.billId.equals(billId)))
            .get();
        final subtotal = b.totalPaise + b.discountPaise;
        int net(BillItem i, int k) =>
            (i.unitPricePaise * k * b.totalPaise * 2 + subtotal) ~/
            (subtotal * 2);

        var refund = 0;
        var any = false;
        var allBack = true;
        for (final i in items) {
          final q = qtyByItemId[i.id] ?? 0;
          if (q < 0 || q > i.quantity - i.returnedQty) {
            throw BillException('Cannot return more than was sold');
          }
          if (q > 0) {
            any = true;
            refund += net(i, i.returnedQty + q) - net(i, i.returnedQty);
            await _restock(i, q);
            await (_db.update(_db.billItems)..where((t) => t.id.equals(i.id)))
                .write(BillItemsCompanion(returnedQty: Value(i.returnedQty + q)));
          }
          if (i.returnedQty + q < i.quantity) allBack = false;
        }
        if (!any) throw BillException('Select at least one item to return');
        final left = b.totalPaise - b.returnedPaise;
        if (allBack || refund > left) refund = left;
        await (_db.update(_db.bills)..where((t) => t.id.equals(billId)))
            .write(BillsCompanion(returnedPaise: Value(b.returnedPaise + refund)));
        return _refund(b, refund, 'Return, bill ${b.billNumber}');
      });

  Future<int> billCount() async {
    final c = _db.bills.id.count();
    final r = await (_db.selectOnly(_db.bills)..addColumns([c])).getSingle();
    return r.read(c) ?? 0;
  }

  /// One row per sold item. Null when there are no bills.
  Future<String?> buildCsv() async {
    final bills = await (_db.select(_db.bills)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    if (bills.isEmpty) return null;
    final items = await (_db.select(_db.billItems)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    final byBill = <int, List<BillItem>>{};
    for (final i in items) {
      byBill.putIfAbsent(i.billId, () => []).add(i);
    }
    String two(int n) => n.toString().padLeft(2, '0');
    final rows = <List<String>>[
      [
        'Bill No', 'Date', 'Time', 'Payment', 'Customer', 'Item', 'Unit',
        'Quantity', 'Unit Price', 'Line Total', 'Bill Total', 'Discount',
        'Received', 'Change', 'Status',
      ],
    ];
    for (final b in bills) {
      final d = b.createdAt;
      final date = '${d.year}-${two(d.month)}-${two(d.day)}';
      final time = '${two(d.hour)}:${two(d.minute)}';
      final lines = byBill[b.id] ?? const <BillItem>[];
      for (var n = 0; n < (lines.isEmpty ? 1 : lines.length); n++) {
        final i = lines.isEmpty ? null : lines[n];
        final first = n == 0;
        rows.add([
          b.billNumber,
          date,
          time,
          b.paymentMethod.name,
          b.customerName ?? '',
          i?.productName ?? '',
          i?.unit.name ?? '',
          i == null ? '' : '${i.quantity}',
          i == null ? '' : paiseToPlain(i.unitPricePaise),
          i == null ? '' : paiseToPlain(i.lineTotalPaise),
          first ? paiseToPlain(b.totalPaise) : '',
          first ? paiseToPlain(b.discountPaise) : '',
          first && b.receivedPaise != null ? paiseToPlain(b.receivedPaise!) : '',
          first && b.changePaise != null ? paiseToPlain(b.changePaise!) : '',
          first
              ? (b.cancelledAt != null
                  ? 'Cancelled'
                  : b.returnedPaise > 0
                      ? 'Part returned'
                      : 'Completed')
              : '',
        ]);
      }
    }
    return csvEncode(rows);
  }

  /// Deletes bills and bill items ONLY. Products, customers, Khata balances
  /// and Khata history are not touched. Returns the number of bills removed.
  Future<int> clearAll() async {
    final n = await _db.transaction(() async {
      await _db.delete(_db.billItems).go();
      return _db.delete(_db.bills).go();
    });
    try {
      await _db.customStatement('VACUUM'); // reclaim storage space
    } catch (_) {}
    return n;
  }

  Future<String> _nextNumber(DateTime d) async {
    String two(int n) => n.toString().padLeft(2, '0');
    final prefix = '${d.year}${two(d.month)}${two(d.day)}';
    final rows = await (_db.select(_db.bills)
          ..where((t) => t.billNumber.like('$prefix-%')))
        .get();
    var max = 0;
    for (final r in rows) {
      final n = int.tryParse(r.billNumber.split('-').last) ?? 0;
      if (n > max) max = n;
    }
    return '$prefix-${(max + 1).toString().padLeft(3, '0')}';
  }
}
