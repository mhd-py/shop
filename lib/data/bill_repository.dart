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

class _Draft {
  _Draft(this.product, this.unit, this.quantity, this.price);
  final Product product;
  final SaleUnit unit;
  final int quantity;
  final int price;
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
          if (l.unit == SaleUnit.pack) {
            final packPrice = p.sellPackPaise;
            if (p.packSize <= 1 || packPrice == null) {
              throw BillException('${p.name} is not sold in packs');
            }
            price = packPrice;
            pieces = p.packSize * l.quantity;
          } else {
            price = p.sellPiecePaise;
            pieces = l.quantity;
          }
          needed[p.id] = (needed[p.id] ?? 0) + pieces;
          total += price * l.quantity;
          drafts.add(_Draft(p, l.unit, l.quantity, price));
        }

        for (final e in needed.entries) {
          final p = products[e.key]!;
          if (e.value > p.stock) {
            throw BillException('Only ${p.stockText} of ${p.name} in stock');
          }
        }
        if (total <= 0) throw BillException('Bill total must be above zero');

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
        'Quantity', 'Unit Price', 'Line Total', 'Bill Total', 'Received',
        'Change',
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
          first && b.receivedPaise != null ? paiseToPlain(b.receivedPaise!) : '',
          first && b.changePaise != null ? paiseToPlain(b.changePaise!) : '',
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
