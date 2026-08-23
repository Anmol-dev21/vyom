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

@DriftDatabase(tables: [AppSettings, BusinessProfiles])
class AppDatabase extends _$AppDatabase {
  AppDatabase({QueryExecutor? executor}) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

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
