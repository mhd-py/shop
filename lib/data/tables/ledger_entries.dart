import 'package:drift/drift.dart';

import 'customers.dart';

enum LedgerType { credit, partialPayment, fullPayment, billReturn }

/// Money is stored in paise.
class LedgerEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get customerId => integer().references(Customers, #id)();
  TextColumn get type => textEnum<LedgerType>()();
  IntColumn get amountPaise => integer()();

  /// Customer's balance right after this entry.
  IntColumn get balanceAfterPaise => integer()();
  TextColumn get note => text().nullable()();

  /// Filled by Billing later, when a credit comes from a bill.
  IntColumn get billId => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}