import 'package:drift/drift.dart';

import 'app_database.dart';

class AppSettingsRepository {
  AppSettingsRepository(this._db);

  final AppDatabase _db;

  Future<AppSetting?> getAppSettings() async {
    final settings = await (_db.select(
      _db.appSettings,
    )..orderBy([(tbl) => OrderingTerm.desc(tbl.id)])).getSingleOrNull();

    return settings;
  }

  Future<void> saveLanguage(String languageCode) async {
    final existing = await getAppSettings();

    if (existing == null) {
      await _db
          .into(_db.appSettings)
          .insert(
            AppSettingsCompanion(
              languageCode: Value(languageCode),
              onboardingCompleted: const Value(true),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );
      return;
    }

    await (_db.update(
      _db.appSettings,
    )..where((tbl) => tbl.id.equals(existing.id))).write(
      AppSettingsCompanion(
        languageCode: Value(languageCode),
        onboardingCompleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> markOnboardingCompleted() async {
    final existing = await getAppSettings();

    if (existing == null) {
      await _db
          .into(_db.appSettings)
          .insert(
            AppSettingsCompanion(
              onboardingCompleted: const Value(true),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );
      return;
    }

    await (_db.update(
      _db.appSettings,
    )..where((tbl) => tbl.id.equals(existing.id))).write(
      AppSettingsCompanion(
        onboardingCompleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
