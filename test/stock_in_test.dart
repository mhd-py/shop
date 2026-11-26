import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop/data/database.dart';
import 'package:shop/data/stock_in_repository.dart';

void main() {
  late AppDatabase db;
  late StockInRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = StockInRepository(db);
    await db.into(db.products).insert(ProductsCompanion.insert(
          name: 'Parle-G',
          nameKey: 'parle-g',
          costPaise: 500,
          sellPiecePaise: 600,
          stock: const Value(3),
        ));
  });
  tearDown(() => db.close());

  Future<Product> parle() => (db.select(db.products)
        ..where((t) => t.nameKey.equals('parle-g')))
      .getSingle();

  test('old stock plus bill quantity, with the new cost', () async {
    final id = (await parle()).id;
    final r = await repo.apply([
      StockInLine(productId: id, name: 'Parle-G', pieces: 12, costPaise: 550),
    ]);
    final p = await parle();
    expect(p.stock, 15);
    expect(p.costPaise, 550);
    expect(p.sellPiecePaise, 600);
    expect(r.updated, 1);
    expect(r.added, 0);
  });

  test('keeping the old cost leaves it unchanged', () async {
    final id = (await parle()).id;
    await repo.apply([
      StockInLine(
          productId: id,
          name: 'Parle-G',
          pieces: 2,
          costPaise: 999,
          updateCost: false),
    ]);
    final p = await parle();
    expect(p.stock, 5);
    expect(p.costPaise, 500);
  });

  test('new product is created; same name twice makes no duplicate', () async {
    final r = await repo.apply([
      const StockInLine(
          name: 'FC Scale', pieces: 10, costPaise: 375, sellPiecePaise: 500),
      const StockInLine(name: 'fc scale', pieces: 5, costPaise: 380),
    ]);
    final rows = await (db.select(db.products)
          ..where((t) => t.nameKey.equals('fc scale')))
        .get();
    expect(rows.length, 1);
    expect(rows.single.stock, 15);
    expect(rows.single.sellPiecePaise, 500);
    expect(r.added, 1);
    expect(r.updated, 1);
  });

  test('a new line named like an existing product merges, not duplicates',
      () async {
    await repo.apply([
      const StockInLine(name: 'PARLE-G', pieces: 7, costPaise: 520),
    ]);
    expect((await db.select(db.products).get()).length, 1);
    expect((await parle()).stock, 10);
  });

  test('one bad line cancels the whole bill', () async {
    final id = (await parle()).id;
    await expectLater(
      repo.apply([
        StockInLine(productId: id, name: 'Parle-G', pieces: 5, costPaise: 500),
        const StockInLine(name: 'Bad', pieces: 0, costPaise: 100),
      ]),
      throwsA(isA<StockInException>()),
    );
    expect((await parle()).stock, 3);
  });
}
