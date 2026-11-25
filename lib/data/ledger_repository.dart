import 'package:drift/drift.dart';

import '../core/money.dart';
import 'customer_repository.dart';
import 'database.dart';
import 'tables/ledger_entries.dart';

class LedgerRepository {
  LedgerRepository(this._db);
  final AppDatabase _db;

  Stream<Customer?> watchCustomer(int id) => (_db.select(_db.customers)
        ..where((t) => t.id.equals(id)))
      .watchSingleOrNull();

  /// Newest first.
  Stream<List<LedgerEntry>> watchHistory(int customerId) =>
      (_db.select(_db.ledgerEntries)
            ..where((t) => t.customerId.equals(customerId))
            ..orderBy([(t) => OrderingTerm.desc(t.id)]))
          .watch();

  /// Adds to what the customer owes. Billing will pass [billId].
  Future<void> addCredit(int customerId, int amountPaise,
          {String? note, int? billId}) =>
      _post(customerId,
          credit: true, amountPaise: amountPaise, note: note, billId: billId);

  /// Partial payment. If it clears the balance it is recorded as full.
  Future<void> receivePayment(int customerId, int amountPaise,
          {String? note}) =>
      _post(customerId, credit: false, amountPaise: amountPaise, note: note);

  /// Pays the whole outstanding balance.
  Future<void> settleFull(int customerId, {String? note}) =>
      _post(customerId, credit: false, note: note);

  /// Lowers the balance after a bill cancel/return, never below zero.
  /// Returns the amount actually taken off. Call inside a transaction.
  Future<int> reduceForBill(int customerId, int amountPaise,
      {required int billId, String? note}) async {
    final c = await (_db.select(_db.customers)
          ..where((t) => t.id.equals(customerId)))
        .getSingleOrNull();
    if (c == null || c.balancePaise <= 0 || amountPaise <= 0) return 0;
    final take = amountPaise < c.balancePaise ? amountPaise : c.balancePaise;
    final after = c.balancePaise - take;
    await _db.into(_db.ledgerEntries).insert(LedgerEntriesCompanion.insert(
          customerId: customerId,
          type: LedgerType.billReturn,
          amountPaise: take,
          balanceAfterPaise: after,
          note: Value(note),
          billId: Value(billId),
        ));
    await (_db.update(_db.customers)..where((t) => t.id.equals(customerId)))
        .write(CustomersCompanion(balancePaise: Value(after)));
    return take;
  }

  Future<void> _post(
    int customerId, {
    required bool credit,
    int? amountPaise,
    String? note,
    int? billId,
  }) =>
      _db.transaction(() async {
        final c = await (_db.select(_db.customers)
              ..where((t) => t.id.equals(customerId)))
            .getSingleOrNull();
        if (c == null) throw CustomerException('Customer not found');

        final amount = amountPaise ?? c.balancePaise;
        if (amount <= 0) {
          throw CustomerException(
              credit ? 'Enter an amount above zero' : 'Nothing is owed');
        }
        if (!credit && amount > c.balancePaise) {
          throw CustomerException(
              'Payment is more than the ${formatRupees(c.balancePaise)} owed');
        }

        final after =
            credit ? c.balancePaise + amount : c.balancePaise - amount;
        final type = credit
            ? LedgerType.credit
            : after == 0
                ? LedgerType.fullPayment
                : LedgerType.partialPayment;
        final cleanNote = note?.trim();

        await _db.into(_db.ledgerEntries).insert(LedgerEntriesCompanion.insert(
              customerId: customerId,
              type: type,
              amountPaise: amount,
              balanceAfterPaise: after,
              note: Value(
                  cleanNote == null || cleanNote.isEmpty ? null : cleanNote),
              billId: Value(billId),
            ));
        await (_db.update(_db.customers)
              ..where((t) => t.id.equals(customerId)))
            .write(CustomersCompanion(balancePaise: Value(after)));
      });
}