import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vyom_business/database/app_database.dart';
import 'package:vyom_business/database/business_profile_repository.dart';

void main() {
  late AppDatabase database;
  late BusinessProfileRepository repository;

  setUp(() {
    database = AppDatabase(executor: NativeDatabase.memory());
    repository = BusinessProfileRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('creates a business profile', () async {
    await repository.saveBusinessProfile(
      firmName: 'Vyom Traders',
      ownerName: 'Rajesh Kumar',
      address: 'Main Market, Jaipur',
      mobile: '9876543210',
    );

    final profile = await repository.getBusinessProfile();

    expect(profile, isNotNull);
    expect(profile?.firmName, 'Vyom Traders');
    expect(profile?.ownerName, 'Rajesh Kumar');
    expect(profile?.mobile, '9876543210');
  });

  test('reads the business profile', () async {
    await repository.saveBusinessProfile(
      firmName: 'Milk House',
      ownerName: 'Anil Verma',
      address: 'Sector 12, Delhi',
      mobile: '9123456780',
    );

    final profile = await repository.getBusinessProfile();

    expect(profile, isNotNull);
    expect(profile?.firmName, 'Milk House');
  });

  test('updates the business profile', () async {
    await repository.saveBusinessProfile(
      firmName: 'Original Dairy',
      ownerName: 'Suresh Sharma',
      address: 'Old City, Agra',
      mobile: '9988776655',
    );

    await repository.updateBusinessProfile(
      firmName: 'Updated Dairy',
      ownerName: 'Suresh Sharma',
      address: 'New City, Agra',
      mobile: '8877665544',
    );

    final profile = await repository.getBusinessProfile();

    expect(profile, isNotNull);
    expect(profile?.firmName, 'Updated Dairy');
    expect(profile?.address, 'New City, Agra');
    expect(profile?.mobile, '8877665544');
  });

  test('prevents multiple business profile records', () async {
    await repository.saveBusinessProfile(
      firmName: 'First Firm',
      ownerName: 'Owner One',
      address: 'Address One',
      mobile: '1111111111',
    );

    await repository.saveBusinessProfile(
      firmName: 'Second Firm',
      ownerName: 'Owner Two',
      address: 'Address Two',
      mobile: '2222222222',
    );

    final profiles = await database.select(database.businessProfiles).get();

    expect(profiles.length, 1);
    expect(profiles.first.firmName, 'Second Firm');
  });
}
