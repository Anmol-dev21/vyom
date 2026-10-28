import 'package:flutter_test/flutter_test.dart';
import 'package:vyom_business/features/daily_distribution/daily_distribution_screen.dart';

void main() {
  group('DailyDistributionScreen helpers', () {
    test('preserves zero quantities when building a draft payload', () {
      final customers = [
        CustomerDistributionState(
          customerId: 1,
          customerName: 'Asha',
          quantities: {10: 0, 11: 1500, 12: 0},
        ),
        CustomerDistributionState(
          customerId: 2,
          customerName: 'Neha',
          quantities: {20: 250, 21: 0},
        ),
      ];

      final payload = DailyDistributionScreen.buildDraftPayload(customers);

      expect(payload.length, 2);
      expect(payload[0].customerId, 1);
      expect(payload[0].items, [
        (productId: 10, quantity: 0),
        (productId: 11, quantity: 1500),
        (productId: 12, quantity: 0),
      ]);
      expect(payload[1].items, [
        (productId: 20, quantity: 250),
        (productId: 21, quantity: 0),
      ]);
    });

    test('totals only positive delivery quantities', () {
      final customers = [
        CustomerDistributionState(
          customerId: 1,
          customerName: 'Asha',
          quantities: {10: 0, 11: 1500},
        ),
        CustomerDistributionState(
          customerId: 2,
          customerName: 'Neha',
          quantities: {20: 500, 21: 0},
        ),
      ];

      final total = DailyDistributionScreen.calculateDailyTotal(customers);

      expect(total, 2000);
    });

    test('groups totals by product ID', () {
      final customers = [
        CustomerDistributionState(
          customerId: 1,
          customerName: 'Asha',
          quantities: {10: 100, 11: 200},
        ),
        CustomerDistributionState(
          customerId: 2,
          customerName: 'Neha',
          quantities: {10: 300, 12: 400},
        ),
      ];

      expect(DailyDistributionScreen.calculateDailyTotals(customers), {
        10: 400,
        11: 200,
        12: 400,
      });
    });

    test('requires every persisted customer distribution to be confirmed', () {
      final confirmedCustomer = CustomerDistributionState(
        customerId: 1,
        customerName: 'Asha',
        quantities: {10: 100},
        status: 'confirmed',
      );
      final draftCustomer = CustomerDistributionState(
        customerId: 2,
        customerName: 'Neha',
        quantities: {10: 100},
        status: 'draft',
      );

      expect(
        DailyDistributionScreen.isDateConfirmed([confirmedCustomer]),
        isTrue,
      );
      expect(
        DailyDistributionScreen.isDateConfirmed([
          confirmedCustomer,
          draftCustomer,
        ]),
        isFalse,
      );
      expect(
        DailyDistributionScreen.isDateConfirmed([
          confirmedCustomer,
          const CustomerDistributionState(
            customerId: 3,
            customerName: 'New Customer',
            quantities: {},
            status: 'none',
          ),
        ]),
        isTrue,
      );
      expect(DailyDistributionScreen.isDateConfirmed([]), isFalse);
      expect(
        DailyDistributionScreen.isDateConfirmed([
          const CustomerDistributionState(
            customerId: 10,
            customerName: 'No persisted records',
            quantities: {},
            status: 'none',
          ),
        ]),
        isFalse,
      );
    });
  });
}
