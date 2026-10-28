import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyom_business/database/app_database.dart';
import 'package:vyom_business/database/customer_ledger_service.dart';
import 'package:vyom_business/database/daily_distribution_repository.dart';
import 'package:vyom_business/database/customer_repository.dart';
import 'package:vyom_business/database/product_repository.dart';
import 'package:vyom_business/database/product_pricing_provider.dart';
import 'package:vyom_business/database/product_pricing_repository.dart';

void main() {
  late AppDatabase db;
  late DailyDistributionRepository distributionRepository;
  late CustomerRepository customerRepository;
  late ProductRepository productRepository;
  late ProductPricingRepository pricingRepository;
  late CustomerLedgerService ledgerService;

  /// Helper to normalize dates to UTC calendar day boundary.
  DateTime dateUtc(int year, int month, int day) {
    return DateTime.utc(year, month, day);
  }

  setUp(() async {
    db = AppDatabase(executor: NativeDatabase.memory());
    customerRepository = CustomerRepository(db);
    productRepository = ProductRepository(db);
    pricingRepository = ProductPricingRepository(db);
    distributionRepository = DailyDistributionRepository(db, pricingRepository);
    ledgerService = CustomerLedgerService(
      db,
      DatabaseProductPricingProvider(pricingRepository),
    );

    // Create test data
    await customerRepository.createCustomer(
      name: 'Test Customer',
      address: 'Test Address',
      mobile: '9999999999',
    );

    await productRepository.createProduct(name: 'Milk', unit: 'litre');
  });

  tearDown(() async {
    await db.close();
  });

  group('Distribution Price Snapshotting', () {
    test('Draft distribution has no price snapshots', () async {
      // Create a draft distribution
      await distributionRepository.saveDailyDistributionBatch(
        distributionDate: dateUtc(2024, 8, 1),
        entries: [
          (customerId: 1, items: [(productId: 1, quantity: 10)]),
        ],
      );

      final items = await distributionRepository.getDistributionItems(1);
      expect(items.length, 1);
      expect(items[0].unitPricePaise, isNull);
      expect(items[0].lineAmountPaise, isNull);
    });

    test(
      'Confirmation snapshots price when product has active price',
      () async {
        // Set current price: ₹50/litre
        await pricingRepository.createPrice(
          productId: 1,
          pricePerBaseUnitPaise: 5000,
          fromDate: dateUtc(2024, 8, 1),
        );

        // Create and confirm distribution
        await distributionRepository.confirmDailyDistributionBatch(
          distributionDate: dateUtc(2024, 8, 1),
          entries: [
            (customerId: 1, items: [(productId: 1, quantity: 10)]),
          ],
        );

        final items = await distributionRepository.getDistributionItems(1);
        expect(items[0].unitPricePaise, 5000);
        expect(items[0].lineAmountPaise, 50000); // 10 * 5000
      },
    );

    test('Confirmation throws when product has no price', () async {
      // Create draft WITHOUT setting price
      await distributionRepository.saveDailyDistributionBatch(
        distributionDate: dateUtc(2024, 8, 1),
        entries: [
          (customerId: 1, items: [(productId: 1, quantity: 10)]),
        ],
      );

      // Try to confirm - should fail
      expect(
        () => distributionRepository.confirmDailyDistributionBatch(
          distributionDate: dateUtc(2024, 8, 1),
          entries: [
            (customerId: 1, items: [(productId: 1, quantity: 10)]),
          ],
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('Zero quantity items have zero line amount on confirmation', () async {
      // Set price
      await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 5000,
        fromDate: dateUtc(2024, 8, 1),
      );

      // Create distribution with zero quantity
      await distributionRepository.confirmDailyDistributionBatch(
        distributionDate: dateUtc(2024, 8, 1),
        entries: [
          (customerId: 1, items: [(productId: 1, quantity: 0)]),
        ],
      );

      final items = await distributionRepository.getDistributionItems(1);
      expect(items[0].unitPricePaise, 0);
      expect(items[0].lineAmountPaise, 0);
    });

    test('Confirmation uses price effective on distribution date', () async {
      // Set prices: ₹50 until Aug 15
      await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 5000,
        fromDate: dateUtc(2024, 8, 1),
        toDate: dateUtc(2024, 8, 15),
      );

      // Then ₹55 from Aug 15 onwards
      await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 5500,
        fromDate: dateUtc(2024, 8, 15),
      );

      // Distribution on Aug 10 should use ₹50
      await distributionRepository.confirmDailyDistributionBatch(
        distributionDate: dateUtc(2024, 8, 10),
        entries: [
          (customerId: 1, items: [(productId: 1, quantity: 10)]),
        ],
      );

      final itemsAug10 = await distributionRepository.getDistributionItems(1);
      expect(itemsAug10[0].unitPricePaise, 5000);
      expect(itemsAug10[0].lineAmountPaise, 50000); // 10 * 5000

      // Distribution on Aug 20 should use ₹55
      await distributionRepository.confirmDailyDistributionBatch(
        distributionDate: dateUtc(2024, 8, 20),
        entries: [
          (customerId: 1, items: [(productId: 1, quantity: 10)]),
        ],
      );

      final itemsAug20 = await distributionRepository.getDistributionItems(2);
      expect(itemsAug20[0].unitPricePaise, 5500);
      expect(itemsAug20[0].lineAmountPaise, 55000); // 10 * 5500
    });
  });

  group('Regression: Historical Pricing Immutability', () {
    test(
      'CRITICAL: Price change does not affect confirmed distribution charge',
      () async {
        // Scenario: Milk ₹50 on 01/08, customer takes 10L
        // Later price changes to ₹55 on 15/08
        // Then later still ₹60 on 31/08
        // The Aug 1 confirmed distribution MUST eternally show ₹50 charge

        // Step 1: Set initial price ₹50/L (Aug 1)
        await pricingRepository.createPrice(
          productId: 1,
          pricePerBaseUnitPaise: 5000,
          fromDate: dateUtc(2024, 8, 1),
          toDate: dateUtc(2024, 8, 15),
        );

        // Step 2: Confirm distribution on Aug 1 (10L at ₹50 = ₹500)
        await distributionRepository.confirmDailyDistributionBatch(
          distributionDate: dateUtc(2024, 8, 1),
          entries: [
            (customerId: 1, items: [(productId: 1, quantity: 10)]),
          ],
        );

        // Verify initial snapshot
        var items = await distributionRepository.getDistributionItems(1);
        expect(items[0].lineAmountPaise, 50000);

        // Step 3: Price changes to ₹55 on Aug 15
        await pricingRepository.createPrice(
          productId: 1,
          pricePerBaseUnitPaise: 5500,
          fromDate: dateUtc(2024, 8, 15),
          toDate: dateUtc(2024, 8, 31),
        );

        // Verify snapshot is UNCHANGED
        items = await distributionRepository.getDistributionItems(1);
        expect(items[0].lineAmountPaise, 50000);

        // Step 4: Price changes to ₹60 on Aug 31
        await pricingRepository.updatePrice(id: 2, pricePerBaseUnitPaise: 6000);

        // Verify snapshot is STILL unchanged
        items = await distributionRepository.getDistributionItems(1);
        expect(items[0].lineAmountPaise, 50000);

        // Step 5: Customer ledger calculation uses stored snapshot, not current price
        final ledger = await ledgerService.calculateCustomerLedger(
          customerId: 1,
          fromDate: dateUtc(2024, 8, 1),
          toDate: dateUtc(2024, 8, 31),
        );

        // Debit should be ₹500 (from snapshot), not ₹550 or ₹600
        expect(ledger.debitPaise, 50000);
      },
    );

    test('CRITICAL: Draft distribution has no ledger impact; confirmation snapshots', () async {
      // Set price: ₹50/L
      await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 5000,
        fromDate: dateUtc(2024, 8, 1),
      );

      // Create draft distribution (10L at ₹50 = ₹500 when confirmed)
      await distributionRepository.saveDailyDistributionBatch(
        distributionDate: dateUtc(2024, 8, 1),
        entries: [
          (customerId: 1, items: [(productId: 1, quantity: 10)]),
        ],
      );

      // Calculate ledger - should show ₹0 (draft is ignored)
      var ledger = await ledgerService.calculateCustomerLedger(
        customerId: 1,
        fromDate: dateUtc(2024, 8, 1),
        toDate: dateUtc(2024, 8, 31),
      );
      expect(ledger.debitPaise, 0);

      // Close the ₹50 price at Aug 15, then create ₹55 price from Aug 15 onwards
      final firstPrice = await pricingRepository.getCurrentPrice(1);
      if (firstPrice != null) {
        await pricingRepository.updatePrice(
          id: firstPrice.id,
          effectiveTo: dateUtc(2024, 8, 15),
        );
      }

      // Price changes to ₹55
      await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 5500,
        fromDate: dateUtc(2024, 8, 15),
      );

      // Now confirm the distribution - it should use ₹50 (the price on Aug 1)
      await distributionRepository.confirmDailyDistributionBatch(
        distributionDate: dateUtc(2024, 8, 1),
        entries: [
          (customerId: 1, items: [(productId: 1, quantity: 10)]),
        ],
      );

      // Ledger should now show ₹500 (10 * 50, from the snapshot, not 10 * 55)
      ledger = await ledgerService.calculateCustomerLedger(
        customerId: 1,
        fromDate: dateUtc(2024, 8, 1),
        toDate: dateUtc(2024, 8, 31),
      );
      expect(ledger.debitPaise, 50000);
    });
  });

  group('Distribution Items with Multiple Products', () {
    setUp(() async {
      // Create additional product
      await productRepository.createProduct(name: 'Yogurt', unit: 'kg');
    });

    test('Multiple items in distribution all get price snapshots', () async {
      // Set prices: Milk ₹50/L, Yogurt ₹200/kg
      await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 5000,
        fromDate: dateUtc(2024, 8, 1),
      );

      await pricingRepository.createPrice(
        productId: 2,
        pricePerBaseUnitPaise: 20000,
        fromDate: dateUtc(2024, 8, 1),
      );

      // Confirm distribution with both items
      await distributionRepository.confirmDailyDistributionBatch(
        distributionDate: dateUtc(2024, 8, 1),
        entries: [
          (
            customerId: 1,
            items: [
              (productId: 1, quantity: 10), // 10L milk
              (productId: 2, quantity: 5), // 5kg yogurt
            ],
          ),
        ],
      );

      final items = await distributionRepository.getDistributionItems(1);
      expect(items.length, 2);

      // Milk item
      final milkItem = items.firstWhere((i) => i.productId == 1);
      expect(milkItem.unitPricePaise, 5000);
      expect(milkItem.lineAmountPaise, 50000); // 10 * 5000

      // Yogurt item
      final yogurtItem = items.firstWhere((i) => i.productId == 2);
      expect(yogurtItem.unitPricePaise, 20000);
      expect(yogurtItem.lineAmountPaise, 100000); // 5 * 20000
    });

    test('Ledger correctly sums snapshot line amounts for all items', () async {
      // Set prices
      await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 5000,
        fromDate: dateUtc(2024, 8, 1),
      );

      await pricingRepository.createPrice(
        productId: 2,
        pricePerBaseUnitPaise: 20000,
        fromDate: dateUtc(2024, 8, 1),
      );

      // Confirm distribution
      await distributionRepository.confirmDailyDistributionBatch(
        distributionDate: dateUtc(2024, 8, 1),
        entries: [
          (
            customerId: 1,
            items: [(productId: 1, quantity: 10), (productId: 2, quantity: 5)],
          ),
        ],
      );

      // Calculate ledger
      final ledger = await ledgerService.calculateCustomerLedger(
        customerId: 1,
        fromDate: dateUtc(2024, 8, 1),
        toDate: dateUtc(2024, 8, 31),
      );

      // Total debit = 50000 (milk) + 100000 (yogurt) = 150000
      expect(ledger.debitPaise, 150000);
    });
  });

  group('Precision and Edge Cases', () {
    test('Distribution charge handles paise precision (₹0.01)', () async {
      // Set price: 1 paise per unit
      await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 1,
        fromDate: dateUtc(2024, 8, 1),
      );

      await distributionRepository.confirmDailyDistributionBatch(
        distributionDate: dateUtc(2024, 8, 1),
        entries: [
          (customerId: 1, items: [(productId: 1, quantity: 100)]),
        ],
      );

      final items = await distributionRepository.getDistributionItems(1);
      expect(items[0].lineAmountPaise, 100);
    });

    test('Distribution charge handles large quantities', () async {
      // Set price: ₹50
      await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 5000,
        fromDate: dateUtc(2024, 8, 1),
      );

      // Large quantity: 99999 units
      await distributionRepository.confirmDailyDistributionBatch(
        distributionDate: dateUtc(2024, 8, 1),
        entries: [
          (customerId: 1, items: [(productId: 1, quantity: 99999)]),
        ],
      );

      final items = await distributionRepository.getDistributionItems(1);
      expect(items[0].lineAmountPaise, 99999 * 5000);
    });
  });
}
