import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import 'database.dart';

/// A message that is safe to show to the shopkeeper.
class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

class RestoreResult {
  RestoreResult(this.db, {this.error});

  /// The database to use from now on (restored, or the old one put back).
  final AppDatabase db;
  final String? error;
  bool get restored => error == null;
}

class BackupService {
  BackupService(this._db);
  final AppDatabase _db;

  /// Backup and restore need real files, so they work on the phone only.
  static bool get supported => !kIsWeb;
  static const _safetyPrefix = 'safety-before-restore-';

  /// Writes a consistent copy of the database and returns its path.
  Future<String> createBackup({Directory? dir}) async {
    final folder = dir ?? await getTemporaryDirectory();
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name = 'shop-backup-${d.year}${two(d.month)}${two(d.day)}'
        '-${two(d.hour)}${two(d.minute)}.db';
    final file = File('${folder.path}/$name');
    if (await file.exists()) await file.delete();
    final escaped = file.path.replaceAll("'", "''");
    await _db.customStatement("VACUUM INTO '$escaped'");
    return file.path;
  }

  /// Checks the SQLite header and schema version of a chosen file.
  Future<void> validate(String path) async {
    final file = File(path);
    if (!await file.exists()) throw BackupException('File not found');
    final raf = await file.open();
    try {
      final head = await raf.read(100);
      final magic = String.fromCharCodes(head.take(15));
      if (head.length < 100 || magic != 'SQLite format 3') {
        throw BackupException('This is not a Shop backup file');
      }
      final version =
          (head[60] << 24) | (head[61] << 16) | (head[62] << 8) | head[63];
      if (version < 2) throw BackupException('This is not a Shop backup file');
      if (version > _db.schemaVersion) {
        throw BackupException('This backup was made by a newer version of '
            'the app. Update the app first.');
      }
    } finally {
      await raf.close();
    }
  }

  Future<String> _livePath() async {
    final rows = await _db.customSelect('PRAGMA database_list').get();
    for (final r in rows) {
      if (r.read<String>('name') == 'main') {
        final f = r.read<String>('file');
        if (f.isNotEmpty) return f;
      }
    }
    throw BackupException('Could not find the database file');
  }

  Future<void> _replaceFile(String from, String to) async {
    for (final s in ['-wal', '-shm', '-journal']) {
      final f = File('$to$s');
      if (await f.exists()) await f.delete();
    }
    final tmp = '$to.restoring';
    await File(from).copy(tmp);
    await File(tmp).rename(to);
  }

  /// Keeps only the newest safety copy.
  Future<String> _safetyCopy(Directory folder) async {
    for (final e in folder.listSync()) {
      if (e is File && e.path.split('/').last.startsWith(_safetyPrefix)) {
        await e.delete();
      }
    }
    final path = '${folder.path}/$_safetyPrefix'
        '${DateTime.now().millisecondsSinceEpoch}.db';
    await _db.customStatement("VACUUM INTO '${path.replaceAll("'", "''")}'");
    return path;
  }

  /// Replaces the current data with the chosen backup.
  /// Throws [BackupException] before touching anything if the file is bad.
  /// If the restored file fails to open, the previous data is put back.
  Future<RestoreResult> restore(
    String pickedPath, {
    AppDatabase Function()? openDb,
    Directory? safetyDir,
  }) async {
    await validate(pickedPath);
    final live = await _livePath();
    final folder = safetyDir ?? await getApplicationDocumentsDirectory();
    final safety = await _safetyCopy(folder);
    final open = openDb ?? () => AppDatabase();
    await _db.close();
    AppDatabase? fresh;
    try {
      await _replaceFile(pickedPath, live);
      fresh = open();
      // Opens the file, runs any needed upgrade, and proves it is readable.
      await fresh.customSelect('SELECT count(*) AS c FROM bills').get();
      return RestoreResult(fresh);
    } catch (_) {
      try {
        await fresh?.close();
      } catch (_) {}
      await _replaceFile(safety, live);
      return RestoreResult(open(),
          error: 'The file could not be restored. '
              'Your previous data was put back.');
    }
  }
}
