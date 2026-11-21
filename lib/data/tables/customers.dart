import 'package:drift/drift.dart';

/// Money is stored in paise. Phone is stored as 10 digits.
class Customers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get phone => text().withLength(min: 10, max: 10)();

  /// Amount the customer owes. Kept in sync by the ledger (part 2).
  IntColumn get balancePaise => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {phone},
      ];
}