import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/products.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Products])
class AppDatabase extends _$AppDatabase {
  /// Pass an in-memory executor in tests; the app uses the default.
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _open() {
    return driftDatabase(
      name: 'shop_db',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    );
  }
}
