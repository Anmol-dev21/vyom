import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/business_setup/business_setup_screen.dart';
import '../features/customers/customer_list_screen.dart';
import '../features/daily_distribution/daily_distribution_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/onboarding/language_selection_screen.dart';
import '../features/onboarding/splash_screen.dart';
import '../features/products/product_list_screen.dart';
import '../features/reports/customer_ledger_detail_screen.dart';
import '../features/reports/customer_ledger_screen.dart';
import '../features/transactions/transaction_list_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/language',
        builder: (context, state) => const LanguageSelectionScreen(),
      ),
      GoRoute(
        path: '/business-setup',
        builder: (context, state) => const BusinessSetupScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/products',
        builder: (context, state) => const ProductListScreen(),
      ),
      GoRoute(
        path: '/customers',
        builder: (context, state) => const CustomerListScreen(),
      ),
      GoRoute(
        path: '/daily-update',
        builder: (context, state) => const DailyDistributionScreen(),
      ),
      GoRoute(
        path: '/transactions',
        builder: (context, state) => const TransactionListScreen(),
      ),
      GoRoute(
        path: '/reports',
        builder: (context, state) => const CustomerLedgerScreen(),
      ),
      GoRoute(
        path: '/reports/customer/:customerId',
        builder: (context, state) {
          final customerId =
              int.tryParse(state.pathParameters['customerId'] ?? '') ?? 0;
          final customerName = Uri.decodeComponent(
            state.uri.queryParameters['name'] ?? 'Customer',
          );
          final fromDate =
              DateTime.tryParse(state.uri.queryParameters['fromDate'] ?? '') ??
              DateTime.now();
          final toDate =
              DateTime.tryParse(state.uri.queryParameters['toDate'] ?? '') ??
              DateTime.now();

          return CustomerLedgerDetailScreen(
            customerId: customerId,
            customerName: customerName,
            fromDate: fromDate,
            toDate: toDate,
          );
        },
      ),
    ],
  );
});
