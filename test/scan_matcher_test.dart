import 'package:flutter_test/flutter_test.dart';
import 'package:shop/data/database.dart';
import 'package:shop/data/product_repository.dart';
import 'package:shop/features/scan/product_matcher.dart';

Product p(int id, String name) => Product(
      id: id,
      name: name,
      nameKey: ProductRepository.keyOf(name),
      packSize: 1,
      costPaise: 100,
      sellPiecePaise: 150,
      sellPackPaise: null,
      stock: 3,
      createdAt: DateTime(2026),
    );

void main() {
  final matcher = ProductMatcher([
    p(1, 'Parle-G'),
    p(2, 'Marie Gold 250gm'),
    p(3, 'Parle G 100g'),
  ]);

  test('same name in any case or punctuation is exact', () {
    expect(matcher.match('PARLE-G').kind, MatchKind.exact);
    expect(matcher.match('parle g').product!.id, 1);
  });

  test('close name is only suggested', () {
    final r = matcher.match('PARLE G 56G');
    expect(r.kind, MatchKind.similar);
    expect(r.product!.id, 1);
    expect(matcher.match('Marie Gold 250GM 36PK').kind, MatchKind.similar);
  });

  test('different size is never matched', () {
    expect(matcher.match('Parle G 56g').product?.id, isNot(3));
    expect(matcher.match('Marie Gold 500gm').kind, MatchKind.none);
  });

  test('unknown product has no match', () {
    expect(matcher.match('Dabur Paste 50G').kind, MatchKind.none);
  });
}
