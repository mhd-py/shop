import 'package:drift/drift.dart';

/// Prices are stored in paise (integer) to avoid rounding errors.
class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();

  /// Lowercase, trimmed name. Used for duplicate detection.
  TextColumn get nameKey => text()();
  IntColumn get pricePaise => integer()();
  IntColumn get stock => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
