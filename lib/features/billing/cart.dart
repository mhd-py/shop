import 'package:flutter/foundation.dart';

import '../../data/bill_repository.dart';
import '../../data/database.dart';
import '../../data/product_extensions.dart';
import '../../data/tables/bill_items.dart';

class CartItem {
  CartItem(this.product, this.unit, this.quantity);
  Product product;
  final SaleUnit unit;
  int quantity;

  int get unitPrice => unit == SaleUnit.pack
      ? (product.sellPackPaise ?? 0)
      : product.sellPiecePaise;
  int get pieces => unit == SaleUnit.pack ? quantity * product.packSize : quantity;
  int get lineTotal => unitPrice * quantity;
}

class CartController extends ChangeNotifier {
  final List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;
  int get total => _items.fold(0, (s, i) => s + i.lineTotal);

  static bool canSellPack(Product p) => p.packSize > 1 && p.sellPackPaise != null;

  /// Pieces of this product already in the cart (piece and pack lines).
  int piecesInCart(int productId) => _items
      .where((i) => i.product.id == productId)
      .fold(0, (s, i) => s + i.pieces);

  /// Returns an error message, or null when added.
  String? add(Product p, SaleUnit unit) {
    if (unit == SaleUnit.pack && !canSellPack(p)) {
      return '${p.name} is not sold in packs';
    }
    final step = unit == SaleUnit.pack ? p.packSize : 1;
    if (piecesInCart(p.id) + step > p.stock) {
      return 'Only ${p.stockText} of ${p.name} in stock';
    }
    for (final i in _items.where((i) => i.product.id == p.id)) {
      i.product = p; // keep stock/prices fresh
    }
    final existing = _items
        .where((i) => i.product.id == p.id && i.unit == unit)
        .firstOrNull;
    if (existing != null) {
      existing.quantity++;
    } else {
      _items.add(CartItem(p, unit, 1));
    }
    notifyListeners();
    return null;
  }

  String? increase(CartItem item) => add(item.product, item.unit);

  void decrease(CartItem item) {
    if (item.quantity > 1) {
      item.quantity--;
      notifyListeners();
    }
  }

  void remove(CartItem item) {
    _items.remove(item);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }

  List<CartLine> toLines() =>
      _items.map((i) => CartLine(i.product.id, i.unit, i.quantity)).toList();
}
