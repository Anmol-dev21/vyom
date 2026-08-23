import 'package:drift/drift.dart';

import 'app_database.dart';

class BusinessProfileRepository {
  BusinessProfileRepository(this._db);

  final AppDatabase _db;

  Future<BusinessProfile?> getBusinessProfile() async {
    final profile = await (_db.select(
      _db.businessProfiles,
    )..orderBy([(tbl) => OrderingTerm.desc(tbl.id)])).getSingleOrNull();

    return profile;
  }

  Future<void> saveBusinessProfile({
    required String firmName,
    required String ownerName,
    required String address,
    required String mobile,
  }) async {
    final existing = await getBusinessProfile();

    if (existing != null) {
      await updateBusinessProfile(
        firmName: firmName,
        ownerName: ownerName,
        address: address,
        mobile: mobile,
      );
      return;
    }

    await _db
        .into(_db.businessProfiles)
        .insert(
          BusinessProfilesCompanion(
            firmName: Value(firmName),
            ownerName: Value(ownerName),
            address: Value(address),
            mobile: Value(mobile),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> updateBusinessProfile({
    required String firmName,
    required String ownerName,
    required String address,
    required String mobile,
  }) async {
    final existing = await getBusinessProfile();

    if (existing == null) {
      throw StateError('Business profile does not exist.');
    }

    await (_db.update(
      _db.businessProfiles,
    )..where((tbl) => tbl.id.equals(existing.id))).write(
      BusinessProfilesCompanion(
        firmName: Value(firmName),
        ownerName: Value(ownerName),
        address: Value(address),
        mobile: Value(mobile),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
