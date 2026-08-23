import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';
import 'app_settings_repository.dart';
import 'business_profile_repository.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) => AppDatabase());

final appSettingsRepositoryProvider = Provider<AppSettingsRepository>(
  (ref) => AppSettingsRepository(ref.watch(appDatabaseProvider)),
);

final appSettingsProvider = FutureProvider<AppSetting?>((ref) async {
  final repository = ref.watch(appSettingsRepositoryProvider);
  return repository.getAppSettings();
});

final businessProfileRepositoryProvider = Provider<BusinessProfileRepository>(
  (ref) => BusinessProfileRepository(ref.watch(appDatabaseProvider)),
);

final businessProfileProvider = FutureProvider<BusinessProfile?>((ref) async {
  final repository = ref.watch(businessProfileRepositoryProvider);
  return repository.getBusinessProfile();
});
