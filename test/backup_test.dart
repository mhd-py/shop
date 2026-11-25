import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop/data/backup_service.dart';
import 'package:shop/data/database.dart';
import 'package:shop/data/settings_repository.dart';

void main() {
  test('backup file opens with the same data', () async {
    final tmp = await Directory.systemTemp.createTemp('bk');
    final db = AppDatabase(NativeDatabase(File('${tmp.path}/a.db')));
    final s = SettingsRepository(db);
    await s.setShopName('Test Shop');
    expect(await s.watchLastBackup().first, isNull);
    await s.markBackupNow();
    expect(await s.watchLastBackup().first, isNotNull);
    final path = await BackupService(db).createBackup(dir: tmp);
    await db.close();

    final copy = AppDatabase(NativeDatabase(File(path)));
    expect(await SettingsRepository(copy).watchShopName().first, 'Test Shop');
    await copy.close();
    await tmp.delete(recursive: true);
  });
}
