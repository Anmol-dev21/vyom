import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class AppSettings extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get languageCode => text().withDefault(const Constant('en'))();

  BoolColumn get onboardingCompleted =>
      boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();
}

class BusinessProfiles extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get firmName => text()();

  TextColumn get ownerName => text()();

  TextColumn get address => text()();

  TextColumn get mobile => text()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();
}

class Products extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text()();

  TextColumn get unit => text()();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();
}

class Customers extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text()();

  TextColumn get address => text()();

  TextColumn get mobile => text()();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();
}

class CustomerProducts extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get customerId => integer().references(Customers, #id)();

  IntColumn get productId => integer().references(Products, #id)();

  IntColumn get defaultQuantity => integer()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {customerId, productId},
  ];
}

class DailyDistributions extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get customerId => integer().references(Customers, #id)();

  DateTimeColumn get distributionDate => dateTime()();

  TextColumn get status =>
      text().withDefault(const Constant('draft'))(); // 'draft' or 'confirmed'

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {customerId, distributionDate},
  ];
}

class DailyDistributionItems extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get distributionId =>
      integer().references(DailyDistributions, #id)();

  IntColumn get productId => integer().references(Products, #id)();

  IntColumn get quantity => integer()();

  /// Price per base unit in paise, snapshotted when confirmed.
  /// For a product measured in litres at ₹50/litre, this is 5000 (paise).
  /// NULL for draft distributions; populated on confirmation.
  IntColumn get unitPricePaise => integer().nullable()();

  /// Line amount in paise, snapshotted when confirmed.
  /// lineAmountPaise = quantity × unitPricePaise
  /// NULL for draft distributions; populated on confirmation.
  IntColumn get lineAmountPaise => integer().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {distributionId, productId},
  ];
}

/// Historical product pricing table.
/// Tracks price changes over time with non-overlapping effective periods.
/// Used to determine correct historical prices for charge calculations.
class ProductPrices extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get productId => integer().references(Products, #id)();

  /// Price per base unit in paise (₹50 = 5000 paise).
  /// For products, this is the price for 1 unit (1 litre, 1 kg, etc).
  IntColumn get pricePerBaseUnitPaise => integer()();

  /// Date when this price becomes effective.
  /// Normalized to UTC calendar day boundary.
  DateTimeColumn get effectiveFrom => dateTime()();

  /// Date when this price stops being effective (exclusive).
  /// NULL means this price is currently active (no end date).
  /// Normalized to UTC calendar day boundary.
  DateTimeColumn get effectiveTo => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {productId, effectiveFrom},
  ];
}

enum TransactionType { received, given }

enum PaymentMethod { cash, upi, bank }

class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get customerId => integer().references(Customers, #id)();

  DateTimeColumn get transactionDate => dateTime()();

  IntColumn get amount => integer()();

  TextColumn get transactionType => textEnum<TransactionType>()();

  TextColumn get paymentMethod => textEnum<PaymentMethod>()();

  TextColumn get note => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();
}

@DriftDatabase(
  tables: [
    AppSettings,
    BusinessProfiles,
    Products,
    Customers,
    CustomerProducts,
    DailyDistributions,
    DailyDistributionItems,
    Transactions,
    ProductPrices,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase({QueryExecutor? executor}) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_transactions_customer_date ON transactions (customer_id, transaction_date);',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_transactions_date ON transactions (transaction_date);',
      );
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(products);
        await m.createTable(customers);
        await m.createTable(customerProducts);
      }
      if (from < 3) {
        await m.createTable(dailyDistributions);
        await m.createTable(dailyDistributionItems);
      }
      if (from < 4) {
        await m.createTable(transactions);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_transactions_customer_date ON transactions (customer_id, transaction_date);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_transactions_date ON transactions (transaction_date);',
        );
      }
      if (from < 5) {
        // Add price snapshot fields to DailyDistributionItems (only if not already present)
        // When creating fresh databases, these columns are created as part of the table definition,
        // so we need to check before adding them.
        final columns = await customSelect(
          "PRAGMA table_info(daily_distribution_items)",
        ).get();
        final columnNames = columns
            .map((col) => col.read<String>('name'))
            .toSet();

        if (!columnNames.contains('unit_price_paise')) {
          await m.addColumn(
            dailyDistributionItems,
            dailyDistributionItems.unitPricePaise,
          );
        }

        if (!columnNames.contains('line_amount_paise')) {
          await m.addColumn(
            dailyDistributionItems,
            dailyDistributionItems.lineAmountPaise,
          );
        }

        // Create ProductPrices table
        await m.createTable(productPrices);
        // Create index for efficient price lookups
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_product_prices_product_effective ON product_prices (product_id, effective_from);',
        );
      }
    },
  );

  static QueryExecutor _openConnection() {
    return LazyDatabase(() async {
      late final Directory dbFolder;

      try {
        dbFolder = await getApplicationDocumentsDirectory();
      } on MissingPluginException {
        dbFolder = Directory.systemTemp;
      }

      final file = File(p.join(dbFolder.path, 'vyom_business.sqlite'));
      return NativeDatabase(file);
    });
  }
}
