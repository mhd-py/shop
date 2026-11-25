import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop/data/backup_service.dart';
import 'package:shop/data/database.dart';
import 'package:shop/data/settings_repository.dart';

Future<String> fake(Directory d, String name, int version) async {
  final b = List<int>.filled(4096, 0);
  final m = 'SQLite format 3'.codeUnits;
  for (var i = 0; i < m.length; i++) {
    b[i] = m[i];
  }
  b[60] = (version >> 24) & 255;
  b[61] = (version >> 16) & 255;
  b[62] = (version >> 8) & 255;
  b[63] = version & 255;
  final f = File('${d.path}/$name');
  await f.writeAsBytes(b);
  return f.path;
}

void main() {
  late Directory tmp;
  late String livePath;
  late AppDatabase live;
  late String backup;

  AppDatabase openLive() => AppDatabase(NativeDatabase(File(livePath)));

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rs');
    livePath = '${tmp.path}/live.db';
    final src = AppDatabase(NativeDatabase(File('${tmp.path}/src.db')));
    await SettingsRepository(src).setShopName('Old Shop');
    backup = await BackupService(src).createBackup(dir: tmp);
    await src.close();
    live = openLive();
    await SettingsRepository(live).setShopName('New Shop');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('restore replaces data and keeps one safety copy', () async {
    final r = await BackupService(live)
        .restore(backup, openDb: openLive, safetyDir: tmp);
    expect(r.restored, isTrue);
    expect(await SettingsRepository(r.db).watchShopName().first, 'Old Shop');
    final safety = tmp
        .listSync()
        .where((e) => e.path.contains('safety-before-restore'))
        .toList();
    expect(safety.length, 1);
    await r.db.close();
  });

  test('bad files are rejected and data is untouched', () async {
    final svc = BackupService(live);
    final notDb = File('${tmp.path}/x.txt')..writeAsStringSync('hello');
    final zero = await fake(tmp, 'zero.db', 0);
    final newer = await fake(tmp, 'newer.db', 99);
    for (final p in [notDb.path, zero, newer]) {
      await expectLater(
          svc.restore(p, openDb: openLive, safetyDir: tmp),
          throwsA(isA<BackupException>()));
    }
    expect(await SettingsRepository(live).watchShopName().first, 'New Shop');
    await live.close();
  });

  test('unreadable file rolls back to the previous data', () async {
    final junk = await fake(tmp, 'junk.db', 7);
    final r = await BackupService(live)
        .restore(junk, openDb: openLive, safetyDir: tmp);
    expect(r.restored, isFalse);
    expect(await SettingsRepository(r.db).watchShopName().first, 'New Shop');
    await r.db.close();
  });
}
