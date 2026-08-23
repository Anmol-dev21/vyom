import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vyom_business/database/app_database.dart';
import 'package:vyom_business/database/database_providers.dart';
import 'package:vyom_business/database/product_repository.dart';
import 'package:vyom_business/features/products/product_list_screen.dart';

void main() {
  test(
    'product list data can load through the repository/provider layer',
    () async {
      final database = AppDatabase(executor: NativeDatabase.memory());
      final repository = ProductRepository(database);

      await repository.createProduct(name: 'Milk', unit: 'litre');
      final products = await repository.getActiveProducts();

      expect(products.length, 1);
      expect(products.first.name, 'Milk');
      expect(products.first.unit, 'litre');

      await database.close();
    },
  );

  testWidgets('creating a product refreshes list data', (tester) async {
    final database = AppDatabase(executor: NativeDatabase.memory());
    final repository = ProductRepository(database);

    addTearDown(() async {
      await database.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [productRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: ProductListScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('No active products yet'), findsOneWidget);

    await repository.createProduct(name: 'Curd', unit: 'kg');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProductListScreen)),
    );
    container.invalidate(productListProvider);
    await tester.pumpAndSettle();

    expect(find.text('Curd'), findsOneWidget);
    expect(find.text('kg'), findsOneWidget);
  });

  test('duplicate product errors are handled without crashing', () async {
    final database = AppDatabase(executor: NativeDatabase.memory());
    final repository = ProductRepository(database);

    await repository.createProduct(name: 'Paneer', unit: 'kg');

    expect(
      () => repository.createProduct(name: ' paneer ', unit: 'gram'),
      throwsA(isA<StateError>()),
    );

    await database.close();
  });
}
