import 'dart:convert';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// Opens the system share sheet with the CSV file.
/// Returns false when sharing is not available on this device/browser.
Future<bool> shareCsv(String fileName, String csv) async {
  final bytes = Uint8List.fromList(utf8.encode(csv));
  final result = await SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(bytes, mimeType: 'text/csv', name: fileName)],
    fileNameOverrides: [fileName],
    subject: fileName,
  ));
  return result.status != ShareResultStatus.unavailable;
}
