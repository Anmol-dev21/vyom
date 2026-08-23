import 'package:drift/drift.dart';

import 'app_database.dart';

class ProductRepository {
  ProductRepository(this._db);

  final AppDatabase _db;

  Future<List<Product>> getActiveProducts() async {
    return (_db.select(_db.products)
          ..where((tbl) => tbl.isActive.equals(true))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.name)]))
        .get();
  }

  Future<Product?> getProductById(int id) async {
    return (_db.select(
      _db.products,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  Future<Product> createProduct({
    required String name,
    required String unit,
  }) async {
    final normalizedName = name.trim();
    final normalizedUnit = unit.trim();

    if (normalizedName.isEmpty || normalizedUnit.isEmpty) {
      throw StateError('Product name and unit are required.');
    }

    final existing =
        await (_db.select(_db.products)
              ..where(
                (tbl) => tbl.name.lower().equals(normalizedName.toLowerCase()),
              )
              ..where((tbl) => tbl.isActive.equals(true)))
            .getSingleOrNull();

    if (existing != null) {
      throw StateError('An active product with this name already exists.');
    }

    final id = await _db
        .into(_db.products)
        .insert(
          ProductsCompanion(
            name: Value(normalizedName),
            unit: Value(normalizedUnit),
            isActive: const Value(true),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );

    final created = await getProductById(id);
    if (created == null) {
      throw StateError('Unable to create product.');
    }
    return created;
  }

  Future<Product> updateProduct({
    required int id,
    required String name,
    required String unit,
    bool? isActive,
  }) async {
    final normalizedName = name.trim();
    final normalizedUnit = unit.trim();

    if (normalizedName.isEmpty || normalizedUnit.isEmpty) {
      throw StateError('Product name and unit are required.');
    }

    final existing = await getProductById(id);
    if (existing == null) {
      throw StateError('Product not found.');
    }

    final duplicate =
        await (_db.select(_db.products)
              ..where(
                (tbl) => tbl.name.lower().equals(normalizedName.toLowerCase()),
              )
              ..where((tbl) => tbl.id.isNotNull())
              ..where((tbl) => tbl.id.isNotValue(id)))
            .getSingleOrNull();

    if (duplicate != null && duplicate.isActive) {
      throw StateError('Another active product with this name already exists.');
    }

    await (_db.update(_db.products)..where((tbl) => tbl.id.equals(id))).write(
      ProductsCompanion(
        name: Value(normalizedName),
        unit: Value(normalizedUnit),
        isActive: isActive != null ? Value(isActive) : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );

    final updated = await getProductById(id);
    if (updated == null) {
      throw StateError('Unable to update product.');
    }
    return updated;
  }

  Future<void> deactivateProduct(int id) async {
    final existing = await getProductById(id);
    if (existing == null) {
      throw StateError('Product not found.');
    }

    await (_db.update(_db.products)..where((tbl) => tbl.id.equals(id))).write(
      ProductsCompanion(
        isActive: const Value(false),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
