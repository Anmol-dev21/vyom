import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vyom_business/database/app_database.dart';
import 'package:vyom_business/database/customer_product_repository.dart';
import 'package:vyom_business/database/customer_repository.dart';
import 'package:vyom_business/database/product_repository.dart';

void main() {
  late AppDatabase database;
  late ProductRepository productRepository;
  late CustomerRepository customerRepository;
  late CustomerProductRepository customerProductRepository;

  setUp(() {
    database = AppDatabase(executor: NativeDatabase.memory());
    productRepository = ProductRepository(database);
    customerRepository = CustomerRepository(database);
    customerProductRepository = CustomerProductRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('creates and reads products', () async {
    final created = await productRepository.createProduct(
      name: 'Milk',
      unit: 'litre',
    );

    final products = await productRepository.getActiveProducts();
    final product = await productRepository.getProductById(created.id);

    expect(products.length, 1);
    expect(product, isNotNull);
    expect(product?.name, 'Milk');
    expect(product?.unit, 'litre');
    expect(product?.isActive, isTrue);
  });

  test('prevents duplicate active products', () async {
    await productRepository.createProduct(name: 'Milk', unit: 'litre');

    expect(
      () => productRepository.createProduct(name: 'milk', unit: 'kg'),
      throwsA(isA<StateError>()),
    );
  });

  test('creates and reads customers', () async {
    final created = await customerRepository.createCustomer(
      name: 'Anil Verma',
      address: 'Main Market, Jaipur',
      mobile: '9876543210',
    );

    final customers = await customerRepository.getActiveCustomers();
    final customer = await customerRepository.getCustomerById(created.id);

    expect(customers.length, 1);
    expect(customer, isNotNull);
    expect(customer?.name, 'Anil Verma');
    expect(customer?.address, 'Main Market, Jaipur');
    expect(customer?.mobile, '9876543210');
    expect(customer?.isActive, isTrue);
  });

  test('creates a customer-product relationship', () async {
    final product = await productRepository.createProduct(
      name: 'Curd',
      unit: 'kg',
    );
    final customer = await customerRepository.createCustomer(
      name: 'Rita Sharma',
      address: 'Saket, Delhi',
      mobile: '9123456780',
    );

    final relationship = await customerProductRepository.addProductToCustomer(
      customerId: customer.id,
      productId: product.id,
      defaultQuantity: 2000,
    );

    final entries = await customerProductRepository.getProductsForCustomer(
      customer.id,
    );

    expect(relationship.defaultQuantity, 2000);
    expect(entries.length, 1);
    expect(entries.first.productId, product.id);
    expect(entries.first.defaultQuantity, 2000);
  });

  test('prevents duplicate customer-product assignments', () async {
    final product = await productRepository.createProduct(
      name: 'Paneer',
      unit: 'kg',
    );
    final customer = await customerRepository.createCustomer(
      name: 'Sanjay Gupta',
      address: 'Old City, Agra',
      mobile: '9988776655',
    );

    await customerProductRepository.addProductToCustomer(
      customerId: customer.id,
      productId: product.id,
      defaultQuantity: 1500,
    );

    expect(
      () => customerProductRepository.addProductToCustomer(
        customerId: customer.id,
        productId: product.id,
        defaultQuantity: 2000,
      ),
      throwsA(isA<StateError>()),
    );

    expect(
      () => database
          .into(database.customerProducts)
          .insert(
            CustomerProductsCompanion(
              customerId: Value(customer.id),
              productId: Value(product.id),
              defaultQuantity: Value(2000),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          ),
      throwsException,
    );
  });

  test('deactivates a product', () async {
    final product = await productRepository.createProduct(
      name: 'Ghee',
      unit: 'kg',
    );

    await productRepository.deactivateProduct(product.id);

    final activeProducts = await productRepository.getActiveProducts();
    final stored = await productRepository.getProductById(product.id);

    expect(activeProducts, isEmpty);
    expect(stored, isNotNull);
    expect(stored?.isActive, isFalse);
  });

  test('deactivates a customer', () async {
    final customer = await customerRepository.createCustomer(
      name: 'Kavita Singh',
      address: 'Sector 18, Mohali',
      mobile: '7777777777',
    );

    await customerRepository.deactivateCustomer(customer.id);

    final activeCustomers = await customerRepository.getActiveCustomers();
    final stored = await customerRepository.getCustomerById(customer.id);

    expect(activeCustomers, isEmpty);
    expect(stored, isNotNull);
    expect(stored?.isActive, isFalse);
  });
}
