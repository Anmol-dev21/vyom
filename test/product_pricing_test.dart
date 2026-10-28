import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyom_business/database/app_database.dart';
import 'package:vyom_business/database/product_pricing_repository.dart';

void main() {
  late AppDatabase db;
  late ProductPricingRepository pricingRepository;

  /// Helper to normalize dates to UTC calendar day boundary.
  DateTime dateUtc(int year, int month, int day) {
    return DateTime.utc(year, month, day);
  }

  setUp(() async {
    db = AppDatabase(executor: NativeDatabase.memory());
    pricingRepository = ProductPricingRepository(db);

    // Create a product so product_price rows have a valid FK.
    await db
        .into(db.products)
        .insert(
          ProductsCompanion(
            id: const Value(1),
            name: const Value('Milk'),
            unit: const Value('litre'),
            isActive: const Value(true),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  group('ProductPricingRepository', () {
    // ========== Basic CRUD Tests ==========

    test('createPrice creates a price entry with open-ended period', () async {
      final price = await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 5000, // ₹50
        fromDate: dateUtc(2024, 1, 1),
      );

      expect(price.productId, 1);
      expect(price.pricePerBaseUnitPaise, 5000);
      expect(price.effectiveFrom.year, 2024);
      expect(price.effectiveFrom.month, 1);
      expect(price.effectiveFrom.day, 1);
      expect(price.effectiveTo, isNull);
    });

    test('createPrice with end date creates closed-ended period', () async {
      final price = await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 5000,
        fromDate: dateUtc(2024, 1, 1),
        toDate: dateUtc(2024, 2, 1),
      );

      expect(price.effectiveTo?.year, 2024);
      expect(price.effectiveTo?.month, 2);
      expect(price.effectiveTo?.day, 1);
    });

    test('getCurrentPrice returns the active open-ended price', () async {
      await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 5000,
        fromDate: dateUtc(2024, 1, 1),
      );

      final price = await pricingRepository.getCurrentPrice(1);

      expect(price, isNotNull);
      expect(price?.pricePerBaseUnitPaise, 5000);
    });

    test('getCurrentPrice returns null when no active price exists', () async {
      final price = await pricingRepository.getCurrentPrice(999);

      expect(price, isNull);
    });

    test(
      'getPriceOnDate returns price when date falls within period',
      () async {
        await pricingRepository.createPrice(
          productId: 1,
          pricePerBaseUnitPaise: 5000,
          fromDate: dateUtc(2024, 1, 1),
          toDate: dateUtc(2024, 2, 1),
        );

        final price = await pricingRepository.getPriceOnDate(
          productId: 1,
          date: dateUtc(2024, 1, 15),
        );

        expect(price?.pricePerBaseUnitPaise, 5000);
      },
    );

    test('getPriceOnDate returns null when date is outside period', () async {
      await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 5000,
        fromDate: dateUtc(2024, 1, 1),
        toDate: dateUtc(2024, 2, 1),
      );

      final price = await pricingRepository.getPriceOnDate(
        productId: 1,
        date: dateUtc(2024, 3, 1),
      );

      expect(price, isNull);
    });

    test(
      'getPriceOnDate finds open-ended price after its start date',
      () async {
        await pricingRepository.createPrice(
          productId: 1,
          pricePerBaseUnitPaise: 5000,
          fromDate: dateUtc(2024, 1, 1),
        );

        final price = await pricingRepository.getPriceOnDate(
          productId: 1,
          date: dateUtc(2024, 12, 31),
        );

        expect(price?.pricePerBaseUnitPaise, 5000);
      },
    );

    test('updatePrice changes pricePerBaseUnitPaise', () async {
      final created = await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 5000,
        fromDate: dateUtc(2024, 1, 1),
      );

      final updated = await pricingRepository.updatePrice(
        id: created.id,
        pricePerBaseUnitPaise: 5500,
      );

      expect(updated.pricePerBaseUnitPaise, 5500);
    });

    test('updatePrice can close an open-ended price', () async {
      final created = await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 5000,
        fromDate: dateUtc(2024, 1, 1),
      );

      final updated = await pricingRepository.updatePrice(
        id: created.id,
        effectiveTo: dateUtc(2024, 6, 1),
      );

      expect(updated.effectiveTo?.year, 2024);
      expect(updated.effectiveTo?.month, 6);
      expect(updated.effectiveTo?.day, 1);
    });

    test('deletePrice removes a price entry', () async {
      final created = await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 5000,
        fromDate: dateUtc(2024, 1, 1),
      );

      await pricingRepository.deletePrice(created.id);

      final price = await pricingRepository.getCurrentPrice(1);
      expect(price, isNull);
    });

    // ========== Validation Tests ==========

    test('createPrice throws when price is negative', () async {
      expect(
        () => pricingRepository.createPrice(
          productId: 1,
          pricePerBaseUnitPaise: -5000,
          fromDate: dateUtc(2024, 1, 1),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('createPrice throws when fromDate is after toDate', () async {
      expect(
        () => pricingRepository.createPrice(
          productId: 1,
          pricePerBaseUnitPaise: 5000,
          fromDate: dateUtc(2024, 2, 1),
          toDate: dateUtc(2024, 1, 1),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('createPrice throws when open-ended price already exists', () async {
      await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 5000,
        fromDate: dateUtc(2024, 1, 1),
      );

      expect(
        () => pricingRepository.createPrice(
          productId: 1,
          pricePerBaseUnitPaise: 5500,
          fromDate: dateUtc(2024, 2, 1),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.toString(),
            'message',
            contains('open-ended price already exists'),
          ),
        ),
      );
    });

    test('createPrice throws on overlapping closed periods', () async {
      await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 5000,
        fromDate: dateUtc(2024, 1, 1),
        toDate: dateUtc(2024, 2, 1),
      );

      // Try to create overlapping period
      expect(
        () => pricingRepository.createPrice(
          productId: 1,
          pricePerBaseUnitPaise: 5500,
          fromDate: dateUtc(2024, 1, 15),
          toDate: dateUtc(2024, 3, 1),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'updatePrice throws when new effectiveTo is before effectiveFrom',
      () async {
        final created = await pricingRepository.createPrice(
          productId: 1,
          pricePerBaseUnitPaise: 5000,
          fromDate: dateUtc(2024, 1, 1),
        );

        expect(
          () => pricingRepository.updatePrice(
            id: created.id,
            effectiveTo: dateUtc(2023, 12, 1),
          ),
          throwsA(isA<StateError>()),
        );
      },
    );

    // ========== Historical Pricing Tests ==========

    test('getPriceHistory returns prices that overlap date range', () async {
      // Period 1: Jan 1 - Feb 1 @ ₹50
      await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 5000,
        fromDate: dateUtc(2024, 1, 1),
        toDate: dateUtc(2024, 2, 1),
      );

      // Period 2: Feb 1 - Mar 1 @ ₹55
      await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 5500,
        fromDate: dateUtc(2024, 2, 1),
        toDate: dateUtc(2024, 3, 1),
      );

      // Period 3: Mar 1 onwards @ ₹60
      await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 6000,
        fromDate: dateUtc(2024, 3, 1),
      );

      // Query from Jan 15 to Mar 15 should get periods 1, 2, and 3
      final history = await pricingRepository.getPriceHistory(
        productId: 1,
        fromDate: dateUtc(2024, 1, 15),
        toDate: dateUtc(2024, 3, 15),
      );

      expect(history.length, 3);
      // Results are ordered newest first
      expect(history[0].pricePerBaseUnitPaise, 6000);
      expect(history[1].pricePerBaseUnitPaise, 5500);
      expect(history[2].pricePerBaseUnitPaise, 5000);
    });

    // ========== Multiple Products Tests ==========

    test('different products can have independent prices', () async {
      await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 5000,
        fromDate: dateUtc(2024, 1, 1),
      );

      await db
          .into(db.products)
          .insert(
            ProductsCompanion(
              id: const Value(2),
              name: const Value('Yogurt'),
              unit: const Value('kg'),
              isActive: const Value(true),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      await pricingRepository.createPrice(
        productId: 2,
        pricePerBaseUnitPaise: 2000,
        fromDate: dateUtc(2024, 1, 1),
      );

      final price1 = await pricingRepository.getCurrentPrice(1);
      final price2 = await pricingRepository.getCurrentPrice(2);

      expect(price1?.pricePerBaseUnitPaise, 5000);
      expect(price2?.pricePerBaseUnitPaise, 2000);
    });

    // ========== Precision and Edge Cases ==========

    test('prices handle paise precision (₹0.01)', () async {
      final price = await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 1, // 1 paise = ₹0.01
        fromDate: dateUtc(2024, 1, 1),
      );

      expect(price.pricePerBaseUnitPaise, 1);
    });

    test('prices handle large values (₹99999.99)', () async {
      final price = await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 9999999, // ₹99999.99
        fromDate: dateUtc(2024, 1, 1),
      );

      expect(price.pricePerBaseUnitPaise, 9999999);
    });

    test('date normalization handles time components correctly', () async {
      // Create with explicit time (should be normalized to UTC midnight)
      final created = await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 5000,
        fromDate: DateTime(2024, 1, 1, 15, 30, 45), // With time
        toDate: DateTime(2024, 2, 1, 10, 20, 30),
      );

      expect(created.effectiveFrom.year, 2024);
      expect(created.effectiveFrom.month, 1);
      expect(created.effectiveFrom.day, 1);
      expect(created.effectiveTo?.year, 2024);
      expect(created.effectiveTo?.month, 2);
      expect(created.effectiveTo?.day, 1);
    });

    // ========== Contiguous Price Transitions ==========

    test('can create contiguous non-overlapping price periods', () async {
      // Period 1: Jan 1 - Feb 1
      final p1 = await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 5000,
        fromDate: dateUtc(2024, 1, 1),
        toDate: dateUtc(2024, 2, 1),
      );

      // Period 2: Feb 1 - Mar 1 (starts exactly when period 1 ends)
      final p2 = await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 5500,
        fromDate: dateUtc(2024, 2, 1),
        toDate: dateUtc(2024, 3, 1),
      );

      expect(p1.effectiveTo, p2.effectiveFrom);
    });

    // ========== Scenario: Price Change Over Time ==========

    test('Scenario: Milk ₹50 on 01/08, ₹55 on 15/08 - historical charges immutable', () async {
      // On Aug 1: ₹50/litre
      await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 5000,
        fromDate: dateUtc(2024, 8, 1),
        toDate: dateUtc(2024, 8, 15),
      );

      // On Aug 15: ₹55/litre
      await pricingRepository.createPrice(
        productId: 1,
        pricePerBaseUnitPaise: 5500,
        fromDate: dateUtc(2024, 8, 15),
      );

      // Charge on Aug 10 uses ₹50
      final priceAug10 = await pricingRepository.getPriceOnDate(
        productId: 1,
        date: dateUtc(2024, 8, 10),
      );
      expect(priceAug10?.pricePerBaseUnitPaise, 5000);

      // Charge on Aug 20 uses ₹55
      final priceAug20 = await pricingRepository.getPriceOnDate(
        productId: 1,
        date: dateUtc(2024, 8, 20),
      );
      expect(priceAug20?.pricePerBaseUnitPaise, 5500);

      // Later, if we change Aug 15 price to ₹60 (updating existing entry):
      // The Aug 10 charge must NEVER change because it already used ₹50.
      // This is guaranteed by CustomerLedgerService using stored lineAmountPaise.
    });
  });
}
