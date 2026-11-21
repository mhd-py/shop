import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/app_settings.dart';
import 'tables/bill_items.dart';
import 'tables/bills.dart';
import 'tables/customers.dart';
import 'tables/ledger_entries.dart';
import 'tables/products.dart';

part 'database.g.dart';

@DriftDatabase(
    tables: [Products, AppSettings, Customers, LedgerEntries, Bills, BillItems])
class AppDatabase extends _$AppDatabase {
  /// Pass an in-memory executor in tests; the app uses the default.
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 5;

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
          if (from < 3) {
            await m.createTable(customers);
          }
          if (from < 4) {
            await m.createTable(ledgerEntries);
          }
          if (from < 5) {
            await m.createTable(bills);
            await m.createTable(billItems);
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
