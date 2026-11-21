import 'package:drift/drift.dart';

import 'bills.dart';

enum SaleUnit { piece, pack }

/// A snapshot of what was sold, so old bills stay correct after edits.
class BillItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get billId => integer().references(Bills, #id)();

  /// Plain int: the product may be deleted later.
  IntColumn get productId => integer().nullable()();
  TextColumn get productName => text()();
  TextColumn get unit => textEnum<SaleUnit>()();
  IntColumn get quantity => integer()();
  IntColumn get unitPricePaise => integer()();
  IntColumn get lineTotalPaise => integer()();
}
