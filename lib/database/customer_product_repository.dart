import 'package:drift/drift.dart';

import 'app_database.dart';

class CustomerProductRepository {
  CustomerProductRepository(this._db);

  final AppDatabase _db;

  Future<List<CustomerProduct>> getProductsForCustomer(int customerId) async {
    return (_db.select(_db.customerProducts)
          ..where((tbl) => tbl.customerId.equals(customerId))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.productId)]))
        .get();
  }

  Future<CustomerProduct> addProductToCustomer({
    required int customerId,
    required int productId,
    required int defaultQuantity,
  }) async {
    final existing =
        await (_db.select(_db.customerProducts)
              ..where((tbl) => tbl.customerId.equals(customerId))
              ..where((tbl) => tbl.productId.equals(productId)))
            .getSingleOrNull();

    if (existing != null) {
      throw StateError('This customer already has this product assigned.');
    }

    final id = await _db
        .into(_db.customerProducts)
        .insert(
          CustomerProductsCompanion(
            customerId: Value(customerId),
            productId: Value(productId),
            defaultQuantity: Value(defaultQuantity),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );

    final created = await (_db.select(
      _db.customerProducts,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

    if (created == null) {
      throw StateError('Unable to add product to customer.');
    }
    return created;
  }

  Future<CustomerProduct> updateCustomerProduct({
    required int id,
    required int defaultQuantity,
  }) async {
    final existing = await (_db.select(
      _db.customerProducts,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

    if (existing == null) {
      throw StateError('Customer product assignment not found.');
    }

    await (_db.update(
      _db.customerProducts,
    )..where((tbl) => tbl.id.equals(id))).write(
      CustomerProductsCompanion(
        defaultQuantity: Value(defaultQuantity),
        updatedAt: Value(DateTime.now()),
      ),
    );

    final updated = await (_db.select(
      _db.customerProducts,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

    if (updated == null) {
      throw StateError('Unable to update customer product assignment.');
    }
    return updated;
  }

  Future<void> removeProductFromCustomer(int id) async {
    final existing = await (_db.select(
      _db.customerProducts,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

    if (existing == null) {
      throw StateError('Customer product assignment not found.');
    }

    await (_db.delete(
      _db.customerProducts,
    )..where((tbl) => tbl.id.equals(id))).go();
  }
}
