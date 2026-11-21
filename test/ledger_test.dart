import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop/data/customer_repository.dart';
import 'package:shop/data/database.dart';
import 'package:shop/data/ledger_repository.dart';
import 'package:shop/data/tables/ledger_entries.dart';

void main() {
  late AppDatabase db;
  late CustomerRepository customers;
  late LedgerRepository ledger;
  late int id;

  Future<int> balance() async =>
      (await ledger.watchCustomer(id).first)!.balancePaise;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    customers = CustomerRepository(db);
    ledger = LedgerRepository(db);
    await customers.add('Ravi', '9876543210');
    id = (await customers.watchAll().first).single.id;
  });
  tearDown(() => db.close());

  test('credit increases the balance', () async {
    await ledger.addCredit(id, 10000);
    await ledger.addCredit(id, 2500);
    expect(await balance(), 12500);
  });

  test('partial payment reduces the balance', () async {
    await ledger.addCredit(id, 10000);
    await ledger.receivePayment(id, 4000);
    expect(await balance(), 6000);
    final last = (await ledger.watchHistory(id).first).first;
    expect(last.type, LedgerType.partialPayment);
    expect(last.balanceAfterPaise, 6000);
  });

  test('payment equal to the balance is recorded as full', () async {
    await ledger.addCredit(id, 10000);
    await ledger.receivePayment(id, 10000);
    expect(await balance(), 0);
    expect((await ledger.watchHistory(id).first).first.type,
        LedgerType.fullPayment);
  });

  test('settleFull clears the balance', () async {
    await ledger.addCredit(id, 7300);
    await ledger.settleFull(id);
    expect(await balance(), 0);
  });

  test('overpayment, zero amounts and settling nothing are rejected',
      () async {
    await ledger.addCredit(id, 5000);
    expect(() => ledger.receivePayment(id, 5001),
        throwsA(isA<CustomerException>()));
    expect(() => ledger.addCredit(id, 0), throwsA(isA<CustomerException>()));
    await ledger.settleFull(id);
    expect(() => ledger.settleFull(id), throwsA(isA<CustomerException>()));
    expect(await balance(), 0);
  });

  test('balance always equals the ledger total', () async {
    await ledger.addCredit(id, 10000);
    await ledger.receivePayment(id, 3000);
    await ledger.addCredit(id, 500);
    final entries = await ledger.watchHistory(id).first;
    final total = entries.fold<int>(
        0,
        (s, e) =>
            e.type == LedgerType.credit ? s + e.amountPaise : s - e.amountPaise);
    expect(total, await balance());
    expect(entries.first.amountPaise, 500); // newest first
  });

  test('deleting a settled customer also removes the history', () async {
    await ledger.addCredit(id, 1000);
    expect(() => customers.delete(id), throwsA(isA<CustomerException>()));
    await ledger.settleFull(id);
    await customers.delete(id);
    expect(await db.select(db.ledgerEntries).get(), isEmpty);
  });
}