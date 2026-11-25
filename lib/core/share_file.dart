import 'package:share_plus/share_plus.dart';

/// Opens the share sheet with a file from disk.
Future<ShareResultStatus> shareBackupFile(String path) async {
  final name = path.split('/').last;
  final result = await SharePlus.instance.share(ShareParams(
    files: [XFile(path, mimeType: 'application/octet-stream', name: name)],
    fileNameOverrides: [name],
    subject: name,
  ));
  return result.status;
}
