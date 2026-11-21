import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/app_settings.dart';
import 'tables/products.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Products, AppSettings])
class AppDatabase extends _$AppDatabase {
  /// Pass an in-memory executor in tests; the app uses the default.
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // Version 1 only held test products: rebuild with the new layout.
            await m.drop(products);
            await m.createTable(products);
            await m.createTable(appSettings);
          }
        },
      );

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
