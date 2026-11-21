import 'database.dart';

class SettingsRepository {
  SettingsRepository(this._db);
  final AppDatabase _db;

  static const defaultLowStock = 5;
  static const _lowStockKey = 'low_stock_threshold';

  Stream<int> watchLowStockThreshold() => (_db.select(_db.appSettings)
        ..where((t) => t.settingKey.equals(_lowStockKey)))
      .watchSingleOrNull()
      .map((row) => int.tryParse(row?.settingValue ?? '') ?? defaultLowStock);

  Future<void> setLowStockThreshold(int value) =>
      _db.into(_db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              settingKey: _lowStockKey,
              settingValue: value.toString(),
            ),
          );
}
