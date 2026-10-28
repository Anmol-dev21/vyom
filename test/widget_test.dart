import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vyom_business/database/app_database.dart';
import 'package:vyom_business/database/database_providers.dart';
import 'package:vyom_business/features/onboarding/language_selection_screen.dart';
import 'package:vyom_business/features/reports/customer_ledger_detail_screen.dart';
import 'package:vyom_business/features/reports/customer_ledger_screen.dart';

void main() {
  testWidgets('shows language selection options', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LanguageSelectionScreen())),
    );

    expect(find.text('Welcome to VYOM'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('हिंदी'), findsOneWidget);
  });

  testWidgets('customer ledger screen shows the report heading', (
    WidgetTester tester,
  ) async {
    final database = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(() async {
      await database.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: CustomerLedgerScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Customer Ledger'), findsOneWidget);
    expect(find.text('Customer balances'), findsOneWidget);
  });

  testWidgets('customer ledger detail screen shows payment entries', (
    WidgetTester tester,
  ) async {
    final database = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(() async {
      await database.close();
    });

    await database
        .into(database.customers)
        .insert(
          CustomersCompanion(
            id: const Value(1),
            name: const Value('Amit Shah'),
            address: const Value('123 Main St'),
            mobile: const Value('1234567890'),
            isActive: const Value(true),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );

    await database
        .into(database.transactions)
        .insert(
          TransactionsCompanion(
            customerId: const Value(1),
            transactionDate: Value(DateTime.utc(2026, 8, 15)),
            amount: const Value(25000),
            transactionType: const Value(TransactionType.received),
            paymentMethod: const Value(PaymentMethod.cash),
            note: const Value('Advance'),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          home: CustomerLedgerDetailScreen(
            customerId: 1,
            customerName: 'Amit Shah',
            fromDate: DateTime.utc(2026, 8, 1),
            toDate: DateTime.utc(2026, 8, 31),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ledger entries'), findsOneWidget);
    expect(find.text('Payment received'), findsOneWidget);
    expect(find.text('Advance'), findsOneWidget);
  });
}
