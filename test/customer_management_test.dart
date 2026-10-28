import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vyom_business/database/app_database.dart';
import 'package:vyom_business/database/customer_product_repository.dart';
import 'package:vyom_business/database/customer_repository.dart';
import 'package:vyom_business/database/database_providers.dart';
import 'package:vyom_business/database/product_repository.dart';
import 'package:vyom_business/features/customers/customer_list_screen.dart';

void main() {
  test('creating a customer through the repository', () async {
    final database = AppDatabase(executor: NativeDatabase.memory());
    final repository = CustomerRepository(database);

    final customer = await repository.createCustomer(
      name: 'John Doe',
      address: '123 Main Street',
      mobile: '9876543210',
    );

    expect(customer.name, 'John Doe');
    expect(customer.address, '123 Main Street');
    expect(customer.mobile, '9876543210');
    expect(customer.isActive, true);

    await database.close();
  });

  test('adding default products to a customer', () async {
    final database = AppDatabase(executor: NativeDatabase.memory());
    final productRepository = ProductRepository(database);
    final customerRepository = CustomerRepository(database);
    final cpRepository = CustomerProductRepository(database);

    final product = await productRepository.createProduct(
      name: 'Milk',
      unit: 'litre',
    );

    final customer = await customerRepository.createCustomer(
      name: 'Jane Doe',
      address: '456 Oak Avenue',
      mobile: '9123456789',
    );

    final assignment = await cpRepository.addProductToCustomer(
      customerId: customer.id,
      productId: product.id,
      defaultQuantity: 2000,
    );

    expect(assignment.customerId, customer.id);
    expect(assignment.productId, product.id);
    expect(assignment.defaultQuantity, 2000);

    final assignments = await cpRepository.getProductsForCustomer(customer.id);
    expect(assignments.length, 1);
    expect(assignments.first.defaultQuantity, 2000);

    await database.close();
  });

  test('updating customer information', () async {
    final database = AppDatabase(executor: NativeDatabase.memory());
    final repository = CustomerRepository(database);

    final customer = await repository.createCustomer(
      name: 'John Doe',
      address: '123 Main Street',
      mobile: '9876543210',
    );

    final updated = await repository.updateCustomer(
      id: customer.id,
      name: 'John Smith',
      address: '789 Elm Street',
      mobile: '8765432109',
    );

    expect(updated.name, 'John Smith');
    expect(updated.address, '789 Elm Street');
    expect(updated.mobile, '8765432109');

    await database.close();
  });

  test('updating a customer\'s assigned products', () async {
    final database = AppDatabase(executor: NativeDatabase.memory());
    final productRepository = ProductRepository(database);
    final customerRepository = CustomerRepository(database);
    final cpRepository = CustomerProductRepository(database);

    final milk = await productRepository.createProduct(
      name: 'Milk',
      unit: 'litre',
    );

    final curd = await productRepository.createProduct(
      name: 'Curd',
      unit: 'kg',
    );

    final customer = await customerRepository.createCustomer(
      name: 'Jane Doe',
      address: '456 Oak Avenue',
      mobile: '9123456789',
    );

    final assignment1 = await cpRepository.addProductToCustomer(
      customerId: customer.id,
      productId: milk.id,
      defaultQuantity: 2000,
    );

    var assignments = await cpRepository.getProductsForCustomer(customer.id);
    expect(assignments.length, 1);

    final assignment2 = await cpRepository.addProductToCustomer(
      customerId: customer.id,
      productId: curd.id,
      defaultQuantity: 500,
    );

    assignments = await cpRepository.getProductsForCustomer(customer.id);
    expect(assignments.length, 2);

    await cpRepository.updateCustomerProduct(
      id: assignment1.id,
      defaultQuantity: 3000,
    );

    assignments = await cpRepository.getProductsForCustomer(customer.id);
    final updated = assignments.firstWhere((a) => a.id == assignment1.id);
    expect(updated.defaultQuantity, 3000);

    await cpRepository.removeProductFromCustomer(assignment2.id);

    assignments = await cpRepository.getProductsForCustomer(customer.id);
    expect(assignments.length, 1);

    await database.close();
  });

  test('preventing duplicate product assignments', () async {
    final database = AppDatabase(executor: NativeDatabase.memory());
    final productRepository = ProductRepository(database);
    final customerRepository = CustomerRepository(database);
    final cpRepository = CustomerProductRepository(database);

    final product = await productRepository.createProduct(
      name: 'Paneer',
      unit: 'kg',
    );

    final customer = await customerRepository.createCustomer(
      name: 'John Doe',
      address: '123 Main Street',
      mobile: '9876543210',
    );

    await cpRepository.addProductToCustomer(
      customerId: customer.id,
      productId: product.id,
      defaultQuantity: 1000,
    );

    expect(
      () => cpRepository.addProductToCustomer(
        customerId: customer.id,
        productId: product.id,
        defaultQuantity: 500,
      ),
      throwsA(isA<StateError>()),
    );

    await database.close();
  });

  test('deactivating a customer', () async {
    final database = AppDatabase(executor: NativeDatabase.memory());
    final repository = CustomerRepository(database);

    final customer = await repository.createCustomer(
      name: 'John Doe',
      address: '123 Main Street',
      mobile: '9876543210',
    );

    expect(customer.isActive, true);

    await repository.deactivateCustomer(customer.id);

    final deactivated = await repository.getCustomerById(customer.id);
    expect(deactivated?.isActive, false);

    final activeCustomers = await repository.getActiveCustomers();
    expect(activeCustomers.any((c) => c.id == customer.id), false);

    await database.close();
  });

  testWidgets('customer list displays active customers', (tester) async {
    final database = AppDatabase(executor: NativeDatabase.memory());
    final repository = CustomerRepository(database);

    await repository.createCustomer(
      name: 'Alice',
      address: '111 First Street',
      mobile: '1111111111',
    );

    await repository.createCustomer(
      name: 'Bob',
      address: '222 Second Avenue',
      mobile: '2222222222',
    );

    addTearDown(() async {
      await database.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [customerRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: CustomerListScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
  });
}
