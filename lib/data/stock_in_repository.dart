import 'package:drift/drift.dart';

import 'database.dart';
import 'product_repository.dart';

/// A message that is safe to show to the shopkeeper.
class StockInException implements Exception {
  StockInException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One bill line, ready to save. [pieces] is already converted to pieces and
/// [costPaise] is per stock unit of the product (per pack for pack products).
class StockInLine {
  const StockInLine({
    this.productId,
    required this.name,
    required this.pieces,
    required this.costPaise,
    this.sellPiecePaise,
    this.updateCost = true,
  });

  /// Null means "create a new product named [name]".
  final int? productId;
  final String name;
  final int pieces;
  final int costPaise;
  final int? sellPiecePaise;
  final bool updateCost;
}

class StockInResult {
  const StockInResult({required this.added, required this.updated});
  final int added;
  final int updated;
}

class StockInRepository {
  StockInRepository(this._db);
  final AppDatabase _db;

  /// Saves every line in one transaction: all or nothing. Current stock is
  /// read inside the transaction, so old stock + bill quantity is exact.
  Future<StockInResult> apply(List<StockInLine> lines) =>
      _db.transaction(() async {
        var added = 0;
        var updated = 0;
        for (final l in lines) {
          if (l.pieces <= 0) {
            throw StockInException('"${l.name}": quantity must be above zero');
          }
          if (l.costPaise < 0) {
            throw StockInException('"${l.name}": cost cannot be negative');
          }
          Product? p;
          if (l.productId != null) {
            p = await (_db.select(_db.products)
                  ..where((t) => t.id.equals(l.productId!)))
                .getSingleOrNull();
            if (p == null) {
              throw StockInException(
                  '"${l.name}" was deleted. Please review the bill again.');
            }
          } else {
            final name = l.name.trim();
            if (name.isEmpty || name.length > 100) {
              throw StockInException('Product name must be 1 to 100 letters');
            }
            // Same name twice on one bill adds to the first, no duplicate.
            p = await (_db.select(_db.products)
                  ..where((t) => t.nameKey.equals(ProductRepository.keyOf(name))))
                .getSingleOrNull();
          }

          if (p != null) {
            await (_db.update(_db.products)..where((t) => t.id.equals(p!.id)))
                .write(ProductsCompanion(
              stock: Value(p.stock + l.pieces),
              costPaise:
                  l.updateCost ? Value(l.costPaise) : const Value.absent(),
            ));
            updated++;
          } else {
            await _db.into(_db.products).insert(ProductsCompanion.insert(
                  name: l.name.trim(),
                  nameKey: ProductRepository.keyOf(l.name),
                  costPaise: l.costPaise,
                  sellPiecePaise: l.sellPiecePaise ?? l.costPaise,
                  stock: Value(l.pieces),
                ));
            added++;
          }
        }
        return StockInResult(added: added, updated: updated);
      });
}
