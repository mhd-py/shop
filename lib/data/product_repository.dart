import 'package:drift/drift.dart';

import 'database.dart';

/// What the product form collects. Stock is in pieces.
class ProductInput {
  const ProductInput({
    required this.name,
    required this.packSize,
    required this.costPaise,
    required this.sellPiecePaise,
    this.sellPackPaise,
    required this.stockPieces,
  });

  final String name;
  final int packSize;
  final int costPaise;
  final int sellPiecePaise;
  final int? sellPackPaise;
  final int stockPieces;
}

class ProductRepository {
  ProductRepository(this._db);
  final AppDatabase _db;

  static String keyOf(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Stream<List<Product>> watchAll() => (_db.select(_db.products)
        ..orderBy([(t) => OrderingTerm.asc(t.nameKey)]))
      .watch();

  Future<Product?> findByName(String name) => (_db.select(_db.products)
        ..where((t) => t.nameKey.equals(keyOf(name))))
      .getSingleOrNull();

  Future<void> add(ProductInput i) =>
      _db.into(_db.products).insert(ProductsCompanion.insert(
            name: i.name.trim(),
            nameKey: keyOf(i.name),
            costPaise: i.costPaise,
            sellPiecePaise: i.sellPiecePaise,
            packSize: Value(i.packSize),
            sellPackPaise: Value(i.sellPackPaise),
            stock: Value(i.stockPieces),
          ));

  Future<void> update(int id, ProductInput i) =>
      (_db.update(_db.products)..where((t) => t.id.equals(id))).write(
        ProductsCompanion(
          name: Value(i.name.trim()),
          nameKey: Value(keyOf(i.name)),
          packSize: Value(i.packSize),
          costPaise: Value(i.costPaise),
          sellPiecePaise: Value(i.sellPiecePaise),
          sellPackPaise: Value(i.sellPackPaise),
          stock: Value(i.stockPieces),
        ),
      );

  /// Adds the new stock to an existing product. Prices change only when
  /// [useNewPrices] is true.
  Future<void> merge(
    Product existing,
    ProductInput i, {
    required bool useNewPrices,
  }) =>
      _db.transaction(() async {
        final current = await (_db.select(_db.products)
              ..where((t) => t.id.equals(existing.id)))
            .getSingle();
        await (_db.update(_db.products)
              ..where((t) => t.id.equals(existing.id)))
            .write(
          ProductsCompanion(
            stock: Value(current.stock + i.stockPieces),
            costPaise: useNewPrices ? Value(i.costPaise) : const Value.absent(),
            sellPiecePaise:
                useNewPrices ? Value(i.sellPiecePaise) : const Value.absent(),
            sellPackPaise:
                useNewPrices ? Value(i.sellPackPaise) : const Value.absent(),
          ),
        );
      });

  Future<void> delete(int id) =>
      (_db.delete(_db.products)..where((t) => t.id.equals(id))).go();
}
