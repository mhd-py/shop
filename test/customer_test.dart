import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop/data/customer_repository.dart';
import 'package:shop/data/database.dart';

void main() {
  late AppDatabase db;
  late CustomerRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = CustomerRepository(db);
  });
  tearDown(() => db.close());

  test('phone is cleaned: +91, 0 and spaces removed', () {
    expect(CustomerRepository.normalizePhone('+91 98765 43210'), '9876543210');
    expect(CustomerRepository.normalizePhone('09876543210'), '9876543210');
    expect(CustomerRepository.normalizePhone('98765-43210'), '9876543210');
  });

  test('phone validation', () {
    expect(CustomerRepository.validatePhone('9876543210'), isNull);
    expect(CustomerRepository.validatePhone(''), isNotNull);
    expect(CustomerRepository.validatePhone('12345'), isNotNull);
    expect(CustomerRepository.validatePhone('5876543210'), isNotNull);
  });

  test('add stores cleaned phone and zero balance', () async {
    await repo.add('  Ravi ', '+91 98765 43210');
    final c = (await repo.watchAll().first).single;
    expect(c.name, 'Ravi');
    expect(c.phone, '9876543210');
    expect(c.balancePaise, 0);
  });

  test('duplicate phone is rejected', () async {
    await repo.add('Ravi', '9876543210');
    expect(() => repo.add('Sita', '09876543210'),
        throwsA(isA<CustomerException>()));
  });

  test('editing keeps own phone but cannot take another customer\'s',
      () async {
    await repo.add('Ravi', '9876543210');
    await repo.add('Sita', '9123456780');
    final ravi = (await repo.watchAll().first).firstWhere((c) => c.name == 'Ravi');
    await repo.update(ravi.id, 'Ravi K', '9876543210');
    expect(() => repo.update(ravi.id, 'Ravi K', '9123456780'),
        throwsA(isA<CustomerException>()));
  });

  test('delete works when settled, blocked when money is owed', () async {
    await repo.add('Ravi', '9876543210');
    final c = (await repo.watchAll().first).single;
    await (db.update(db.customers)..where((t) => t.id.equals(c.id)))
        .write(const CustomersCompanion(balancePaise: Value(5000)));
    expect(() => repo.delete(c.id), throwsA(isA<CustomerException>()));
    expect((await repo.watchAll().first).length, 1);

    await (db.update(db.customers)..where((t) => t.id.equals(c.id)))
        .write(const CustomersCompanion(balancePaise: Value(0)));
    await repo.delete(c.id);
    expect(await repo.watchAll().first, isEmpty);
  });
}