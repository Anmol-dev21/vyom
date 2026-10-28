import 'package:drift/drift.dart';

import 'app_database.dart';

/// Repository for managing historical product pricing.
///
/// Ensures that price changes are tracked with non-overlapping effective periods.
/// This enables historical ledger calculations to use the correct price for any given date.
/// Critical constraint: NEVER allow overlapping price periods for the same product.
class ProductPricingRepository {
  ProductPricingRepository(this._db);

  final AppDatabase _db;

  /// Get the price for a product on a specific date.
  ///
  /// Returns the price where [date] falls within [effectiveFrom, effectiveTo).
  /// Returns null if no price is defined for that date.
  /// [date] is normalized to UTC calendar day boundary.
  Future<ProductPrice?> getPriceOnDate({
    required int productId,
    required DateTime date,
  }) async {
    final normalized = _normalizeBusinessDate(date);

    return (_db.select(_db.productPrices)
          ..where((tbl) => tbl.productId.equals(productId))
          ..where((tbl) => tbl.effectiveFrom.isSmallerOrEqualValue(normalized))
          ..where(
            (tbl) =>
                tbl.effectiveTo.isNull() |
                tbl.effectiveTo.isBiggerThanValue(normalized),
          )
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.effectiveFrom)]))
        .getSingleOrNull();
  }

  /// Get the currently active price for a product.
  ///
  /// Returns the price with no end date (effectiveTo is NULL).
  /// Returns null if no active price exists.
  Future<ProductPrice?> getCurrentPrice(int productId) async {
    return (_db.select(_db.productPrices)
          ..where((tbl) => tbl.productId.equals(productId))
          ..where((tbl) => tbl.effectiveTo.isNull())
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.effectiveFrom)]))
        .getSingleOrNull();
  }

  /// Get the price history for a product within a date range.
  ///
  /// Returns all price periods that overlap with [fromDate, toDate].
  /// Dates are normalized to UTC calendar day boundaries.
  /// Results ordered by effectiveFrom descending (newest first).
  Future<List<ProductPrice>> getPriceHistory({
    required int productId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final normalizedFrom = _normalizeBusinessDate(fromDate);
    final normalizedTo = _normalizeBusinessDate(toDate);

    return (_db.select(_db.productPrices)
          ..where((tbl) => tbl.productId.equals(productId))
          // Overlaps with date range: effectiveFrom <= toDate AND (effectiveTo > fromDate OR effectiveTo is NULL)
          ..where(
            (tbl) => tbl.effectiveFrom.isSmallerOrEqualValue(normalizedTo),
          )
          ..where(
            (tbl) =>
                tbl.effectiveTo.isNull() |
                tbl.effectiveTo.isBiggerThanValue(normalizedFrom),
          )
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.effectiveFrom)]))
        .get();
  }

  /// Create a new price entry.
  ///
  /// Throws StateError if:
  /// - [pricePerBaseUnitPaise] is negative
  /// - [fromDate] is after [toDate] (if toDate is provided)
  /// - An overlapping price period already exists for this product
  /// - A price with no end date already exists for this product
  ///
  /// [fromDate] and [toDate] are normalized to UTC calendar day boundaries.
  Future<ProductPrice> createPrice({
    required int productId,
    required int pricePerBaseUnitPaise,
    required DateTime fromDate,
    DateTime? toDate,
  }) async {
    if (pricePerBaseUnitPaise < 0) {
      throw StateError('Price cannot be negative.');
    }

    final normalizedFrom = _normalizeBusinessDate(fromDate);
    final normalizedTo = toDate != null ? _normalizeBusinessDate(toDate) : null;

    if (normalizedTo != null && normalizedFrom.isAfter(normalizedTo)) {
      throw StateError('fromDate must not be after toDate.');
    }

    // Check for overlaps
    await _validateNoOverlap(
      productId: productId,
      fromDate: normalizedFrom,
      toDate: normalizedTo,
    );

    final id = await _db
        .into(_db.productPrices)
        .insert(
          ProductPricesCompanion(
            productId: Value(productId),
            pricePerBaseUnitPaise: Value(pricePerBaseUnitPaise),
            effectiveFrom: Value(normalizedFrom),
            effectiveTo: normalizedTo != null
                ? Value(normalizedTo)
                : const Value.absent(),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );

    final created = await (_db.select(
      _db.productPrices,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

    if (created == null) {
      throw StateError('Unable to create price entry.');
    }

    return created;
  }

  /// Update an existing price entry.
  ///
  /// Can update: pricePerBaseUnitPaise, effectiveTo.
  /// Cannot update: productId, effectiveFrom (immutable business logic).
  ///
  /// Throws StateError if price not found or validation fails.
  Future<ProductPrice> updatePrice({
    required int id,
    int? pricePerBaseUnitPaise,
    DateTime? effectiveTo,
  }) async {
    final existing = await (_db.select(
      _db.productPrices,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

    if (existing == null) {
      throw StateError('Price entry not found.');
    }

    if (pricePerBaseUnitPaise != null && pricePerBaseUnitPaise < 0) {
      throw StateError('Price cannot be negative.');
    }

    final newEffectiveTo = effectiveTo != null
        ? _normalizeBusinessDate(effectiveTo)
        : null;

    // If updating effectiveTo, validate against effectiveFrom
    if (newEffectiveTo != null &&
        existing.effectiveFrom.isAfter(newEffectiveTo)) {
      throw StateError(
        'effectiveTo must not be before or equal to effectiveFrom.',
      );
    }

    // If changing the end date, re-validate for overlaps
    if (newEffectiveTo != existing.effectiveTo) {
      await _validateNoOverlapForUpdate(
        id: id,
        productId: existing.productId,
        fromDate: existing.effectiveFrom,
        toDate: newEffectiveTo,
      );
    }

    await (_db.update(
      _db.productPrices,
    )..where((tbl) => tbl.id.equals(id))).write(
      ProductPricesCompanion(
        pricePerBaseUnitPaise: pricePerBaseUnitPaise != null
            ? Value(pricePerBaseUnitPaise)
            : const Value.absent(),
        effectiveTo: effectiveTo != null
            ? Value(newEffectiveTo)
            : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );

    final updated = await (_db.select(
      _db.productPrices,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

    if (updated == null) {
      throw StateError('Unable to update price entry.');
    }

    return updated;
  }

  /// Delete a price entry.
  ///
  /// Throws StateError if price not found.
  Future<void> deletePrice(int id) async {
    final existing = await (_db.select(
      _db.productPrices,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

    if (existing == null) {
      throw StateError('Price entry not found.');
    }

    await (_db.delete(
      _db.productPrices,
    )..where((tbl) => tbl.id.equals(id))).go();
  }

  /// Validate that a new price entry does not overlap with existing prices.
  ///
  /// Throws StateError if:
  /// - New price overlaps with an existing price
  /// - A price with no end date already exists (only one open-ended price allowed per product)
  Future<void> _validateNoOverlap({
    required int productId,
    required DateTime fromDate,
    required DateTime? toDate,
  }) async {
    // Check for existing price with no end date
    final openEndedPrice =
        await (_db.select(_db.productPrices)
              ..where((tbl) => tbl.productId.equals(productId))
              ..where((tbl) => tbl.effectiveTo.isNull()))
            .getSingleOrNull();

    if (openEndedPrice != null) {
      throw StateError(
        'Cannot create a new price: an open-ended price already exists. '
        'Close the existing price first by setting its effectiveTo date.',
      );
    }

    // Check for overlaps with existing prices
    // Overlap condition: newFrom <= existingTo AND newTo > existingFrom
    final overlapping =
        await (_db.select(_db.productPrices)
              ..where((tbl) => tbl.productId.equals(productId))
              ..where(
                (tbl) => tbl.effectiveFrom.isSmallerOrEqualValue(
                  toDate ?? DateTime(2099, 12, 31), // Far future if no end date
                ),
              )
              ..where(
                (tbl) =>
                    tbl.effectiveTo.isNull() |
                    tbl.effectiveTo.isBiggerThanValue(fromDate),
              ))
            .get();

    if (overlapping.isNotEmpty) {
      throw StateError(
        'Cannot create price: it overlaps with existing price period. '
        'Product ID: $productId, New period: $fromDate to ${toDate ?? "open"}.',
      );
    }
  }

  /// Validate that updating a price entry does not create overlaps.
  ///
  /// Used when updating the effectiveTo date of an existing entry.
  /// [id] is the entry being updated (excluded from overlap check).
  Future<void> _validateNoOverlapForUpdate({
    required int id,
    required int productId,
    required DateTime fromDate,
    required DateTime? toDate,
  }) async {
    // Check for overlaps with OTHER existing prices (exclude self)
    final overlapping =
        await (_db.select(_db.productPrices)
              ..where((tbl) => tbl.productId.equals(productId))
              ..where(
                (tbl) => tbl.id.isNotValue(id),
              ) // Exclude the entry being updated
              ..where(
                (tbl) => tbl.effectiveFrom.isSmallerOrEqualValue(
                  toDate ?? DateTime(2099, 12, 31),
                ),
              )
              ..where(
                (tbl) =>
                    tbl.effectiveTo.isNull() |
                    tbl.effectiveTo.isBiggerThanValue(fromDate),
              ))
            .get();

    if (overlapping.isNotEmpty) {
      throw StateError(
        'Cannot update price: it would overlap with existing price period. '
        'Product ID: $productId.',
      );
    }
  }

  /// Normalize a date to UTC calendar day boundary (midnight UTC).
  DateTime _normalizeBusinessDate(DateTime date) {
    return DateTime.utc(date.year, date.month, date.day);
  }
}
