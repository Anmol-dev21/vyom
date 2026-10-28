import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vyom_business/database/app_database.dart';
import 'package:vyom_business/database/customer_repository.dart';
import 'package:vyom_business/database/transaction_repository.dart';

void main() {
  group('TransactionRepository', () {
    late AppDatabase database;
    late CustomerRepository customerRepository;
    late TransactionRepository transactionRepository;

    setUp(() async {
      database = AppDatabase(executor: NativeDatabase.memory());
      customerRepository = CustomerRepository(database);
      transactionRepository = TransactionRepository(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('create received cash transaction', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Rajesh',
        address: 'Road 1',
        mobile: '9876543210',
      );

      final tx = await transactionRepository.createTransaction(
        customerId: customer.id,
        transactionDate: DateTime(2026, 8, 29, 9, 15),
        transactionType: TransactionType.received,
        paymentMethod: PaymentMethod.cash,
        amountInPaise: 200000,
        note: 'Today Rajesh gave ₹2000 by UPI',
      );

      expect(tx.customerId, customer.id);
      expect(tx.transactionType, TransactionType.received);
      expect(tx.paymentMethod, PaymentMethod.cash);
      expect(tx.amountInPaise, 200000);
    });

    test('create received UPI transaction', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Ramesh',
        address: 'Road 2',
        mobile: '9876543211',
      );

      final tx = await transactionRepository.createTransaction(
        customerId: customer.id,
        transactionDate: DateTime(2026, 8, 29, 18, 30),
        transactionType: TransactionType.received,
        paymentMethod: PaymentMethod.upi,
        amountInPaise: 50000,
      );

      expect(tx.paymentMethod, PaymentMethod.upi);
      expect(tx.amountInPaise, 50000);
    });

    test('create received bank transaction', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Shital',
        address: 'Road 3',
        mobile: '9876543212',
      );

      final tx = await transactionRepository.createTransaction(
        customerId: customer.id,
        transactionDate: DateTime(2026, 8, 29),
        transactionType: TransactionType.received,
        paymentMethod: PaymentMethod.bank,
        amountInPaise: 100000,
      );

      expect(tx.paymentMethod, PaymentMethod.bank);
      expect(tx.amountInPaise, 100000);
    });

    test('create given transaction', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Nisha',
        address: 'Road 4',
        mobile: '9876543213',
      );

      final tx = await transactionRepository.createTransaction(
        customerId: customer.id,
        transactionDate: DateTime(2026, 8, 30),
        transactionType: TransactionType.given,
        paymentMethod: PaymentMethod.cash,
        amountInPaise: 75000,
      );

      expect(tx.transactionType, TransactionType.given);
      expect(tx.amountInPaise, 75000);
    });

    test('read transaction by ID', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Amit',
        address: 'Road 5',
        mobile: '9876543214',
      );

      final created = await transactionRepository.createTransaction(
        customerId: customer.id,
        transactionDate: DateTime(2026, 8, 29),
        transactionType: TransactionType.received,
        paymentMethod: PaymentMethod.cash,
        amountInPaise: 150000,
      );

      final found = await transactionRepository.getTransactionById(created.id);
      expect(found, isNotNull);
      expect(found!.id, created.id);
      expect(found.amountInPaise, 150000);
    });

    test('read customer transactions', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Bharat',
        address: 'Road 6',
        mobile: '9876543215',
      );

      await transactionRepository.createTransaction(
        customerId: customer.id,
        transactionDate: DateTime(2026, 8, 29),
        transactionType: TransactionType.received,
        paymentMethod: PaymentMethod.cash,
        amountInPaise: 10000,
      );
      await transactionRepository.createTransaction(
        customerId: customer.id,
        transactionDate: DateTime(2026, 8, 30),
        transactionType: TransactionType.given,
        paymentMethod: PaymentMethod.upi,
        amountInPaise: 5000,
      );

      final items = await transactionRepository.getTransactionsForCustomer(
        customer.id,
      );
      expect(items.length, 2);
    });

    test('read transactions by date', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Chetan',
        address: 'Road 7',
        mobile: '9876543216',
      );

      final date = DateTime(2026, 8, 29);
      await transactionRepository.createTransaction(
        customerId: customer.id,
        transactionDate: date,
        transactionType: TransactionType.received,
        paymentMethod: PaymentMethod.cash,
        amountInPaise: 10000,
      );
      await transactionRepository.createTransaction(
        customerId: customer.id,
        transactionDate: date.add(const Duration(hours: 12)),
        transactionType: TransactionType.received,
        paymentMethod: PaymentMethod.bank,
        amountInPaise: 20000,
      );

      final items = await transactionRepository.getTransactionsByDate(date);
      expect(items.length, 2);
    });

    test('read transactions between dates', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Dinesh',
        address: 'Road 8',
        mobile: '9876543217',
      );

      await transactionRepository.createTransaction(
        customerId: customer.id,
        transactionDate: DateTime(2026, 8, 28),
        transactionType: TransactionType.received,
        paymentMethod: PaymentMethod.cash,
        amountInPaise: 10000,
      );
      await transactionRepository.createTransaction(
        customerId: customer.id,
        transactionDate: DateTime(2026, 8, 29),
        transactionType: TransactionType.received,
        paymentMethod: PaymentMethod.bank,
        amountInPaise: 20000,
      );
      await transactionRepository.createTransaction(
        customerId: customer.id,
        transactionDate: DateTime(2026, 8, 30),
        transactionType: TransactionType.given,
        paymentMethod: PaymentMethod.cash,
        amountInPaise: 30000,
      );

      final items = await transactionRepository.getTransactionsBetweenDates(
        DateTime(2026, 8, 29),
        DateTime(2026, 8, 30),
      );
      expect(items.length, 2);
    });

    test('update transaction', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Esha',
        address: 'Road 9',
        mobile: '9876543218',
      );

      final created = await transactionRepository.createTransaction(
        customerId: customer.id,
        transactionDate: DateTime(2026, 8, 29),
        transactionType: TransactionType.received,
        paymentMethod: PaymentMethod.cash,
        amountInPaise: 10000,
        note: 'old note',
      );

      final updated = await transactionRepository.updateTransaction(
        id: created.id,
        customerId: customer.id,
        transactionDate: DateTime(2026, 8, 30),
        transactionType: TransactionType.received,
        paymentMethod: PaymentMethod.upi,
        amountInPaise: 25000,
        note: 'updated note',
      );

      expect(updated.amountInPaise, 25000);
      expect(updated.paymentMethod, PaymentMethod.upi);
      expect(updated.note, 'updated note');
    });

    test('delete/correction behavior', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Farah',
        address: 'Road 10',
        mobile: '9876543219',
      );

      final tx = await transactionRepository.createTransaction(
        customerId: customer.id,
        transactionDate: DateTime(2026, 8, 29),
        transactionType: TransactionType.received,
        paymentMethod: PaymentMethod.cash,
        amountInPaise: 10000,
      );

      await transactionRepository.deleteTransaction(tx.id);
      final found = await transactionRepository.getTransactionById(tx.id);
      expect(found, isNull);
    });

    test('reject zero amount', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Gaurav',
        address: 'Road 11',
        mobile: '9876543220',
      );

      expect(
        () => transactionRepository.createTransaction(
          customerId: customer.id,
          transactionDate: DateTime(2026, 8, 29),
          transactionType: TransactionType.received,
          paymentMethod: PaymentMethod.cash,
          amountInPaise: 0,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('reject negative amount', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Hina',
        address: 'Road 12',
        mobile: '9876543221',
      );

      expect(
        () => transactionRepository.createTransaction(
          customerId: customer.id,
          transactionDate: DateTime(2026, 8, 29),
          transactionType: TransactionType.received,
          paymentMethod: PaymentMethod.cash,
          amountInPaise: -100,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('reject invalid decimal precision', () async {
      expect(
        () => TransactionRepository.parseRupeesToPaise('100.123'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => TransactionRepository.parseRupeesToPaise('100.1234'),
        throwsA(isA<FormatException>()),
      );
    });

    test('accept valid paise amount', () async {
      expect(TransactionRepository.parseRupeesToPaise('100'), 10000);
      expect(TransactionRepository.parseRupeesToPaise('100.50'), 10050);
      expect(TransactionRepository.parseRupeesToPaise('0.01'), 1);
    });

    test('reject nonexistent customer', () async {
      expect(
        () => transactionRepository.createTransaction(
          customerId: 999999,
          transactionDate: DateTime(2026, 8, 29),
          transactionType: TransactionType.received,
          paymentMethod: PaymentMethod.cash,
          amountInPaise: 10000,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('verify foreign-key enforcement', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Isha',
        address: 'Road 13',
        mobile: '9876543222',
      );

      final id = await database
          .into(database.transactions)
          .insert(
            TransactionsCompanion(
              customerId: Value(customer.id),
              transactionDate: Value(DateTime.utc(2026, 8, 29)),
              amount: const Value(10000),
              transactionType: const Value(TransactionType.received),
              paymentMethod: const Value(PaymentMethod.cash),
              note: const Value('note'),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      expect(id, greaterThan(0));

      expect(
        () => database
            .into(database.transactions)
            .insert(
              TransactionsCompanion(
                customerId: const Value(999999),
                transactionDate: Value(DateTime.utc(2026, 8, 29)),
                amount: const Value(10000),
                transactionType: const Value(TransactionType.received),
                paymentMethod: const Value(PaymentMethod.cash),
                note: const Value('note'),
                createdAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.now()),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('verify date normalization', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Jatin',
        address: 'Road 14',
        mobile: '9876543223',
      );

      final tx = await transactionRepository.createTransaction(
        customerId: customer.id,
        transactionDate: DateTime(2026, 8, 29, 9, 0),
        transactionType: TransactionType.received,
        paymentMethod: PaymentMethod.cash,
        amountInPaise: 15000,
      );

      expect(tx.transactionDate.year, 2026);
      expect(tx.transactionDate.month, 8);
      expect(tx.transactionDate.day, 29);

      final byDate = await transactionRepository.getTransactionsByDate(
        DateTime(2026, 8, 29, 18, 30),
      );
      expect(byDate.single.id, tx.id);
    });

    test('verify money is stored as integer paise', () async {
      final customer = await customerRepository.createCustomer(
        name: 'Kavya',
        address: 'Road 15',
        mobile: '9876543224',
      );

      final tx = await transactionRepository.createTransaction(
        customerId: customer.id,
        transactionDate: DateTime(2026, 8, 29),
        transactionType: TransactionType.received,
        paymentMethod: PaymentMethod.cash,
        amountInPaise: 10050,
      );

      final row = await (database.select(
        database.transactions,
      )..where((tbl) => tbl.id.equals(tx.id))).getSingle();
      expect(row.amount, 10050);
      expect(row.amount.runtimeType, int);
    });

    test('verify migration v3 to v4 preserves existing data', () async {
      final file = File(
        '${Directory.systemTemp.path}/vyom_business_v3_migration_${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      if (await file.exists()) {
        await file.delete();
      }

      final legacyExecutor = NativeDatabase(file);
      await legacyExecutor.ensureOpen(const _MigrationExecutorUser());
      await legacyExecutor.runCustom('PRAGMA user_version = 3;');
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
      await legacyExecutor.runCustom('''
        CREATE TABLE daily_distributions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customer_id INTEGER NOT NULL REFERENCES customers (id),
          distribution_date INTEGER NOT NULL,
          status TEXT NOT NULL DEFAULT 'draft',
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          UNIQUE (customer_id, distribution_date)
        );
      ''');
      await legacyExecutor.runCustom('''
        CREATE TABLE daily_distribution_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          distribution_id INTEGER NOT NULL REFERENCES daily_distributions (id),
          product_id INTEGER NOT NULL REFERENCES products (id),
          quantity INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          UNIQUE (distribution_id, product_id)
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
      await legacyExecutor.runCustom(
        "INSERT INTO daily_distributions(customer_id, distribution_date, status, created_at, updated_at) VALUES(1, $timestamp, 'draft', $timestamp, $timestamp);",
      );
      await legacyExecutor.runCustom(
        "INSERT INTO daily_distribution_items(distribution_id, product_id, quantity, created_at, updated_at) VALUES(1, 1, 100, $timestamp, $timestamp);",
      );

      await legacyExecutor.close();

      final upgraded = AppDatabase(executor: NativeDatabase(file));
      final settings = await upgraded.select(upgraded.appSettings).getSingle();
      final product = await upgraded.select(upgraded.products).getSingle();
      final customer = await upgraded.select(upgraded.customers).getSingle();
      final distributionCount = await upgraded
          .select(upgraded.dailyDistributions)
          .get();
      final transactionCount = await upgraded
          .select(upgraded.transactions)
          .get();

      expect(settings.languageCode, 'en');
      expect(product.name, 'Milk');
      expect(customer.name, 'Jane');
      expect(distributionCount.length, 1);
      expect(transactionCount, isEmpty);

      await upgraded.close();
      if (await file.exists()) {
        await file.delete();
      }
    });

    test('verify fresh database creates transaction table', () async {
      final tableNames = database.allTables.map(
        (table) => table.actualTableName,
      );
      expect(tableNames, contains('transactions'));
    });
  });
}

class _MigrationExecutorUser implements QueryExecutorUser {
  const _MigrationExecutorUser();

  @override
  int get schemaVersion => 3;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}
