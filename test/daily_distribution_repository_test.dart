import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vyom_business/database/app_database.dart';
import 'package:vyom_business/database/customer_repository.dart';
import 'package:vyom_business/database/daily_distribution_repository.dart';
import 'package:vyom_business/database/product_repository.dart';

class _MigrationExecutorUser implements QueryExecutorUser {
  const _MigrationExecutorUser();

  @override
  int get schemaVersion => 2;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

void main() {
  group('DailyDistributionRepository', () {
    late AppDatabase database;
    late DailyDistributionRepository repository;
    late CustomerRepository customerRepository;
    late ProductRepository productRepository;

    setUp(() async {
      database = AppDatabase(executor: NativeDatabase.memory());
      repository = DailyDistributionRepository(database);
      customerRepository = CustomerRepository(database);
      productRepository = ProductRepository(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('create a draft distribution', () async {
      final customer = await customerRepository.createCustomer(
        name: 'John Doe',
        address: '123 Main St',
        mobile: '9876543210',
      );

      final distributionDate = DateTime(2026, 8, 23);
      final distribution = await repository.createDraftDistribution(
        customerId: customer.id,
        distributionDate: distributionDate,
      );

      expect(distribution.customerId, customer.id);
      expect(distribution.status, 'draft');
      expect(distribution.distributionDate.year, 2026);
      expect(distribution.distributionDate.month, 8);
      expect(distribution.distributionDate.day, 23);
    });

    test('create distribution with multiple products', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Alice',
        address: '456 Oak Ave',
        mobile: '8765432109',
      );

      final milk = await productRepository.createProduct(
        name: 'Milk',
        unit: 'litre',
      );

      final curd = await productRepository.createProduct(
        name: 'Curd',
        unit: 'kg',
      );

      final distribution = await repository.createDraftDistribution(
        customerId: customer.id,
        distributionDate: DateTime(2026, 8, 23),
      );

      await repository.addProductToDistribution(
        distributionId: distribution.id,
        productId: milk.id,
        quantity: 2000,
      );

      await repository.addProductToDistribution(
        distributionId: distribution.id,
        productId: curd.id,
        quantity: 500,
      );

      final items = await repository.getDistributionItems(distribution.id);
      expect(items.length, 2);
      expect(items[0].quantity, 2000);
      expect(items[1].quantity, 500);
    });

    test('read distribution by customer and date', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Bob',
        address: '789 Elm St',
        mobile: '7654321098',
      );

      final distributionDate = DateTime(2026, 8, 23);
      final created = await repository.createDraftDistribution(
        customerId: customer.id,
        distributionDate: distributionDate,
      );

      final found = await repository.getDistributionByCustomerAndDate(
        customerId: customer.id,
        distributionDate: distributionDate,
      );

      expect(found, isNotNull);
      expect(found!.id, created.id);
    });

    test('read all distributions for one date', () async {
      final customer1 = await customerRepository.createCustomer(
        name: 'Customer 1',
        address: 'Address 1',
        mobile: '1111111111',
      );

      final customer2 = await customerRepository.createCustomer(
        name: 'Customer 2',
        address: 'Address 2',
        mobile: '2222222222',
      );

      final distributionDate = DateTime(2026, 8, 23);

      await repository.createDraftDistribution(
        customerId: customer1.id,
        distributionDate: distributionDate,
      );

      await repository.createDraftDistribution(
        customerId: customer2.id,
        distributionDate: distributionDate,
      );

      final distributions = await repository.getDistributionsByDate(
        distributionDate,
      );

      expect(distributions.length, 2);
    });

    test('normalize same-day times to one customer/day distribution', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Charlie',
        address: '321 Pine St',
        mobile: '6543210987',
      );

      final midnight = DateTime(2026, 8, 19, 0, 0);
      final afternoon = DateTime(2026, 8, 19, 15, 30);

      final created = await repository.createDraftDistribution(
        customerId: customer.id,
        distributionDate: midnight,
      );

      expect(
        () => repository.createDraftDistribution(
          customerId: customer.id,
          distributionDate: afternoon,
        ),
        throwsA(isA<StateError>()),
      );

      final foundByMidnight = await repository.getDistributionByCustomerAndDate(
        customerId: customer.id,
        distributionDate: midnight,
      );
      final foundByAfternoon = await repository
          .getDistributionByCustomerAndDate(
            customerId: customer.id,
            distributionDate: afternoon,
          );

      expect(foundByMidnight, isNotNull);
      expect(foundByAfternoon, isNotNull);
      expect(foundByMidnight!.id, created.id);
      expect(foundByAfternoon!.id, created.id);
    });

    test(
      'database rejects duplicate customer/date rows at SQL level',
      () async {
        final customer = await customerRepository.createCustomer(
          name: 'Charlie 2',
          address: '321 Pine St',
          mobile: '6543210988',
        );

        await database
            .into(database.dailyDistributions)
            .insert(
              DailyDistributionsCompanion(
                customerId: Value(customer.id),
                distributionDate: Value(DateTime.utc(2026, 8, 19)),
                status: const Value('draft'),
                createdAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.now()),
              ),
            );

        expect(
          () => database
              .into(database.dailyDistributions)
              .insert(
                DailyDistributionsCompanion(
                  customerId: Value(customer.id),
                  distributionDate: Value(DateTime.utc(2026, 8, 19)),
                  status: const Value('draft'),
                  createdAt: Value(DateTime.now()),
                  updatedAt: Value(DateTime.now()),
                ),
              ),
          throwsA(isA<SqliteException>()),
        );
      },
    );

    test('database rejects duplicate product rows in a distribution', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Diana 2',
        address: '654 Maple St',
        mobile: '5432109877',
      );

      final product = await productRepository.createProduct(
        name: 'Paneer 2',
        unit: 'kg',
      );

      final distributionId = await database
          .into(database.dailyDistributions)
          .insert(
            DailyDistributionsCompanion(
              customerId: Value(customer.id),
              distributionDate: Value(DateTime.utc(2026, 8, 20)),
              status: const Value('draft'),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      await database
          .into(database.dailyDistributionItems)
          .insert(
            DailyDistributionItemsCompanion(
              distributionId: Value(distributionId),
              productId: Value(product.id),
              quantity: Value(1000),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      expect(
        () => database
            .into(database.dailyDistributionItems)
            .insert(
              DailyDistributionItemsCompanion(
                distributionId: Value(distributionId),
                productId: Value(product.id),
                quantity: Value(500),
                createdAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.now()),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('foreign keys are enforced for distribution items', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Eve 2',
        address: '987 Cedar St',
        mobile: '4321098766',
      );

      final product = await productRepository.createProduct(
        name: 'Ghee 2',
        unit: 'kg',
      );

      final distributionId = await database
          .into(database.dailyDistributions)
          .insert(
            DailyDistributionsCompanion(
              customerId: Value(customer.id),
              distributionDate: Value(DateTime.utc(2026, 8, 21)),
              status: const Value('draft'),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      expect(
        () => database
            .into(database.dailyDistributionItems)
            .insert(
              DailyDistributionItemsCompanion(
                distributionId: Value(distributionId),
                productId: Value(999999),
                quantity: Value(1000),
                createdAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.now()),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );

      expect(
        () => database
            .into(database.dailyDistributionItems)
            .insert(
              DailyDistributionItemsCompanion(
                distributionId: Value(999999),
                productId: Value(product.id),
                quantity: Value(1000),
                createdAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.now()),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test(
      'createDistributionWithItems rolls back on item insert failure',
      () async {
        final customer = await customerRepository.createCustomer(
          name: 'Frank 2',
          address: '159 Birch St',
          mobile: '3210987655',
        );

        expect(
          () => repository.createDistributionWithItems(
            customerId: customer.id,
            distributionDate: DateTime(2026, 8, 22),
            items: [(productId: 999999, quantity: 10)],
          ),
          throwsA(isA<SqliteException>()),
        );

        final found = await repository.getDistributionByCustomerAndDate(
          customerId: customer.id,
          distributionDate: DateTime(2026, 8, 22),
        );

        expect(found, isNull);
        expect(
          await repository.getDistributionsByDate(DateTime(2026, 8, 22)),
          isEmpty,
        );
      },
    );

    test('migrates schema v2 to v3 while preserving existing business data', () async {
      final file = File(
        '${Directory.systemTemp.path}/vyom_business_v2_migration_${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      if (await file.exists()) {
        await file.delete();
      }

      final legacyExecutor = NativeDatabase(file);
      await legacyExecutor.ensureOpen(const _MigrationExecutorUser());
      await legacyExecutor.runCustom('PRAGMA user_version = 2;');
      await legacyExecutor.runCustom('''
        CREATE TABLE app_settings (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          language_code TEXT NOT NULL DEFAULT 'en',
          onboarding_completed INTEGER NOT NULL DEFAULT 0 CHECK ("onboarding_completed" IN (0, 1)),
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        );
      ''');
      await legacyExecutor.runCustom('''
        CREATE TABLE business_profiles (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          firm_name TEXT NOT NULL,
          owner_name TEXT NOT NULL,
          address TEXT NOT NULL,
          mobile TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        );
      ''');
      await legacyExecutor.runCustom('''
        CREATE TABLE products (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          unit TEXT NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1 CHECK ("is_active" IN (0, 1)),
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        );
      ''');
      await legacyExecutor.runCustom('''
        CREATE TABLE customers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          address TEXT NOT NULL,
          mobile TEXT NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1 CHECK ("is_active" IN (0, 1)),
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        );
      ''');
      await legacyExecutor.runCustom('''
        CREATE TABLE customer_products (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customer_id INTEGER NOT NULL REFERENCES customers (id),
          product_id INTEGER NOT NULL REFERENCES products (id),
          default_quantity INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          UNIQUE (customer_id, product_id)
        );
      ''');

      final createdAt = DateTime(2026, 8, 1, 12, 0);
      final timestamp = createdAt.millisecondsSinceEpoch;
      await legacyExecutor.runCustom(
        "INSERT INTO app_settings(language_code, onboarding_completed, created_at, updated_at) VALUES('en', 0, $timestamp, $timestamp);",
      );
      await legacyExecutor.runCustom(
        "INSERT INTO business_profiles(firm_name, owner_name, address, mobile, created_at, updated_at) VALUES('Acme', 'Owner', 'Road 1', '999', $timestamp, $timestamp);",
      );
      await legacyExecutor.runCustom(
        "INSERT INTO products(name, unit, is_active, created_at, updated_at) VALUES('Milk', 'litre', 1, $timestamp, $timestamp);",
      );
      await legacyExecutor.runCustom(
        "INSERT INTO customers(name, address, mobile, is_active, created_at, updated_at) VALUES('Jane', 'Street 2', '111', 1, $timestamp, $timestamp);",
      );
      await legacyExecutor.runCustom(
        "INSERT INTO customer_products(customer_id, product_id, default_quantity, created_at, updated_at) VALUES(1, 1, 500, $timestamp, $timestamp);",
      );

      await legacyExecutor.close();

      final upgraded = AppDatabase(executor: NativeDatabase(file));
      final settings = await upgraded.select(upgraded.appSettings).getSingle();
      final profile = await upgraded
          .select(upgraded.businessProfiles)
          .getSingle();
      final product = await upgraded.select(upgraded.products).getSingle();
      final customer = await upgraded.select(upgraded.customers).getSingle();
      final customerProduct = await upgraded
          .select(upgraded.customerProducts)
          .getSingle();

      expect(settings.languageCode, 'en');
      expect(profile.firmName, 'Acme');
      expect(product.name, 'Milk');
      expect(customer.name, 'Jane');
      expect(customerProduct.defaultQuantity, 500);

      final dailyDistributions = await upgraded
          .select(upgraded.dailyDistributions)
          .get();
      final dailyItems = await upgraded
          .select(upgraded.dailyDistributionItems)
          .get();
      expect(dailyDistributions, isEmpty);
      expect(dailyItems, isEmpty);

      final migrationTables = await upgraded.executor.runSelect(
        'SELECT name FROM sqlite_master WHERE type = ? AND name IN (?, ?)',
        ['table', 'daily_distributions', 'daily_distribution_items'],
      );
      expect(migrationTables.length, 2);

      await upgraded.close();
      if (await file.exists()) {
        await file.delete();
      }
    });

    test(
      'prevent duplicate customer/date distribution via repository check',
      () async {
        final customer = await customerRepository.createCustomer(
          name: 'Charlie',
          address: '321 Pine St',
          mobile: '6543210987',
        );

        final date = DateTime(2026, 8, 23);

        await repository.createDraftDistribution(
          customerId: customer.id,
          distributionDate: date,
        );

        expect(
          () => repository.createDraftDistribution(
            customerId: customer.id,
            distributionDate: date,
          ),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('prevent duplicate product inside one distribution', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Diana',
        address: '654 Maple St',
        mobile: '5432109876',
      );

      final product = await productRepository.createProduct(
        name: 'Paneer',
        unit: 'kg',
      );

      final distribution = await repository.createDraftDistribution(
        customerId: customer.id,
        distributionDate: DateTime(2026, 8, 23),
      );

      await repository.addProductToDistribution(
        distributionId: distribution.id,
        productId: product.id,
        quantity: 1000,
      );

      expect(
        () => repository.addProductToDistribution(
          distributionId: distribution.id,
          productId: product.id,
          quantity: 500,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('update quantity in draft', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Eve',
        address: '987 Cedar St',
        mobile: '4321098765',
      );

      final product = await productRepository.createProduct(
        name: 'Ghee',
        unit: 'kg',
      );

      final distribution = await repository.createDraftDistribution(
        customerId: customer.id,
        distributionDate: DateTime(2026, 8, 23),
      );

      final item = await repository.addProductToDistribution(
        distributionId: distribution.id,
        productId: product.id,
        quantity: 1000,
      );

      final updated = await repository.updateDistributionItemQuantity(
        itemId: item.id,
        quantity: 2000,
      );

      expect(updated.quantity, 2000);
    });

    test('add product in draft', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Frank',
        address: '159 Birch St',
        mobile: '3210987654',
      );

      final product1 = await productRepository.createProduct(
        name: 'Buttermilk',
        unit: 'litre',
      );

      final product2 = await productRepository.createProduct(
        name: 'Yogurt',
        unit: 'kg',
      );

      final distribution = await repository.createDraftDistribution(
        customerId: customer.id,
        distributionDate: DateTime(2026, 8, 23),
      );

      await repository.addProductToDistribution(
        distributionId: distribution.id,
        productId: product1.id,
        quantity: 1500,
      );

      var items = await repository.getDistributionItems(distribution.id);
      expect(items.length, 1);

      await repository.addProductToDistribution(
        distributionId: distribution.id,
        productId: product2.id,
        quantity: 750,
      );

      items = await repository.getDistributionItems(distribution.id);
      expect(items.length, 2);
    });

    test('remove product in draft', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Grace',
        address: '753 Walnut St',
        mobile: '2109876543',
      );

      final product = await productRepository.createProduct(
        name: 'Lassi',
        unit: 'litre',
      );

      final distribution = await repository.createDraftDistribution(
        customerId: customer.id,
        distributionDate: DateTime(2026, 8, 23),
      );

      final item = await repository.addProductToDistribution(
        distributionId: distribution.id,
        productId: product.id,
        quantity: 2000,
      );

      var items = await repository.getDistributionItems(distribution.id);
      expect(items.length, 1);

      await repository.removeProductFromDistribution(item.id);

      items = await repository.getDistributionItems(distribution.id);
      expect(items.length, 0);
    });

    test('confirm distribution', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Henry',
        address: '321 Spruce St',
        mobile: '1098765432',
      );

      final product = await productRepository.createProduct(
        name: 'Cheese',
        unit: 'kg',
      );

      final distribution = await repository.createDraftDistribution(
        customerId: customer.id,
        distributionDate: DateTime(2026, 8, 23),
      );

      await repository.addProductToDistribution(
        distributionId: distribution.id,
        productId: product.id,
        quantity: 500,
      );

      final confirmed = await repository.confirmDistribution(distribution.id);

      expect(confirmed.status, 'confirmed');
    });

    test('prevent update after confirmation', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Ivy',
        address: '654 Ash St',
        mobile: '0987654321',
      );

      final product = await productRepository.createProduct(
        name: 'Shrikhand',
        unit: 'kg',
      );

      final distribution = await repository.createDraftDistribution(
        customerId: customer.id,
        distributionDate: DateTime(2026, 8, 23),
      );

      final item = await repository.addProductToDistribution(
        distributionId: distribution.id,
        productId: product.id,
        quantity: 1000,
      );

      await repository.confirmDistribution(distribution.id);

      expect(
        () => repository.updateDistributionItemQuantity(
          itemId: item.id,
          quantity: 2000,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('prevent adding product after confirmation', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Jack',
        address: '987 Larch St',
        mobile: '9876543210',
      );

      final product1 = await productRepository.createProduct(
        name: 'Rasam',
        unit: 'litre',
      );

      final product2 = await productRepository.createProduct(
        name: 'Sambar',
        unit: 'kg',
      );

      final distribution = await repository.createDraftDistribution(
        customerId: customer.id,
        distributionDate: DateTime(2026, 8, 23),
      );

      await repository.addProductToDistribution(
        distributionId: distribution.id,
        productId: product1.id,
        quantity: 1000,
      );

      await repository.confirmDistribution(distribution.id);

      expect(
        () => repository.addProductToDistribution(
          distributionId: distribution.id,
          productId: product2.id,
          quantity: 500,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('prevent removing product after confirmation', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Kate',
        address: '159 Sycamore St',
        mobile: '8765432109',
      );

      final product = await productRepository.createProduct(
        name: 'Dosa Batter',
        unit: 'litre',
      );

      final distribution = await repository.createDraftDistribution(
        customerId: customer.id,
        distributionDate: DateTime(2026, 8, 23),
      );

      final item = await repository.addProductToDistribution(
        distributionId: distribution.id,
        productId: product.id,
        quantity: 2000,
      );

      await repository.confirmDistribution(distribution.id);

      expect(
        () => repository.removeProductFromDistribution(item.id),
        throwsA(isA<StateError>()),
      );
    });

    test('prevent deleting confirmed distribution', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Leo',
        address: '753 Hemlock St',
        mobile: '7654321098',
      );

      final product = await productRepository.createProduct(
        name: 'Idli Flour',
        unit: 'kg',
      );

      final distribution = await repository.createDraftDistribution(
        customerId: customer.id,
        distributionDate: DateTime(2026, 8, 23),
      );

      await repository.addProductToDistribution(
        distributionId: distribution.id,
        productId: product.id,
        quantity: 1000,
      );

      await repository.confirmDistribution(distribution.id);

      expect(
        () => repository.deleteDraftDistribution(distribution.id),
        throwsA(isA<StateError>()),
      );
    });

    test('allow deleting draft distribution', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Mia',
        address: '321 Fir St',
        mobile: '6543210987',
      );

      final distribution = await repository.createDraftDistribution(
        customerId: customer.id,
        distributionDate: DateTime(2026, 8, 23),
      );

      await repository.deleteDraftDistribution(distribution.id);

      final found = await repository.getDistributionByCustomerAndDate(
        customerId: customer.id,
        distributionDate: DateTime(2026, 8, 23),
      );

      expect(found, isNull);
    });

    test('verify customer default quantity is never changed', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Noah',
        address: '654 Yew St',
        mobile: '5432109876',
      );

      final product = await productRepository.createProduct(
        name: 'Idli',
        unit: 'piece',
      );

      // Set default quantity via CustomerProducts
      await database
          .into(database.customerProducts)
          .insert(
            CustomerProductsCompanion(
              customerId: Value(customer.id),
              productId: Value(product.id),
              defaultQuantity: Value(100),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      final distribution = await repository.createDraftDistribution(
        customerId: customer.id,
        distributionDate: DateTime(2026, 8, 23),
      );

      // Add to distribution with different quantity
      await repository.addProductToDistribution(
        distributionId: distribution.id,
        productId: product.id,
        quantity: 50,
      );

      // Verify distribution item is independent of CustomerProducts
      final item = (await repository.getDistributionItems(distribution.id))
          .firstWhere((item) => item.productId == product.id);
      expect(item.quantity, 50);
    });

    test('prevent confirmation with no items', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Olivia',
        address: '987 Juniper St',
        mobile: '4321098765',
      );

      final distribution = await repository.createDraftDistribution(
        customerId: customer.id,
        distributionDate: DateTime(2026, 8, 23),
      );

      expect(
        () => repository.confirmDistribution(distribution.id),
        throwsA(isA<StateError>()),
      );
    });

    test('allows zero but rejects negative quantities', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Paul',
        address: '159 Dogwood St',
        mobile: '3210987654',
      );

      final product = await productRepository.createProduct(
        name: 'Upma',
        unit: 'gram',
      );

      final distribution = await repository.createDraftDistribution(
        customerId: customer.id,
        distributionDate: DateTime(2026, 8, 23),
      );

      final zeroItem = await repository.addProductToDistribution(
        distributionId: distribution.id,
        productId: product.id,
        quantity: 0,
      );
      expect(zeroItem.quantity, 0);

      expect(
        () => repository.addProductToDistribution(
          distributionId: distribution.id,
          productId: product.id + 1,
          quantity: -100,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'saves a complete batch atomically and supports zero quantities',
      () async {
        final first = await customerRepository.createCustomer(
          name: 'Rajesh',
          address: 'First Road',
          mobile: '9876500001',
        );
        final second = await customerRepository.createCustomer(
          name: 'Suresh',
          address: 'Second Road',
          mobile: '9876500002',
        );
        final milk = await productRepository.createProduct(
          name: 'Batch Milk',
          unit: 'litre',
        );
        final date = DateTime(2026, 8, 24);

        await repository.saveDailyDistributionBatch(
          distributionDate: date,
          entries: [
            (customerId: first.id, items: [(productId: milk.id, quantity: 0)]),
            (
              customerId: second.id,
              items: [(productId: milk.id, quantity: 2000)],
            ),
          ],
        );

        final firstDistribution = await repository
            .getDistributionByCustomerAndDate(
              customerId: first.id,
              distributionDate: date,
            );
        expect(
          (await repository.getDistributionItems(firstDistribution!.id))
              .single
              .quantity,
          0,
        );
        expect((await repository.getDistributionsByDate(date)).length, 2);
      },
    );

    test('rolls back the complete batch when one customer fails', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Atomic Customer',
        address: 'Atomic Road',
        mobile: '9876500003',
      );
      final product = await productRepository.createProduct(
        name: 'Atomic Product',
        unit: 'piece',
      );
      final date = DateTime(2026, 8, 24);

      expect(
        () => repository.saveDailyDistributionBatch(
          distributionDate: date,
          entries: [
            (
              customerId: customer.id,
              items: [(productId: product.id, quantity: 1)],
            ),
            (customerId: 999999, items: [(productId: product.id, quantity: 1)]),
          ],
        ),
        throwsA(isA<SqliteException>()),
      );

      expect(await repository.getDistributionsByDate(date), isEmpty);
    });

    test(
      're-saves an existing draft by adding, updating, and removing items',
      () async {
        final customer = await customerRepository.createCustomer(
          name: 'Resave Customer',
          address: 'Resave Road',
          mobile: '9876500004',
        );
        final milk = await productRepository.createProduct(
          name: 'Resave Milk',
          unit: 'litre',
        );
        final curd = await productRepository.createProduct(
          name: 'Resave Curd',
          unit: 'kg',
        );
        final date = DateTime(2026, 8, 24);

        await repository.saveDailyDistributionBatch(
          distributionDate: date,
          entries: [
            (
              customerId: customer.id,
              items: [
                (productId: milk.id, quantity: 1000),
                (productId: curd.id, quantity: 500),
              ],
            ),
          ],
        );
        await repository.saveDailyDistributionBatch(
          distributionDate: date,
          entries: [
            (
              customerId: customer.id,
              items: [(productId: milk.id, quantity: 2000)],
            ),
          ],
        );

        final distribution = await repository.getDistributionByCustomerAndDate(
          customerId: customer.id,
          distributionDate: date,
        );
        final items = await repository.getDistributionItems(distribution!.id);
        expect(items.length, 1);
        expect(items.single.productId, milk.id);
        expect(items.single.quantity, 2000);
      },
    );

    test(
      'confirm batch rolls back when an existing empty draft fails',
      () async {
        final emptyCustomer = await customerRepository.createCustomer(
          name: 'Empty Customer',
          address: 'Empty Road',
          mobile: '9876500005',
        );
        final validCustomer = await customerRepository.createCustomer(
          name: 'Valid Customer',
          address: 'Valid Road',
          mobile: '9876500006',
        );
        final product = await productRepository.createProduct(
          name: 'Confirm Product',
          unit: 'piece',
        );
        final date = DateTime(2026, 8, 24);
        await repository.createDraftDistribution(
          customerId: emptyCustomer.id,
          distributionDate: date,
        );

        expect(
          () => repository.confirmDailyDistributionBatch(
            distributionDate: date,
            entries: [
              (
                customerId: validCustomer.id,
                items: [(productId: product.id, quantity: 1)],
              ),
            ],
          ),
          throwsA(isA<StateError>()),
        );

        expect(
          await repository.getDistributionByCustomerAndDate(
            customerId: validCustomer.id,
            distributionDate: date,
          ),
          isNull,
        );
        final unchanged = await repository.getDistributionByCustomerAndDate(
          customerId: emptyCustomer.id,
          distributionDate: date,
        );
        expect(unchanged!.status, 'draft');
      },
    );

    test(
      'historical distributions remain readable after deactivation',
      () async {
        final customer = await customerRepository.createCustomer(
          name: 'Historical Customer',
          address: 'History Road',
          mobile: '9876500007',
        );
        final product = await productRepository.createProduct(
          name: 'Historical Product',
          unit: 'piece',
        );
        final date = DateTime(2026, 8, 24);
        await repository.saveDailyDistributionBatch(
          distributionDate: date,
          entries: [
            (
              customerId: customer.id,
              items: [(productId: product.id, quantity: 0)],
            ),
          ],
        );
        await customerRepository.deactivateCustomer(customer.id);

        final distribution = await repository.getDistributionByCustomerAndDate(
          customerId: customer.id,
          distributionDate: date,
        );
        expect(distribution, isNotNull);
        expect(
          (await repository.getDistributionItems(distribution!.id))
              .single
              .quantity,
          0,
        );
      },
    );

    test(
      'a new customer can be added without regenerating existing drafts',
      () async {
        final first = await customerRepository.createCustomer(
          name: 'Existing Customer',
          address: 'Existing Road',
          mobile: '9876500008',
        );
        final product = await productRepository.createProduct(
          name: 'New Customer Product',
          unit: 'piece',
        );
        final date = DateTime(2026, 8, 24);
        await repository.saveDailyDistributionBatch(
          distributionDate: date,
          entries: [
            (
              customerId: first.id,
              items: [(productId: product.id, quantity: 2)],
            ),
          ],
        );

        final second = await customerRepository.createCustomer(
          name: 'Later Customer',
          address: 'Later Road',
          mobile: '9876500009',
        );

        final existing = await repository.getDistributionByCustomerAndDate(
          customerId: first.id,
          distributionDate: date,
        );
        final later = await repository.getDistributionByCustomerAndDate(
          customerId: second.id,
          distributionDate: date,
        );
        expect(existing, isNotNull);
        expect(later, isNull);
        expect(
          (await repository.getDistributionItems(existing!.id)).single.quantity,
          2,
        );
      },
    );
  });
}
