import 'package:drift/drift.dart';

import 'app_database.dart';
import 'product_pricing_repository.dart';

class DailyDistributionRepository {
  DailyDistributionRepository(
    this._db, [
    ProductPricingRepository? pricingRepository,
  ]) : _pricingRepository = pricingRepository ?? ProductPricingRepository(_db);

  final AppDatabase _db;
  final ProductPricingRepository _pricingRepository;

  Future<void> saveDailyDistributionBatch({
    required DateTime distributionDate,
    required List<
      ({int customerId, List<({int productId, int quantity})> items})
    >
    entries,
  }) async {
    await _db.transaction(
      () => _saveDailyDistributionBatch(
        distributionDate: distributionDate,
        entries: entries,
      ),
    );
  }

  Future<void> _saveDailyDistributionBatch({
    required DateTime distributionDate,
    required List<
      ({int customerId, List<({int productId, int quantity})> items})
    >
    entries,
  }) async {
    final normalized = _normalizeBusinessDate(distributionDate);
    final customerIds = <int>{};

    for (final entry in entries) {
      if (!customerIds.add(entry.customerId)) {
        throw StateError(
          'Duplicate customer entries are not allowed in a batch.',
        );
      }
      final productIds = <int>{};
      for (final item in entry.items) {
        if (item.quantity < 0) {
          throw StateError('Quantity cannot be negative.');
        }
        if (!productIds.add(item.productId)) {
          throw StateError(
            'Duplicate product entries are not allowed within a distribution.',
          );
        }
      }

      var distribution =
          await (_db.select(_db.dailyDistributions)
                ..where((tbl) => tbl.customerId.equals(entry.customerId))
                ..where((tbl) => tbl.distributionDate.equals(normalized)))
              .getSingleOrNull();

      if (distribution == null) {
        final id = await _db
            .into(_db.dailyDistributions)
            .insert(
              DailyDistributionsCompanion(
                customerId: Value(entry.customerId),
                distributionDate: Value(normalized),
                status: const Value('draft'),
                createdAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.now()),
              ),
            );
        distribution = await _getDistributionById(id);
      }

      if (distribution == null) {
        throw StateError('Unable to create distribution.');
      }
      final distributionId = distribution.id;
      if (distribution.status != 'draft') {
        final currentItems = await getDistributionItems(distributionId);
        final matches =
            currentItems.length == entry.items.length &&
            currentItems.every(
              (current) => entry.items.any(
                (item) =>
                    item.productId == current.productId &&
                    item.quantity == current.quantity,
              ),
            );
        if (!matches || distribution.status != 'confirmed') {
          throw StateError('Cannot modify a confirmed distribution.');
        }
        continue;
      }

      await (_db.delete(
        _db.dailyDistributionItems,
      )..where((tbl) => tbl.distributionId.equals(distributionId))).go();

      for (final item in entry.items) {
        await _db
            .into(_db.dailyDistributionItems)
            .insert(
              DailyDistributionItemsCompanion(
                distributionId: Value(distributionId),
                productId: Value(item.productId),
                quantity: Value(item.quantity),
                createdAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.now()),
              ),
            );
      }
    }
  }

  Future<void> confirmDailyDistributionBatch({
    required DateTime distributionDate,
    required List<
      ({int customerId, List<({int productId, int quantity})> items})
    >
    entries,
  }) async {
    await _db.transaction(() async {
      await _saveDailyDistributionBatch(
        distributionDate: distributionDate,
        entries: entries,
      );

      final distributions = await getDistributionsByDate(distributionDate);
      for (final distribution in distributions) {
        if (distribution.status == 'draft') {
          final items = await getDistributionItems(distribution.id);
          if (items.isEmpty) {
            throw StateError(
              'Cannot confirm a distribution without any items.',
            );
          }

          // Snapshot prices for each item before confirming
          await _snapshotDistributionPrices(
            distributionDate: distributionDate,
            items: items,
          );

          await (_db.update(
            _db.dailyDistributions,
          )..where((tbl) => tbl.id.equals(distribution.id))).write(
            DailyDistributionsCompanion(
              status: const Value('confirmed'),
              updatedAt: Value(DateTime.now()),
            ),
          );
        } else if (distribution.status != 'confirmed') {
          throw StateError('Invalid distribution status.');
        }
      }
    });
  }

  /// Snapshot prices for all items in a distribution on the given date.
  ///
  /// For each item, looks up the price that was effective on distributionDate,
  /// then stores unitPricePaise and lineAmountPaise in the item.
  /// If an item's quantity is 0, lineAmountPaise is set to 0.
  /// If no price exists for a product on that date, throws StateError.
  Future<void> _snapshotDistributionPrices({
    required DateTime distributionDate,
    required List<DailyDistributionItem> items,
  }) async {
    if (items.isEmpty) {
      return;
    }

    // Collect product IDs and get their prices on the distribution date
    final productIds = items.map((item) => item.productId).toList();
    final pricesByProduct = <int, ProductPrice?>{};

    for (final productId in productIds) {
      final price = await _pricingRepository.getPriceOnDate(
        productId: productId,
        date: distributionDate,
      );
      pricesByProduct[productId] = price;
    }

    // Update each item with snapshotted price and line amount
    for (final item in items) {
      final price = pricesByProduct[item.productId];

      // For zero-quantity items, store 0 for both price and amount
      if (item.quantity == 0) {
        await (_db.update(
          _db.dailyDistributionItems,
        )..where((tbl) => tbl.id.equals(item.id))).write(
          DailyDistributionItemsCompanion(
            unitPricePaise: const Value(0),
            lineAmountPaise: const Value(0),
            updatedAt: Value(DateTime.now()),
          ),
        );
        continue;
      }

      // For non-zero quantities, require a price
      if (price == null) {
        throw StateError(
          'Cannot confirm distribution: Product ${item.productId} has no price configured '
          'for ${_normalizeBusinessDate(distributionDate)}. '
          'Please set a price before confirming.',
        );
      }

      final lineAmount = item.quantity * price.pricePerBaseUnitPaise;

      await (_db.update(
        _db.dailyDistributionItems,
      )..where((tbl) => tbl.id.equals(item.id))).write(
        DailyDistributionItemsCompanion(
          unitPricePaise: Value(price.pricePerBaseUnitPaise),
          lineAmountPaise: Value(lineAmount),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  DateTime _normalizeBusinessDate(DateTime value) {
    return DateTime.utc(value.year, value.month, value.day);
  }

  Future<DailyDistribution> createDistributionWithItems({
    required int customerId,
    required DateTime distributionDate,
    required List<({int productId, int quantity})> items,
  }) async {
    final normalized = _normalizeBusinessDate(distributionDate);

    return _db.transaction(() async {
      final existing =
          await (_db.select(_db.dailyDistributions)
                ..where((tbl) => tbl.customerId.equals(customerId))
                ..where((tbl) => tbl.distributionDate.equals(normalized)))
              .getSingleOrNull();

      if (existing != null) {
        throw StateError(
          'A distribution already exists for this customer on this date.',
        );
      }

      if (items.isEmpty) {
        throw StateError('A distribution must contain at least one item.');
      }

      final productIds = <int>[];
      for (final item in items) {
        if (item.quantity < 0) {
          throw StateError('Quantity cannot be negative.');
        }
        if (productIds.contains(item.productId)) {
          throw StateError(
            'Duplicate product entries are not allowed within a distribution.',
          );
        }
        productIds.add(item.productId);
      }

      final distributionId = await _db
          .into(_db.dailyDistributions)
          .insert(
            DailyDistributionsCompanion(
              customerId: Value(customerId),
              distributionDate: Value(normalized),
              status: const Value('draft'),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      try {
        for (final item in items) {
          await _db
              .into(_db.dailyDistributionItems)
              .insert(
                DailyDistributionItemsCompanion(
                  distributionId: Value(distributionId),
                  productId: Value(item.productId),
                  quantity: Value(item.quantity),
                  createdAt: Value(DateTime.now()),
                  updatedAt: Value(DateTime.now()),
                ),
              );
        }
      } catch (_) {
        await (_db.delete(
          _db.dailyDistributionItems,
        )..where((tbl) => tbl.distributionId.equals(distributionId))).go();
        await (_db.delete(
          _db.dailyDistributions,
        )..where((tbl) => tbl.id.equals(distributionId))).go();
        rethrow;
      }

      final created = await _getDistributionById(distributionId);
      if (created == null) {
        throw StateError('Unable to create distribution.');
      }
      return created;
    });
  }

  /// Create a new draft distribution for a customer on a specific date.
  Future<DailyDistribution> createDraftDistribution({
    required int customerId,
    required DateTime distributionDate,
  }) async {
    final normalized = _normalizeBusinessDate(distributionDate);

    final existing =
        await (_db.select(_db.dailyDistributions)
              ..where((tbl) => tbl.customerId.equals(customerId))
              ..where((tbl) => tbl.distributionDate.equals(normalized)))
            .getSingleOrNull();

    if (existing != null) {
      throw StateError(
        'A distribution already exists for this customer on this date.',
      );
    }

    final id = await _db
        .into(_db.dailyDistributions)
        .insert(
          DailyDistributionsCompanion(
            customerId: Value(customerId),
            distributionDate: Value(normalized),
            status: const Value('draft'),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );

    final created = await _getDistributionById(id);
    if (created == null) {
      throw StateError('Unable to create distribution.');
    }
    return created;
  }

  /// Get a distribution by customer ID and date.
  Future<DailyDistribution?> getDistributionByCustomerAndDate({
    required int customerId,
    required DateTime distributionDate,
  }) async {
    final normalized = _normalizeBusinessDate(distributionDate);

    return (_db.select(_db.dailyDistributions)
          ..where((tbl) => tbl.customerId.equals(customerId))
          ..where((tbl) => tbl.distributionDate.equals(normalized)))
        .getSingleOrNull();
  }

  /// Get all distributions for a specific date.
  Future<List<DailyDistribution>> getDistributionsByDate(
    DateTime distributionDate,
  ) async {
    final normalized = _normalizeBusinessDate(distributionDate);

    return (_db.select(_db.dailyDistributions)
          ..where((tbl) => tbl.distributionDate.equals(normalized))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.customerId)]))
        .get();
  }

  /// Get all items for a distribution.
  Future<List<DailyDistributionItem>> getDistributionItems(
    int distributionId,
  ) async {
    return (_db.select(_db.dailyDistributionItems)
          ..where((tbl) => tbl.distributionId.equals(distributionId))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.productId)]))
        .get();
  }

  /// Add a product to a distribution (draft only).
  Future<DailyDistributionItem> addProductToDistribution({
    required int distributionId,
    required int productId,
    required int quantity,
  }) async {
    final distribution = await _getDistributionById(distributionId);
    if (distribution == null) {
      throw StateError('Distribution not found.');
    }

    if (distribution.status != 'draft') {
      throw StateError('Cannot modify a confirmed distribution.');
    }

    if (quantity < 0) {
      throw StateError('Quantity cannot be negative.');
    }

    // Check if product already exists in this distribution
    final existing =
        await (_db.select(_db.dailyDistributionItems)
              ..where((tbl) => tbl.distributionId.equals(distributionId))
              ..where((tbl) => tbl.productId.equals(productId)))
            .getSingleOrNull();

    if (existing != null) {
      throw StateError(
        'This product is already assigned to this distribution.',
      );
    }

    final id = await _db
        .into(_db.dailyDistributionItems)
        .insert(
          DailyDistributionItemsCompanion(
            distributionId: Value(distributionId),
            productId: Value(productId),
            quantity: Value(quantity),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );

    final created = await (_db.select(
      _db.dailyDistributionItems,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

    if (created == null) {
      throw StateError('Unable to add product to distribution.');
    }
    return created;
  }

  /// Update the quantity of an item in a draft distribution.
  Future<DailyDistributionItem> updateDistributionItemQuantity({
    required int itemId,
    required int quantity,
  }) async {
    final item = await (_db.select(
      _db.dailyDistributionItems,
    )..where((tbl) => tbl.id.equals(itemId))).getSingleOrNull();

    if (item == null) {
      throw StateError('Distribution item not found.');
    }

    // Check distribution status
    final distribution = await _getDistributionById(item.distributionId);
    if (distribution == null) {
      throw StateError('Distribution not found.');
    }

    if (distribution.status != 'draft') {
      throw StateError('Cannot modify a confirmed distribution.');
    }

    if (quantity < 0) {
      throw StateError('Quantity cannot be negative.');
    }

    await (_db.update(
      _db.dailyDistributionItems,
    )..where((tbl) => tbl.id.equals(itemId))).write(
      DailyDistributionItemsCompanion(
        quantity: Value(quantity),
        updatedAt: Value(DateTime.now()),
      ),
    );

    final updated = await (_db.select(
      _db.dailyDistributionItems,
    )..where((tbl) => tbl.id.equals(itemId))).getSingleOrNull();

    if (updated == null) {
      throw StateError('Unable to update distribution item.');
    }
    return updated;
  }

  /// Remove a product from a draft distribution.
  Future<void> removeProductFromDistribution(int itemId) async {
    final item = await (_db.select(
      _db.dailyDistributionItems,
    )..where((tbl) => tbl.id.equals(itemId))).getSingleOrNull();

    if (item == null) {
      throw StateError('Distribution item not found.');
    }

    // Check distribution status
    final distribution = await _getDistributionById(item.distributionId);
    if (distribution == null) {
      throw StateError('Distribution not found.');
    }

    if (distribution.status != 'draft') {
      throw StateError('Cannot modify a confirmed distribution.');
    }

    await (_db.delete(
      _db.dailyDistributionItems,
    )..where((tbl) => tbl.id.equals(itemId))).go();
  }

  /// Confirm a distribution (change status from draft to confirmed).
  Future<DailyDistribution> confirmDistribution(int distributionId) async {
    final distribution = await _getDistributionById(distributionId);
    if (distribution == null) {
      throw StateError('Distribution not found.');
    }

    if (distribution.status != 'draft') {
      throw StateError('Only draft distributions can be confirmed.');
    }

    // Verify the distribution has at least one item
    final items = await getDistributionItems(distributionId);
    if (items.isEmpty) {
      throw StateError('Cannot confirm a distribution without any items.');
    }

    await (_db.update(
      _db.dailyDistributions,
    )..where((tbl) => tbl.id.equals(distributionId))).write(
      DailyDistributionsCompanion(
        status: const Value('confirmed'),
        updatedAt: Value(DateTime.now()),
      ),
    );

    final confirmed = await _getDistributionById(distributionId);
    if (confirmed == null) {
      throw StateError('Unable to confirm distribution.');
    }
    return confirmed;
  }

  /// Delete a draft distribution (and all its items via cascade).
  Future<void> deleteDraftDistribution(int distributionId) async {
    final distribution = await _getDistributionById(distributionId);
    if (distribution == null) {
      throw StateError('Distribution not found.');
    }

    if (distribution.status != 'draft') {
      throw StateError('Cannot delete a confirmed distribution.');
    }

    await (_db.delete(
      _db.dailyDistributions,
    )..where((tbl) => tbl.id.equals(distributionId))).go();
  }

  /// Internal helper to get a distribution by ID.
  Future<DailyDistribution?> _getDistributionById(int id) async {
    return (_db.select(
      _db.dailyDistributions,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }
}
