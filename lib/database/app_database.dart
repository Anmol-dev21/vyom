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

@DriftDatabase(
  tables: [
    AppSettings,
    BusinessProfiles,
    Products,
    Customers,
    CustomerProducts,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase({QueryExecutor? executor}) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(products);
        await m.createTable(customers);
        await m.createTable(customerProducts);
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
