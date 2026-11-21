String formatRupees(int paise) => '₹${(paise / 100).toStringAsFixed(2)}';

/// Returns paise, or null if the text is not a valid amount.
int? parseRupees(String text) {
  final v = double.tryParse(text.trim());
  if (v == null || v < 0) return null;
  return (v * 100).round();
}
