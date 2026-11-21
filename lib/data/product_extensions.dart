import 'database.dart';

/// Shows pieces as packs + pieces, e.g. "2 packs + 5 pcs".
String formatStock(int pieces, int packSize) {
  if (packSize <= 1) return '$pieces pcs';
  final packs = pieces ~/ packSize;
  final loose = pieces % packSize;
  if (packs == 0) return '$loose pcs';
  final packText = packs == 1 ? '1 pack' : '$packs packs';
  return loose == 0 ? packText : '$packText + $loose pcs';
}

extension ProductStock on Product {
  String get stockText => formatStock(stock, packSize);
  bool get isOut => stock <= 0;

  /// Limit counts packs for pack products and pieces for single products.
  bool isLow(int limit) => stock <= limit * packSize;
}
