import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop/data/database.dart';
import 'package:shop/data/pin_repository.dart';

void main() {
  late AppDatabase db;
  late PinRepository pin;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    pin = PinRepository(db);
  });
  tearDown(() => db.close());

  Matcher fails() => throwsA(isA<PinException>());

  test('no PIN at first', () async {
    expect(await pin.hasPin(), isFalse);
  });

  test('set, verify and wrong PIN', () async {
    final code = await pin.setPin('1234');
    expect(code.length, 11);
    expect(await pin.hasPin(), isTrue);
    await pin.verifyPin('1234');
    await expectLater(pin.verifyPin('0000'), fails());
  });

  test('rejects a badly formed PIN', () async {
    await expectLater(pin.setPin('12a4'), fails());
    await expectLater(pin.setPin('123'), fails());
    expect(await pin.hasPin(), isFalse);
  });

  test('waits after 5 wrong tries, even for the right PIN', () async {
    await pin.setPin('1234');
    for (var i = 0; i < 5; i++) {
      await expectLater(pin.verifyPin('0000'), fails());
    }
    await expectLater(pin.verifyPin('1234'), fails());
  });

  test('change and remove need the current PIN', () async {
    await pin.setPin('1234');
    await expectLater(pin.changePin('9999', '5678'), fails());
    await pin.changePin('1234', '5678');
    await pin.verifyPin('5678');
    await expectLater(pin.removePin('0000'), fails());
    await pin.removePin('5678');
    expect(await pin.hasPin(), isFalse);
  });

  test('recovery code resets the PIN and gives a new code', () async {
    final code = await pin.setPin('1234');
    await expectLater(pin.resetWithRecovery('AAAAA-AAAAA', '1111'), fails());
    final fresh =
        await pin.resetWithRecovery(code.toLowerCase().replaceAll('-', ' '), '4321');
    await pin.verifyPin('4321');
    expect(fresh, isNot(code));
    await pin.resetWithRecovery(fresh, '2468');
    await pin.verifyPin('2468');
  });

  test('erase all data clears everything including the PIN', () async {
    await pin.setPin('1234');
    await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'A', nameKey: 'a', costPaise: 100, sellPiecePaise: 150));
    await db.into(db.customers).insert(
        CustomersCompanion.insert(name: 'Ravi', phone: '9876543210'));
    await pin.eraseAllData();
    expect(await db.select(db.products).get(), isEmpty);
    expect(await db.select(db.customers).get(), isEmpty);
    expect(await pin.hasPin(), isFalse);
  });
}
