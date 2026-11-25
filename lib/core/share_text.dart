import 'package:share_plus/share_plus.dart';

/// Opens the phone's share sheet with plain text. False if unavailable.
Future<bool> shareText(String text, {String? subject}) async {
  try {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
    return true;
  } catch (_) {
    return false;
  }
}
