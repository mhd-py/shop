import 'package:flutter_test/flutter_test.dart';
import 'package:shop/data/database.dart';
import 'package:shop/data/tables/bill_items.dart';
import 'package:shop/features/billing/cart.dart';

Product product({int id = 1, int packSize = 10, int stock = 25}) => Product(
      id: id,
      name: 'Biscuit',
      nameKey: 'biscuit',
      packSize: packSize,
      costPaise: 8000,
      sellPiecePaise: 1000,
      sellPackPaise: packSize > 1 ? 9500 : null,
      stock: stock,
      createdAt: DateTime(2026, 11, 21),
    );

void main() {
  test('same product and unit merge into one line', () {
    final cart = CartController();
    final p = product();
    expect(cart.add(p, SaleUnit.piece), isNull);
    expect(cart.add(p, SaleUnit.piece), isNull);
    expect(cart.add(p, SaleUnit.pack), isNull);
    expect(cart.items.length, 2);
    expect(cart.items.first.quantity, 2);
    expect(cart.total, 2000 + 9500);
  });

  test('piece and pack lines share one stock limit', () {
    final cart = CartController();
    final p = product(stock: 25);
    expect(cart.add(p, SaleUnit.pack), isNull); // 10
    expect(cart.add(p, SaleUnit.pack), isNull); // 20
    expect(cart.add(p, SaleUnit.pack), isNotNull); // 30 > 25
    for (var i = 0; i < 5; i++) {
      expect(cart.add(p, SaleUnit.piece), isNull); // up to 25
    }
    expect(cart.add(p, SaleUnit.piece), isNotNull);
    expect(cart.piecesInCart(1), 25);
  });

  test('pack is refused for single-item products', () {
    final cart = CartController();
    expect(cart.add(product(packSize: 1), SaleUnit.pack), isNotNull);
    expect(cart.isEmpty, isTrue);
  });

  test('decrease stops at 1, remove and clear work', () {
    final cart = CartController();
    final p = product();
    cart.add(p, SaleUnit.piece);
    cart.add(p, SaleUnit.piece);
    cart.decrease(cart.items.first);
    cart.decrease(cart.items.first);
    expect(cart.items.first.quantity, 1);
    cart.remove(cart.items.first);
    expect(cart.isEmpty, isTrue);
    cart.add(p, SaleUnit.piece);
    cart.clear();
    expect(cart.total, 0);
  });
}
