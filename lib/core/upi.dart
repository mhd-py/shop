/// Returns an error message, or null when the UPI ID looks valid.
String? validateUpiId(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return 'UPI ID is required';
  if (!RegExp(r'^[\w.\-]{2,}@[a-zA-Z]{2,}$').hasMatch(v)) {
    return 'Enter a valid UPI ID, like shop@upi';
  }
  return null;
}

/// The text inside the QR code. Any UPI app can scan it.
String buildUpiUri({
  required String upiId,
  required String name,
  required int amountPaise,
  String? note,
}) {
  final params = <String, String>{
    'pn': name.trim().isEmpty ? 'Shop' : name.trim(),
    'am': (amountPaise / 100).toStringAsFixed(2),
    'cu': 'INR',
    if (note != null && note.isNotEmpty) 'tn': note,
  };
  final rest = params.entries
      .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
      .join('&');
  return 'upi://pay?pa=${upiId.trim()}&$rest';
}
