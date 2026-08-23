import 'package:drift/drift.dart';

import 'app_database.dart';

class CustomerRepository {
  CustomerRepository(this._db);

  final AppDatabase _db;

  Future<List<Customer>> getActiveCustomers() async {
    return (_db.select(_db.customers)
          ..where((tbl) => tbl.isActive.equals(true))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.name)]))
        .get();
  }

  Future<Customer?> getCustomerById(int id) async {
    return (_db.select(
      _db.customers,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  Future<Customer> createCustomer({
    required String name,
    required String address,
    required String mobile,
  }) async {
    final normalizedName = name.trim();
    final normalizedAddress = address.trim();
    final normalizedMobile = mobile.replaceAll(RegExp(r'\D'), '');

    if (normalizedName.isEmpty || normalizedAddress.isEmpty) {
      throw StateError('Customer name and address are required.');
    }

    if (!RegExp(r'^\d{10}$').hasMatch(normalizedMobile)) {
      throw StateError('A valid Indian 10-digit mobile number is required.');
    }

    final id = await _db
        .into(_db.customers)
        .insert(
          CustomersCompanion(
            name: Value(normalizedName),
            address: Value(normalizedAddress),
            mobile: Value(normalizedMobile),
            isActive: const Value(true),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );

    final created = await getCustomerById(id);
    if (created == null) {
      throw StateError('Unable to create customer.');
    }
    return created;
  }

  Future<Customer> updateCustomer({
    required int id,
    required String name,
    required String address,
    required String mobile,
    bool? isActive,
  }) async {
    final normalizedName = name.trim();
    final normalizedAddress = address.trim();
    final normalizedMobile = mobile.replaceAll(RegExp(r'\D'), '');

    if (normalizedName.isEmpty || normalizedAddress.isEmpty) {
      throw StateError('Customer name and address are required.');
    }

    if (!RegExp(r'^\d{10}$').hasMatch(normalizedMobile)) {
      throw StateError('A valid Indian 10-digit mobile number is required.');
    }

    final existing = await getCustomerById(id);
    if (existing == null) {
      throw StateError('Customer not found.');
    }

    await (_db.update(_db.customers)..where((tbl) => tbl.id.equals(id))).write(
      CustomersCompanion(
        name: Value(normalizedName),
        address: Value(normalizedAddress),
        mobile: Value(normalizedMobile),
        isActive: isActive != null ? Value(isActive) : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );

    final updated = await getCustomerById(id);
    if (updated == null) {
      throw StateError('Unable to update customer.');
    }
    return updated;
  }

  Future<void> deactivateCustomer(int id) async {
    final existing = await getCustomerById(id);
    if (existing == null) {
      throw StateError('Customer not found.');
    }

    await (_db.update(_db.customers)..where((tbl) => tbl.id.equals(id))).write(
      CustomersCompanion(
        isActive: const Value(false),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
