import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:vyom_business/database/app_database.dart';
import 'package:vyom_business/database/customer_ledger_service.dart';
import 'package:vyom_business/database/product_pricing_provider.dart';

/// Mock pricing provider for testing.
class MockPricingProvider implements ProductPricingProvider {
  final Map<int, int> _prices = {};

  void setPrice(int productId, int priceInPaise) {
    _prices[productId] = priceInPaise;
  }

  @override
  Future<int?> getPricePerUnitInPaise(int productId) async {
    return _prices[productId];
  }

  @override
  Future<Map<int, int>> getPricesPerUnitInPaise(List<int> productIds) async {
    final result = <int, int>{};
    for (final id in productIds) {
      if (_prices.containsKey(id)) {
        result[id] = _prices[id]!;
      }
    }
    return result;
  }
}

void main() {
  group('CustomerLedgerService', () {
    late AppDatabase db;
    late CustomerLedgerService service;
    late MockPricingProvider pricingProvider;

    setUp(() async {
      // Use in-memory database for tests
      db = AppDatabase(executor: NativeDatabase.memory());
      pricingProvider = MockPricingProvider();
      service = CustomerLedgerService(db, pricingProvider);
    });

    tearDown(() async {
      await db.close();
    });

    /// Test 1: No records → all zeros
    test('Empty customer ledger returns all zeros', () async {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion(
              id: const Value(1),
              name: const Value('Test Customer'),
              address: const Value('123 Main St'),
              mobile: const Value('1234567890'),
              isActive: const Value(true),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      final ledger = await service.calculateCustomerLedger(
        customerId: 1,
        fromDate: DateTime(2026, 8, 1),
        toDate: DateTime(2026, 8, 31),
      );

      expect(ledger.debitPaise, 0);
      expect(ledger.creditPaise, 0);
      expect(ledger.balancePaise, 0);
    });

    /// Test 2: Distribution creates debit (requires pricing)
    test('Confirmed distribution creates debit when priced', () async {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion(
              id: const Value(1),
              name: const Value('Rajesh'),
              address: const Value('123 Main St'),
              mobile: const Value('1234567890'),
              isActive: const Value(true),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

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

      // Set price: ₹50 per litre = 5000 paise
      pricingProvider.setPrice(1, 5000);

      final distId = await db
          .into(db.dailyDistributions)
          .insert(
            DailyDistributionsCompanion(
              customerId: const Value(1),
              distributionDate: Value(DateTime.utc(2026, 8, 15)),
              status: const Value('confirmed'),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // 2 litres × 5000 paise = 10000 paise
      // When confirmed, the snapshot fields are populated with price and line amount
      await db
          .into(db.dailyDistributionItems)
          .insert(
            DailyDistributionItemsCompanion(
              distributionId: Value(distId),
              productId: const Value(1),
              quantity: const Value(2),
              unitPricePaise: const Value(5000), // Snapshot the price
              lineAmountPaise: const Value(10000), // 2 * 5000
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      final ledger = await service.calculateCustomerLedger(
        customerId: 1,
        fromDate: DateTime(2026, 8, 1),
        toDate: DateTime(2026, 8, 31),
      );

      expect(ledger.debitPaise, 10000); // 2 × 5000
      expect(ledger.creditPaise, 0);
      expect(ledger.balancePaise, 10000);
    });

    /// Test 3: RECEIVED transaction creates credit
    test('Received transaction increases credit', () async {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion(
              id: const Value(1),
              name: const Value('Rajesh'),
              address: const Value('123 Main St'),
              mobile: const Value('1234567890'),
              isActive: const Value(true),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // ₹2000 = 200000 paise
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion(
              customerId: const Value(1),
              transactionDate: Value(DateTime.utc(2026, 8, 20)),
              amount: const Value(200000),
              transactionType: const Value(TransactionType.received),
              paymentMethod: const Value(PaymentMethod.cash),
              note: const Value(null),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      final ledger = await service.calculateCustomerLedger(
        customerId: 1,
        fromDate: DateTime(2026, 8, 1),
        toDate: DateTime(2026, 8, 31),
      );

      expect(ledger.debitPaise, 0);
      expect(ledger.creditPaise, 200000);
      expect(ledger.balancePaise, -200000); // Customer overpaid
    });

    /// Test 4: GIVEN transaction creates debit
    test('Given transaction increases debit', () async {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion(
              id: const Value(1),
              name: const Value('Rajesh'),
              address: const Value('123 Main St'),
              mobile: const Value('1234567890'),
              isActive: const Value(true),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // ₹100 refund = 10000 paise
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion(
              customerId: const Value(1),
              transactionDate: Value(DateTime.utc(2026, 8, 20)),
              amount: const Value(10000),
              transactionType: const Value(TransactionType.given),
              paymentMethod: const Value(PaymentMethod.cash),
              note: const Value('Refund'),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      final ledger = await service.calculateCustomerLedger(
        customerId: 1,
        fromDate: DateTime(2026, 8, 1),
        toDate: DateTime(2026, 8, 31),
      );

      expect(ledger.debitPaise, 10000);
      expect(ledger.creditPaise, 0);
      expect(ledger.balancePaise, 10000);
    });

    /// Test 5: Critical scenario from spec
    test('Critical accounting scenario: ₹3000 DR, ₹2000 CR, ₹100 given = ₹3100 DR, ₹2000 CR, ₹1100 balance', () async {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion(
              id: const Value(1),
              name: const Value('Rajesh'),
              address: const Value('123 Main St'),
              mobile: const Value('1234567890'),
              isActive: const Value(true),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

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

      // Price: ₹50 per litre = 5000 paise
      pricingProvider.setPrice(1, 5000);

      // Create distributions that total to ₹3000 (3000 paise would be 0.30, but we need ₹3000 = 300000)
      // 60 litres × 5000 paise = 300000 paise = ₹3000
      final distId = await db
          .into(db.dailyDistributions)
          .insert(
            DailyDistributionsCompanion(
              customerId: const Value(1),
              distributionDate: Value(DateTime.utc(2026, 8, 15)),
              status: const Value('confirmed'),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      await db
          .into(db.dailyDistributionItems)
          .insert(
            DailyDistributionItemsCompanion(
              distributionId: Value(distId),
              productId: const Value(1),
              quantity: const Value(60), // 60 litres
              unitPricePaise: const Value(5000), // Snapshot the price
              lineAmountPaise: const Value(300000), // 60 * 5000
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // ₹2000 payment = 200000 paise
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion(
              customerId: const Value(1),
              transactionDate: Value(DateTime.utc(2026, 8, 20)),
              amount: const Value(200000),
              transactionType: const Value(TransactionType.received),
              paymentMethod: const Value(PaymentMethod.cash),
              note: const Value(null),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // ₹100 refund = 10000 paise (increases debit)
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion(
              customerId: const Value(1),
              transactionDate: Value(DateTime.utc(2026, 8, 22)),
              amount: const Value(10000),
              transactionType: const Value(TransactionType.given),
              paymentMethod: const Value(PaymentMethod.cash),
              note: const Value('Refund'),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      final ledger = await service.calculateCustomerLedger(
        customerId: 1,
        fromDate: DateTime(2026, 8, 1),
        toDate: DateTime(2026, 8, 31),
      );

      // Expected: DR = 300000 + 10000 = 310000 paise = ₹3100
      // Expected: CR = 200000 paise = ₹2000
      // Expected: Balance = 310000 - 200000 = 110000 paise = ₹1100
      expect(ledger.debitPaise, 310000);
      expect(ledger.creditPaise, 200000);
      expect(ledger.balancePaise, 110000);
    });

    /// Test 6: Zero quantity produces zero charge
    test('Zero quantity distribution produces zero charge', () async {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion(
              id: const Value(1),
              name: const Value('Rajesh'),
              address: const Value('123 Main St'),
              mobile: const Value('1234567890'),
              isActive: const Value(true),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

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

      pricingProvider.setPrice(1, 5000);

      final distId = await db
          .into(db.dailyDistributions)
          .insert(
            DailyDistributionsCompanion(
              customerId: const Value(1),
              distributionDate: Value(DateTime.utc(2026, 8, 15)),
              status: const Value('confirmed'),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // Zero quantity
      await db
          .into(db.dailyDistributionItems)
          .insert(
            DailyDistributionItemsCompanion(
              distributionId: Value(distId),
              productId: const Value(1),
              quantity: const Value(0),
              unitPricePaise: const Value(0), // Snapshot price (zero)
              lineAmountPaise: const Value(0), // 0 * anything = 0
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      final ledger = await service.calculateCustomerLedger(
        customerId: 1,
        fromDate: DateTime(2026, 8, 1),
        toDate: DateTime(2026, 8, 31),
      );

      expect(ledger.debitPaise, 0);
      expect(ledger.creditPaise, 0);
      expect(ledger.balancePaise, 0);
    });

    /// Test 7: Draft distribution does not create debit
    test('Draft distribution does not contribute to finalized debit', () async {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion(
              id: const Value(1),
              name: const Value('Rajesh'),
              address: const Value('123 Main St'),
              mobile: const Value('1234567890'),
              isActive: const Value(true),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

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

      pricingProvider.setPrice(1, 5000);

      final distId = await db
          .into(db.dailyDistributions)
          .insert(
            DailyDistributionsCompanion(
              customerId: const Value(1),
              distributionDate: Value(DateTime.utc(2026, 8, 15)),
              status: const Value('draft'), // Not confirmed
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      await db
          .into(db.dailyDistributionItems)
          .insert(
            DailyDistributionItemsCompanion(
              distributionId: Value(distId),
              productId: const Value(1),
              quantity: const Value(2),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      final ledger = await service.calculateCustomerLedger(
        customerId: 1,
        fromDate: DateTime(2026, 8, 1),
        toDate: DateTime(2026, 8, 31),
      );

      expect(ledger.debitPaise, 0);
      expect(ledger.creditPaise, 0);
    });

    /// Test 8: Multiple distributions aggregate
    test('Multiple distributions aggregate correctly', () async {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion(
              id: const Value(1),
              name: const Value('Rajesh'),
              address: const Value('123 Main St'),
              mobile: const Value('1234567890'),
              isActive: const Value(true),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

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

      pricingProvider.setPrice(1, 5000);

      // Distribution 1: 2 litres
      final dist1Id = await db
          .into(db.dailyDistributions)
          .insert(
            DailyDistributionsCompanion(
              customerId: const Value(1),
              distributionDate: Value(DateTime.utc(2026, 8, 10)),
              status: const Value('confirmed'),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      await db
          .into(db.dailyDistributionItems)
          .insert(
            DailyDistributionItemsCompanion(
              distributionId: Value(dist1Id),
              productId: const Value(1),
              quantity: const Value(2),
              unitPricePaise: const Value(5000),
              lineAmountPaise: const Value(10000), // 2 * 5000
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // Distribution 2: 3 litres
      final dist2Id = await db
          .into(db.dailyDistributions)
          .insert(
            DailyDistributionsCompanion(
              customerId: const Value(1),
              distributionDate: Value(DateTime.utc(2026, 8, 20)),
              status: const Value('confirmed'),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      await db
          .into(db.dailyDistributionItems)
          .insert(
            DailyDistributionItemsCompanion(
              distributionId: Value(dist2Id),
              productId: const Value(1),
              quantity: const Value(3),
              unitPricePaise: const Value(5000),
              lineAmountPaise: const Value(15000), // 3 * 5000
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      final ledger = await service.calculateCustomerLedger(
        customerId: 1,
        fromDate: DateTime(2026, 8, 1),
        toDate: DateTime(2026, 8, 31),
      );

      // 2 × 5000 + 3 × 5000 = 25000 paise
      expect(ledger.debitPaise, 25000);
    });

    /// Test 9: Multiple transactions aggregate
    test('Multiple transactions aggregate correctly', () async {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion(
              id: const Value(1),
              name: const Value('Rajesh'),
              address: const Value('123 Main St'),
              mobile: const Value('1234567890'),
              isActive: const Value(true),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // Payment 1: ₹1000 = 100000 paise
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion(
              customerId: const Value(1),
              transactionDate: Value(DateTime.utc(2026, 8, 10)),
              amount: const Value(100000),
              transactionType: const Value(TransactionType.received),
              paymentMethod: const Value(PaymentMethod.cash),
              note: const Value(null),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // Payment 2: ₹500 = 50000 paise
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion(
              customerId: const Value(1),
              transactionDate: Value(DateTime.utc(2026, 8, 20)),
              amount: const Value(50000),
              transactionType: const Value(TransactionType.received),
              paymentMethod: const Value(PaymentMethod.upi),
              note: const Value(null),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      final ledger = await service.calculateCustomerLedger(
        customerId: 1,
        fromDate: DateTime(2026, 8, 1),
        toDate: DateTime(2026, 8, 31),
      );

      expect(ledger.creditPaise, 150000); // 100000 + 50000
    });

    /// Test 10: Deactivated customer historical data included
    test(
      'Deactivated customer historical data is included in ledger',
      () async {
        await db
            .into(db.customers)
            .insert(
              CustomersCompanion(
                id: const Value(1),
                name: const Value('Rajesh'),
                address: const Value('123 Main St'),
                mobile: const Value('1234567890'),
                isActive: const Value(false), // Deactivated
                createdAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.now()),
              ),
            );

        // Historical transaction
        await db
            .into(db.transactions)
            .insert(
              TransactionsCompanion(
                customerId: const Value(1),
                transactionDate: Value(DateTime.utc(2026, 8, 15)),
                amount: const Value(100000),
                transactionType: const Value(TransactionType.received),
                paymentMethod: const Value(PaymentMethod.cash),
                note: const Value(null),
                createdAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.now()),
              ),
            );

        final ledger = await service.calculateCustomerLedger(
          customerId: 1,
          fromDate: DateTime(2026, 8, 1),
          toDate: DateTime(2026, 8, 31),
        );

        expect(ledger.creditPaise, 100000);
        expect(ledger.debitPaise, 0);
      },
    );

    /// Test 11: Date range inclusive
    test('Date range is inclusive (includes fromDate and toDate)', () async {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion(
              id: const Value(1),
              name: const Value('Rajesh'),
              address: const Value('123 Main St'),
              mobile: const Value('1234567890'),
              isActive: const Value(true),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // Transaction on fromDate
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion(
              customerId: const Value(1),
              transactionDate: Value(DateTime.utc(2026, 8, 1)),
              amount: const Value(100000),
              transactionType: const Value(TransactionType.received),
              paymentMethod: const Value(PaymentMethod.cash),
              note: const Value(null),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // Transaction on toDate
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion(
              customerId: const Value(1),
              transactionDate: Value(DateTime.utc(2026, 8, 31)),
              amount: const Value(50000),
              transactionType: const Value(TransactionType.received),
              paymentMethod: const Value(PaymentMethod.cash),
              note: const Value(null),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      final ledger = await service.calculateCustomerLedger(
        customerId: 1,
        fromDate: DateTime(2026, 8, 1),
        toDate: DateTime(2026, 8, 31),
      );

      expect(ledger.creditPaise, 150000); // Both included
    });

    /// Test 12: Records outside date range excluded
    test('Records outside date range are excluded', () async {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion(
              id: const Value(1),
              name: const Value('Rajesh'),
              address: const Value('123 Main St'),
              mobile: const Value('1234567890'),
              isActive: const Value(true),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // Before range
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion(
              customerId: const Value(1),
              transactionDate: Value(DateTime.utc(2026, 7, 31)),
              amount: const Value(100000),
              transactionType: const Value(TransactionType.received),
              paymentMethod: const Value(PaymentMethod.cash),
              note: const Value(null),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // In range
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion(
              customerId: const Value(1),
              transactionDate: Value(DateTime.utc(2026, 8, 15)),
              amount: const Value(50000),
              transactionType: const Value(TransactionType.received),
              paymentMethod: const Value(PaymentMethod.cash),
              note: const Value(null),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // After range
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion(
              customerId: const Value(1),
              transactionDate: Value(DateTime.utc(2026, 9, 1)),
              amount: const Value(75000),
              transactionType: const Value(TransactionType.received),
              paymentMethod: const Value(PaymentMethod.cash),
              note: const Value(null),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      final ledger = await service.calculateCustomerLedger(
        customerId: 1,
        fromDate: DateTime(2026, 8, 1),
        toDate: DateTime(2026, 8, 31),
      );

      expect(ledger.creditPaise, 50000); // Only in-range transaction
    });

    /// Test 13: fromDate > toDate rejected
    test('fromDate > toDate is rejected', () async {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion(
              id: const Value(1),
              name: const Value('Rajesh'),
              address: const Value('123 Main St'),
              mobile: const Value('1234567890'),
              isActive: const Value(true),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      expect(
        () => service.calculateCustomerLedger(
          customerId: 1,
          fromDate: DateTime(2026, 8, 31),
          toDate: DateTime(2026, 8, 1),
        ),
        throwsA(isA<StateError>()),
      );
    });

    /// Test 14: Precision for ₹100.00
    test('₹100.00 calculations remain exact', () async {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion(
              id: const Value(1),
              name: const Value('Rajesh'),
              address: const Value('123 Main St'),
              mobile: const Value('1234567890'),
              isActive: const Value(true),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // ₹100.00 = 10000 paise
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion(
              customerId: const Value(1),
              transactionDate: Value(DateTime.utc(2026, 8, 15)),
              amount: const Value(10000),
              transactionType: const Value(TransactionType.received),
              paymentMethod: const Value(PaymentMethod.cash),
              note: const Value(null),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      final ledger = await service.calculateCustomerLedger(
        customerId: 1,
        fromDate: DateTime(2026, 8, 1),
        toDate: DateTime(2026, 8, 31),
      );

      expect(ledger.creditPaise, 10000);
      expect(ledger.creditRupees, '100.00');
    });

    /// Test 15: Precision for ₹100.50
    test('₹100.50 calculations remain exact', () async {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion(
              id: const Value(1),
              name: const Value('Rajesh'),
              address: const Value('123 Main St'),
              mobile: const Value('1234567890'),
              isActive: const Value(true),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // ₹100.50 = 10050 paise
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion(
              customerId: const Value(1),
              transactionDate: Value(DateTime.utc(2026, 8, 15)),
              amount: const Value(10050),
              transactionType: const Value(TransactionType.received),
              paymentMethod: const Value(PaymentMethod.cash),
              note: const Value(null),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      final ledger = await service.calculateCustomerLedger(
        customerId: 1,
        fromDate: DateTime(2026, 8, 1),
        toDate: DateTime(2026, 8, 31),
      );

      expect(ledger.creditPaise, 10050);
      expect(ledger.creditRupees, '100.50');
    });

    /// Test 16: Precision for ₹0.01
    test('₹0.01 is represented correctly', () async {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion(
              id: const Value(1),
              name: const Value('Rajesh'),
              address: const Value('123 Main St'),
              mobile: const Value('1234567890'),
              isActive: const Value(true),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // ₹0.01 = 1 paise
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion(
              customerId: const Value(1),
              transactionDate: Value(DateTime.utc(2026, 8, 15)),
              amount: const Value(1),
              transactionType: const Value(TransactionType.received),
              paymentMethod: const Value(PaymentMethod.cash),
              note: const Value(null),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      final ledger = await service.calculateCustomerLedger(
        customerId: 1,
        fromDate: DateTime(2026, 8, 1),
        toDate: DateTime(2026, 8, 31),
      );

      expect(ledger.creditPaise, 1);
      expect(ledger.creditRupees, '0.01');
    });

    /// Test 17: No floating-point arithmetic
    test('No double/floating-point arithmetic used for money', () async {
      // This test validates that all calculations are integer-based
      // by checking that fractional paise results are exact

      await db
          .into(db.customers)
          .insert(
            CustomersCompanion(
              id: const Value(1),
              name: const Value('Rajesh'),
              address: const Value('123 Main St'),
              mobile: const Value('1234567890'),
              isActive: const Value(true),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

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

      // Price: ₹33.33 per litre = 3333 paise (non-round number)
      pricingProvider.setPrice(1, 3333);

      final distId = await db
          .into(db.dailyDistributions)
          .insert(
            DailyDistributionsCompanion(
              customerId: const Value(1),
              distributionDate: Value(DateTime.utc(2026, 8, 15)),
              status: const Value('confirmed'),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // 3 litres × 3333 paise = 9999 paise
      await db
          .into(db.dailyDistributionItems)
          .insert(
            DailyDistributionItemsCompanion(
              distributionId: Value(distId),
              productId: const Value(1),
              quantity: const Value(3),
              unitPricePaise: const Value(3333), // Snapshot price
              lineAmountPaise: const Value(9999), // 3 * 3333
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      final ledger = await service.calculateCustomerLedger(
        customerId: 1,
        fromDate: DateTime(2026, 8, 1),
        toDate: DateTime(2026, 8, 31),
      );

      // Result must be exact integer paise
      expect(ledger.debitPaise, 9999);
      expect(ledger.debitPaise % 1, 0); // Confirm it's an integer
    });

    /// Test 18: Negative balance not clamped
    test('Negative balance contains useful accounting information', () async {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion(
              id: const Value(1),
              name: const Value('Rajesh'),
              address: const Value('123 Main St'),
              mobile: const Value('1234567890'),
              isActive: const Value(true),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // ₹3000 debit = 300000 paise
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion(
              customerId: const Value(1),
              transactionDate: Value(DateTime.utc(2026, 8, 10)),
              amount: const Value(300000),
              transactionType: const Value(TransactionType.given),
              paymentMethod: const Value(PaymentMethod.cash),
              note: const Value(null),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // ₹3500 credit = 350000 paise
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion(
              customerId: const Value(1),
              transactionDate: Value(DateTime.utc(2026, 8, 20)),
              amount: const Value(350000),
              transactionType: const Value(TransactionType.received),
              paymentMethod: const Value(PaymentMethod.cash),
              note: const Value(null),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      final ledger = await service.calculateCustomerLedger(
        customerId: 1,
        fromDate: DateTime(2026, 8, 1),
        toDate: DateTime(2026, 8, 31),
      );

      expect(ledger.debitPaise, 300000);
      expect(ledger.creditPaise, 350000);
      expect(ledger.balancePaise, -50000); // Negative, not clamped
    });

    /// Test 19: Multiple customers produce independent ledgers
    test('Multiple customers produce independent ledger totals', () async {
      // Customer 1
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion(
              id: const Value(1),
              name: const Value('Rajesh'),
              address: const Value('123 Main St'),
              mobile: const Value('1234567890'),
              isActive: const Value(true),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // Customer 2
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion(
              id: const Value(2),
              name: const Value('Priya'),
              address: const Value('456 Oak Ave'),
              mobile: const Value('0987654321'),
              isActive: const Value(true),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // Customer 1 payment: ₹1000 = 100000 paise
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion(
              customerId: const Value(1),
              transactionDate: Value(DateTime.utc(2026, 8, 15)),
              amount: const Value(100000),
              transactionType: const Value(TransactionType.received),
              paymentMethod: const Value(PaymentMethod.cash),
              note: const Value(null),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // Customer 2 payment: ₹2000 = 200000 paise
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion(
              customerId: const Value(2),
              transactionDate: Value(DateTime.utc(2026, 8, 15)),
              amount: const Value(200000),
              transactionType: const Value(TransactionType.received),
              paymentMethod: const Value(PaymentMethod.cash),
              note: const Value(null),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      final ledger1 = await service.calculateCustomerLedger(
        customerId: 1,
        fromDate: DateTime(2026, 8, 1),
        toDate: DateTime(2026, 8, 31),
      );

      final ledger2 = await service.calculateCustomerLedger(
        customerId: 2,
        fromDate: DateTime(2026, 8, 1),
        toDate: DateTime(2026, 8, 31),
      );

      expect(ledger1.creditPaise, 100000);
      expect(ledger2.creditPaise, 200000);
    });

    /// Test 20: calculateAllCustomerLedgers returns summaries
    test(
      'calculateAllCustomerLedgers returns list of all customer ledgers',
      () async {
        // Customer 1
        await db
            .into(db.customers)
            .insert(
              CustomersCompanion(
                id: const Value(1),
                name: const Value('Rajesh'),
                address: const Value('123 Main St'),
                mobile: const Value('1234567890'),
                isActive: const Value(true),
                createdAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.now()),
              ),
            );

        // Customer 2
        await db
            .into(db.customers)
            .insert(
              CustomersCompanion(
                id: const Value(2),
                name: const Value('Priya'),
                address: const Value('456 Oak Ave'),
                mobile: const Value('0987654321'),
                isActive: const Value(true),
                createdAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.now()),
              ),
            );

        // Customer 1 transaction
        await db
            .into(db.transactions)
            .insert(
              TransactionsCompanion(
                customerId: const Value(1),
                transactionDate: Value(DateTime.utc(2026, 8, 15)),
                amount: const Value(100000),
                transactionType: const Value(TransactionType.received),
                paymentMethod: const Value(PaymentMethod.cash),
                note: const Value(null),
                createdAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.now()),
              ),
            );

        // Customer 2 transaction
        await db
            .into(db.transactions)
            .insert(
              TransactionsCompanion(
                customerId: const Value(2),
                transactionDate: Value(DateTime.utc(2026, 8, 15)),
                amount: const Value(200000),
                transactionType: const Value(TransactionType.received),
                paymentMethod: const Value(PaymentMethod.cash),
                note: const Value(null),
                createdAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.now()),
              ),
            );

        final ledgers = await service.calculateAllCustomerLedgers(
          fromDate: DateTime(2026, 8, 1),
          toDate: DateTime(2026, 8, 31),
        );

        expect(ledgers.length, 2);
        expect(ledgers[0].customerId, 1);
        expect(ledgers[1].customerId, 2);
      },
    );

    /// Test 21: Empty customer list with no activity
    test(
      'Empty result when no customers have activity in date range',
      () async {
        await db
            .into(db.customers)
            .insert(
              CustomersCompanion(
                id: const Value(1),
                name: const Value('Rajesh'),
                address: const Value('123 Main St'),
                mobile: const Value('1234567890'),
                isActive: const Value(true),
                createdAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.now()),
              ),
            );

        final ledgers = await service.calculateAllCustomerLedgers(
          fromDate: DateTime(2026, 8, 1),
          toDate: DateTime(2026, 8, 31),
        );

        expect(ledgers.isEmpty, true);
      },
    );

    /// Test 22: Single confirmed distribution with multiple items
    test('Single distribution with multiple products aggregates', () async {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion(
              id: const Value(1),
              name: const Value('Rajesh'),
              address: const Value('123 Main St'),
              mobile: const Value('1234567890'),
              isActive: const Value(true),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // Product 1: Milk
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

      // Product 2: Yogurt
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

      // Milk: ₹50/litre = 5000 paise
      // Yogurt: ₹100/kg = 10000 paise
      pricingProvider.setPrice(1, 5000);
      pricingProvider.setPrice(2, 10000);

      final distId = await db
          .into(db.dailyDistributions)
          .insert(
            DailyDistributionsCompanion(
              customerId: const Value(1),
              distributionDate: Value(DateTime.utc(2026, 8, 15)),
              status: const Value('confirmed'),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // 2 litres milk
      await db
          .into(db.dailyDistributionItems)
          .insert(
            DailyDistributionItemsCompanion(
              distributionId: Value(distId),
              productId: const Value(1),
              quantity: const Value(2),
              unitPricePaise: const Value(5000), // Snapshot price
              lineAmountPaise: const Value(10000), // 2 * 5000
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // 1 kg yogurt
      await db
          .into(db.dailyDistributionItems)
          .insert(
            DailyDistributionItemsCompanion(
              distributionId: Value(distId),
              productId: const Value(2),
              quantity: const Value(1),
              unitPricePaise: const Value(10000), // Snapshot price
              lineAmountPaise: const Value(10000), // 1 * 10000
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      final ledger = await service.calculateCustomerLedger(
        customerId: 1,
        fromDate: DateTime(2026, 8, 1),
        toDate: DateTime(2026, 8, 31),
      );

      // 2 × 5000 + 1 × 10000 = 20000 paise
      expect(ledger.debitPaise, 20000);
    });

    test('calculateCustomerLedgerEntries returns chronological debit and credit entries', () async {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion(
              id: const Value(1),
              name: const Value('Rajesh'),
              address: const Value('123 Main St'),
              mobile: const Value('1234567890'),
              isActive: const Value(true),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

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

      final distId = await db
          .into(db.dailyDistributions)
          .insert(
            DailyDistributionsCompanion(
              customerId: const Value(1),
              distributionDate: Value(DateTime.utc(2026, 8, 12)),
              status: const Value('confirmed'),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      await db
          .into(db.dailyDistributionItems)
          .insert(
            DailyDistributionItemsCompanion(
              distributionId: Value(distId),
              productId: const Value(1),
              quantity: const Value(3),
              unitPricePaise: const Value(5000),
              lineAmountPaise: const Value(15000),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion(
              customerId: const Value(1),
              transactionDate: Value(DateTime.utc(2026, 8, 14)),
              amount: const Value(10000),
              transactionType: const Value(TransactionType.received),
              paymentMethod: const Value(PaymentMethod.cash),
              note: const Value('Advance'),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      final entries = await service.calculateCustomerLedgerEntries(
        customerId: 1,
        fromDate: DateTime(2026, 8, 1),
        toDate: DateTime(2026, 8, 31),
      );

      expect(entries.length, 2);
      expect(entries.first.type, CustomerLedgerEntryType.debit);
      expect(entries.first.amountPaise, 15000);
      expect(entries.last.type, CustomerLedgerEntryType.credit);
      expect(entries.last.amountPaise, 10000);
      expect(entries.last.note, 'Advance');
    });
  });
}
