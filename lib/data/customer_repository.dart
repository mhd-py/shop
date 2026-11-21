import 'package:drift/drift.dart';

import 'database.dart';

/// A message that is safe to show to the shopkeeper.
class CustomerException implements Exception {
  CustomerException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CustomerRepository {
  CustomerRepository(this._db);
  final AppDatabase _db;

  /// Strips spaces/symbols, a leading +91/91 and a leading 0.
  static String normalizePhone(String raw) {
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length == 12 && d.startsWith('91')) d = d.substring(2);
    if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
    return d;
  }

  /// Returns an error message, or null when the phone is valid.
  static String? validatePhone(String raw) {
    final d = normalizePhone(raw);
    if (d.isEmpty) return 'Phone number is required';
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(d)) {
      return 'Enter a valid 10-digit mobile number';
    }
    return null;
  }

  static String? validateName(String raw) =>
      raw.trim().isEmpty ? 'Name is required' : null;

  Stream<List<Customer>> watchAll() => (_db.select(_db.customers)
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .watch();

  Future<void> _checkInput(String name, String phone, {int? exceptId}) async {
    final error = validateName(name) ?? validatePhone(phone);
    if (error != null) throw CustomerException(error);
    final clash = await (_db.select(_db.customers)
          ..where((t) => t.phone.equals(normalizePhone(phone))))
        .getSingleOrNull();
    if (clash != null && clash.id != exceptId) {
      throw CustomerException(
          'This number already belongs to ${clash.name}');
    }
  }

  Future<void> add(String name, String phone) async {
    await _checkInput(name, phone);
    await _db.into(_db.customers).insert(CustomersCompanion.insert(
          name: name.trim(),
          phone: normalizePhone(phone),
        ));
  }

  Future<void> update(int id, String name, String phone) async {
    await _checkInput(name, phone, exceptId: id);
    await (_db.update(_db.customers)..where((t) => t.id.equals(id))).write(
      CustomersCompanion(
        name: Value(name.trim()),
        phone: Value(normalizePhone(phone)),
      ),
    );
  }

  /// Blocked while the customer still owes money.
  Future<void> delete(int id) => _db.transaction(() async {
        final c = await (_db.select(_db.customers)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        if (c == null) return;
        if (c.balancePaise > 0) {
          throw CustomerException(
              '${c.name} still owes money. Clear the balance first.');
        }
        await (_db.delete(_db.ledgerEntries)
              ..where((t) => t.customerId.equals(id)))
            .go();
        await (_db.delete(_db.customers)..where((t) => t.id.equals(id))).go();
      });
}