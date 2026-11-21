import 'package:drift/drift.dart';

/// Money is stored in paise. Stock is always stored in pieces.
class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();

  /// Lowercase, trimmed name. Unique, so duplicates are impossible.
  TextColumn get nameKey => text()();

  /// Pieces per pack. 1 means the product is sold only as single items.
  IntColumn get packSize => integer().withDefault(const Constant(1))();

  /// Supplier price per pack (per piece when packSize is 1).
  IntColumn get costPaise => integer()();
  IntColumn get sellPiecePaise => integer()();
  IntColumn get sellPackPaise => integer().nullable()();
  IntColumn get stock => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {nameKey},
      ];
}
