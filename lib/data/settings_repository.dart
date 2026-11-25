import 'database.dart';

class SettingsRepository {
  SettingsRepository(this._db);
  final AppDatabase _db;

  static const defaultLowStock = 5;
  static const _lowStockKey = 'low_stock_threshold';
  static const _shopNameKey = 'shop_name';
  static const _upiIdKey = 'upi_id';
  static const _lastBackupKey = 'last_backup_ms';

  Stream<String?> _watchText(String key) => (_db.select(_db.appSettings)
        ..where((t) => t.settingKey.equals(key)))
      .watchSingleOrNull()
      .map((row) => row?.settingValue);

  Future<void> _setText(String key, String value) =>
      _db.into(_db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(settingKey: key, settingValue: value),
          );

  Stream<int> watchLowStockThreshold() => _watchText(_lowStockKey)
      .map((v) => int.tryParse(v ?? '') ?? defaultLowStock);

  Future<void> setLowStockThreshold(int value) =>
      _setText(_lowStockKey, value.toString());

  /// Empty text when not set.
  Stream<String> watchShopName() =>
      _watchText(_shopNameKey).map((v) => v ?? '');
  Future<void> setShopName(String v) => _setText(_shopNameKey, v.trim());

  Stream<String> watchUpiId() => _watchText(_upiIdKey).map((v) => v ?? '');
  Future<void> setUpiId(String v) => _setText(_upiIdKey, v.trim());

  AppDatabase get database => _db;

  Stream<DateTime?> watchLastBackup() => _watchText(_lastBackupKey).map((v) {
        final ms = int.tryParse(v ?? '');
        return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
      });

  Future<void> markBackupNow() => _setText(
      _lastBackupKey, DateTime.now().millisecondsSinceEpoch.toString());
}
