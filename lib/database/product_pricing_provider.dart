import 'product_pricing_repository.dart';

/// Abstract interface for product pricing lookups.
///
/// Enables dependency injection and testing with mock implementations.
/// Prices are always in paise (₹100 = 10000 paise).
abstract class ProductPricingProvider {
  /// Get the current price per base unit for a product in paise.
  ///
  /// Returns null if no active price exists for the product.
  /// The "current" price is the price with no end date.
  /// This is used for NEW draft calculations.
  Future<int?> getPricePerUnitInPaise(int productId);

  /// Batch lookup for multiple products' current prices in paise.
  ///
  /// Returns a map of productId → pricePerBaseUnitPaise.
  /// Products without an active price are omitted from the map.
  /// More efficient than calling getPricePerUnitInPaise multiple times.
  Future<Map<int, int>> getPricesPerUnitInPaise(List<int> productIds);
}

/// Production implementation using database-backed pricing.
final class DatabaseProductPricingProvider implements ProductPricingProvider {
  DatabaseProductPricingProvider(this._pricingRepository);

  final ProductPricingRepository _pricingRepository;

  @override
  Future<int?> getPricePerUnitInPaise(int productId) async {
    final price = await _pricingRepository.getCurrentPrice(productId);
    return price?.pricePerBaseUnitPaise;
  }

  @override
  Future<Map<int, int>> getPricesPerUnitInPaise(List<int> productIds) async {
    if (productIds.isEmpty) {
      return {};
    }

    // Fetch all product prices from database
    // (In a real implementation, this would be a single query with IN clause;
    // Drift limitations may require multiple queries)
    final result = <int, int>{};

    for (final productId in productIds) {
      final price = await _pricingRepository.getCurrentPrice(productId);
      if (price != null) {
        result[productId] = price.pricePerBaseUnitPaise;
      }
    }

    return result;
  }
}

/// Test implementation that raises an error.
/// Useful for catching code paths that incorrectly use pricing before it's implemented.
final class NoPricingAvailableProvider implements ProductPricingProvider {
  @override
  Future<int?> getPricePerUnitInPaise(int productId) async {
    throw UnsupportedError(
      'Pricing is not available. '
      'This is a placeholder provider. '
      'Use DatabaseProductPricingProvider with ProductPricingRepository instead.',
    );
  }

  @override
  Future<Map<int, int>> getPricesPerUnitInPaise(List<int> productIds) async {
    throw UnsupportedError(
      'Pricing is not available. '
      'This is a placeholder provider. '
      'Use DatabaseProductPricingProvider with ProductPricingRepository instead.',
    );
  }
}
