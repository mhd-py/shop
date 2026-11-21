import 'package:drift/drift.dart';

enum PaymentMethod { cash, upi, khata }

/// Money is stored in paise.
class Bills extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Format YYYYMMDD-001, counter restarts each day.
  TextColumn get billNumber => text().unique()();
  TextColumn get paymentMethod => textEnum<PaymentMethod>()();
  IntColumn get totalPaise => integer()();

  /// Cash only.
  IntColumn get receivedPaise => integer().nullable()();
  IntColumn get changePaise => integer().nullable()();

  /// Khata only. Plain ints (no foreign key) so bills survive customer deletion.
  IntColumn get customerId => integer().nullable()();
  TextColumn get customerName => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
