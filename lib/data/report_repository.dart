import 'package:drift/drift.dart';

import 'database.dart';
import 'tables/bill_items.dart';
import 'tables/bills.dart';
import 'tables/ledger_entries.dart';

/// Half-open range: [start, end).
class DateRange {
  const DateRange(this.start, this.end);
  final DateTime start;
  final DateTime end;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  factory DateRange.today(DateTime now) {
    final d = _day(now);
    return DateRange(d, DateTime(d.year, d.month, d.day + 1));
  }

  factory DateRange.yesterday(DateTime now) {
    final d = _day(now);
    return DateRange(DateTime(d.year, d.month, d.day - 1), d);
  }

  factory DateRange.last7Days(DateTime now) {
    final d = _day(now);
    return DateRange(DateTime(d.year, d.month, d.day - 6),
        DateTime(d.year, d.month, d.day + 1));
  }

  factory DateRange.thisMonth(DateTime now) => DateRange(
      DateTime(now.year, now.month, 1), DateTime(now.year, now.month + 1, 1));

  /// Both days included.
  factory DateRange.days(DateTime from, DateTime to) {
    final a = _day(from);
    final b = _day(to);
    return DateRange(a, DateTime(b.year, b.month, b.day + 1));
  }
}

class SalesSummary {
  const SalesSummary({
    required this.totalPaise,
    required this.billCount,
    required this.cashPaise,
    required this.upiPaise,
    required this.khataPaise,
    required this.profitPaise,
    required this.billsWithoutCost,
  });
  final int totalPaise;
  final int billCount;
  final int cashPaise;
  final int upiPaise;
  final int khataPaise;

  /// Null when no sold item in the period has a cost (never a wrong number).
  final int? profitPaise;

  /// Bills in the period with at least one item that has no cost recorded.
  final int billsWithoutCost;

  int get averagePaise => billCount == 0 ? 0 : totalPaise ~/ billCount;
}

class KhataSummary {
  const KhataSummary({
    required this.outstandingPaise,
    required this.collectedPaise,
    required this.topDebtors,
  });
  final int outstandingPaise;
  final int collectedPaise;
  final List<Customer> topDebtors;
}

class TopItem {
  const TopItem({
    required this.name,
    required this.pieces,
    required this.packs,
    required this.totalPieces,
    required this.profitPaise,
  });
  final String name;
  final int pieces;
  final int packs;

  /// Pieces + packs converted to pieces.
  final int totalPieces;

  /// Null when none of its lines has a cost.
  final int? profitPaise;
}

class DailySales {
  const DailySales(this.day, this.totalPaise);
  final DateTime day;
  final int totalPaise;
}

class ReportRepository {
  ReportRepository(this._db);
  final AppDatabase _db;

  /// THE ONE PLACE that decides which bills count in reports.
  /// Later: exclude cancelled bills here.
  Expression<bool> _validBill(Bills t, DateRange r) =>
      t.createdAt.isBiggerOrEqualValue(r.start) &
      t.createdAt.isSmallerThanValue(r.end);

  /// THE ONE PLACE that decides a bill's amount.
  /// Later: use the post-discount total here.
  int _billAmount(Bill b) => b.totalPaise;

  Future<List<Bill>> _bills(DateRange r) =>
      (_db.select(_db.bills)..where((t) => _validBill(t, r))).get();

  Future<List<BillItem>> _items(DateRange r) async {
    final rows = await (_db.select(_db.billItems).join([
      innerJoin(_db.bills, _db.bills.id.equalsExp(_db.billItems.billId)),
    ])
          ..where(_validBill(_db.bills, r)))
        .get();
    return rows.map((e) => e.readTable(_db.billItems)).toList();
  }

  Future<SalesSummary> summary(DateRange r) async {
    final bills = await _bills(r);
    final items = await _items(r);

    var total = 0, cash = 0, upi = 0, khata = 0;
    for (final b in bills) {
      final a = _billAmount(b);
      total += a;
      switch (b.paymentMethod) {
        case PaymentMethod.cash:
          cash += a;
        case PaymentMethod.upi:
          upi += a;
        case PaymentMethod.khata:
          khata += a;
      }
    }

    var profit = 0;
    var costed = 0;
    final uncosted = <int>{};
    for (final i in items) {
      final c = i.costPaise;
      if (c == null) {
        uncosted.add(i.billId);
      } else {
        profit += i.lineTotalPaise - c;
        costed++;
      }
    }

    return SalesSummary(
      totalPaise: total,
      billCount: bills.length,
      cashPaise: cash,
      upiPaise: upi,
      khataPaise: khata,
      profitPaise: costed == 0 ? null : profit,
      billsWithoutCost: uncosted.length,
    );
  }

  Future<KhataSummary> khata(DateRange r, {int topCount = 5}) async {
    final customers = await _db.select(_db.customers).get();
    var outstanding = 0;
    for (final c in customers) {
      if (c.balancePaise > 0) outstanding += c.balancePaise;
    }
    final debtors = customers.where((c) => c.balancePaise > 0).toList()
      ..sort((a, b) => b.balancePaise.compareTo(a.balancePaise));

    final entries = await (_db.select(_db.ledgerEntries)
          ..where((t) =>
              t.createdAt.isBiggerOrEqualValue(r.start) &
              t.createdAt.isSmallerThanValue(r.end)))
        .get();
    var collected = 0;
    for (final e in entries) {
      if (e.type != LedgerType.credit) collected += e.amountPaise;
    }

    return KhataSummary(
      outstandingPaise: outstanding,
      collectedPaise: collected,
      topDebtors: debtors.take(topCount).toList(),
    );
  }

  Future<List<TopItem>> _aggregateItems(DateRange r) async {
    final items = await _items(r);
    final products = {
      for (final p in await _db.select(_db.products).get()) p.id: p,
    };
    final map = <String, _Acc>{};
    for (final i in items) {
      final key = i.productId?.toString() ?? 'n:${i.productName}';
      final acc = map.putIfAbsent(key, () => _Acc(i.productName));
      if (i.unit == SaleUnit.pack) {
        acc.packs += i.quantity;
        final size = products[i.productId]?.packSize ?? 1;
        acc.totalPieces += i.quantity * (size < 1 ? 1 : size);
      } else {
        acc.pieces += i.quantity;
        acc.totalPieces += i.quantity;
      }
      final c = i.costPaise;
      if (c != null) acc.profit = (acc.profit ?? 0) + i.lineTotalPaise - c;
    }
    return map.values
        .map((a) => TopItem(
              name: a.name,
              pieces: a.pieces,
              packs: a.packs,
              totalPieces: a.totalPieces,
              profitPaise: a.profit,
            ))
        .toList();
  }

  Future<List<TopItem>> topByQuantity(DateRange r, {int limit = 5}) async {
    final all = await _aggregateItems(r);
    all.sort((a, b) => b.totalPieces.compareTo(a.totalPieces));
    return all.take(limit).toList();
  }

  /// Only items with a known profit.
  Future<List<TopItem>> topByProfit(DateRange r, {int limit = 5}) async {
    final all =
        (await _aggregateItems(r)).where((a) => a.profitPaise != null).toList();
    all.sort((a, b) => b.profitPaise!.compareTo(a.profitPaise!));
    return all.take(limit).toList();
  }

  /// Products at or below [threshold], lowest stock first.
  Future<List<Product>> lowStock(int threshold) => (_db.select(_db.products)
        ..where((t) => t.stock.isSmallerOrEqualValue(threshold))
        ..orderBy([(t) => OrderingTerm.asc(t.stock)]))
      .get();

  /// Stock valued at cost price (per piece).
  Future<int> stockValueAtCost() async {
    var sum = 0;
    for (final p in await _db.select(_db.products).get()) {
      final sz = p.packSize < 1 ? 1 : p.packSize;
      sum += (p.stock * p.costPaise * 2 + sz) ~/ (sz * 2);
    }
    return sum;
  }

  /// One entry per day in the range (zero for days without sales).
  Future<List<DailySales>> dailySales(DateRange r) async {
    final bills = await _bills(r);
    final byDay = <DateTime, int>{};
    for (final b in bills) {
      final d = DateTime(b.createdAt.year, b.createdAt.month, b.createdAt.day);
      byDay[d] = (byDay[d] ?? 0) + _billAmount(b);
    }
    final out = <DailySales>[];
    var d = r.start;
    while (d.isBefore(r.end)) {
      out.add(DailySales(d, byDay[d] ?? 0));
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return out;
  }
}

class _Acc {
  _Acc(this.name);
  final String name;
  int pieces = 0;
  int packs = 0;
  int totalPieces = 0;
  int? profit;
}
