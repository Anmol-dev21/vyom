import 'package:drift/drift.dart';

import 'app_database.dart';
import 'customer_ledger_summary.dart';

enum CustomerLedgerEntryType { debit, credit }

class CustomerLedgerEntry {
  const CustomerLedgerEntry({
    required this.customerId,
    required this.entryDate,
    required this.type,
    required this.amountPaise,
    required this.title,
    this.note,
    this.referenceId,
  });

  final int customerId;
  final DateTime entryDate;
  final CustomerLedgerEntryType type;
  final int amountPaise;
  final String title;
  final String? note;
  final int? referenceId;

  String get amountLabel => '₹${(amountPaise / 100).toStringAsFixed(2)}';
}

/// Service for calculating customer ledgers from persisted business records.
///
/// Ledger calculation rules:
/// - DR (debit): charges from confirmed daily distributions + given transactions
/// - CR (credit): money received from customers
/// - Balance = DR - CR (can be negative if customer has overpaid)
///
/// Only CONFIRMED daily distributions contribute to the finalized debit.
/// Draft distributions are ignored.
/// Zero quantities produce zero charges.
/// All calculations use integer paise; no floating-point arithmetic.
class CustomerLedgerService {
  CustomerLedgerService(this._db, [dynamic _]);

  final AppDatabase _db;

  /// Calculate ledger for a single customer within a date range.
  ///
  /// Throws StateError if fromDate > toDate.
  /// Returns a summary with debit, credit, and balance (all in paise).
  Future<CustomerLedgerSummary> calculateCustomerLedger({
    required int customerId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    // Validate date range
    if (fromDate.isAfter(toDate)) {
      throw StateError('fromDate must not be after toDate.');
    }

    // Normalize dates using the same strategy as the application
    final normalizedFrom = _normalizeBusinessDate(fromDate);
    final normalizedTo = _normalizeBusinessDate(toDate);

    // Load customer to get name; include deactivated customers for historical data
    final customer = await (_db.select(
      _db.customers,
    )..where((tbl) => tbl.id.equals(customerId))).getSingleOrNull();

    if (customer == null) {
      throw StateError('Customer not found.');
    }

    // Load confirmed daily distributions in date range
    final distributions =
        await (_db.select(_db.dailyDistributions)
              ..where((tbl) => tbl.customerId.equals(customerId))
              ..where(
                (tbl) => tbl.distributionDate.isBetweenValues(
                  normalizedFrom,
                  normalizedTo,
                ),
              )
              ..where((tbl) => tbl.status.equals('confirmed')))
            .get();

    // Calculate debit from confirmed distributions
    int debitFromDistributions = 0;
    if (distributions.isNotEmpty) {
      final distributionIds = distributions.map((d) => d.id).toList();
      debitFromDistributions = await _calculateDistributionCharges(
        distributionIds,
      );
    }

    // Load transactions in date range
    final transactions =
        await (_db.select(_db.transactions)
              ..where((tbl) => tbl.customerId.equals(customerId))
              ..where(
                (tbl) => tbl.transactionDate.isBetweenValues(
                  normalizedFrom,
                  normalizedTo,
                ),
              ))
            .get();

    // Separate transactions by type
    int creditFromReceived = 0;
    int debitFromGiven = 0;

    for (final transaction in transactions) {
      if (transaction.transactionType == TransactionType.received) {
        creditFromReceived += transaction.amount;
      } else if (transaction.transactionType == TransactionType.given) {
        debitFromGiven += transaction.amount;
      }
    }

    // Calculate totals
    final totalDebit = debitFromDistributions + debitFromGiven;
    final totalCredit = creditFromReceived;

    return CustomerLedgerSummary(
      customerId: customerId,
      customerName: customer.name,
      fromDate: normalizedFrom,
      toDate: normalizedTo,
      debitPaise: totalDebit,
      creditPaise: totalCredit,
    );
  }

  /// Calculate ledger summaries for all customers with activity in the date range.
  ///
  /// Returns a list sorted by customer ID.
  /// Includes deactivated customers if they have historical records.
  /// Throws StateError if fromDate > toDate.
  Future<List<CustomerLedgerSummary>> calculateAllCustomerLedgers({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    // Validate date range
    if (fromDate.isAfter(toDate)) {
      throw StateError('fromDate must not be after toDate.');
    }

    final normalizedFrom = _normalizeBusinessDate(fromDate);
    final normalizedTo = _normalizeBusinessDate(toDate);

    // Find all customers with activity (distributions or transactions) in the range
    final customerIds = <int>{};

    // Customers with distributions in range
    final distributionCustomers =
        await (_db.select(_db.dailyDistributions)
              ..where(
                (tbl) => tbl.distributionDate.isBetweenValues(
                  normalizedFrom,
                  normalizedTo,
                ),
              )
              ..where((tbl) => tbl.status.equals('confirmed')))
            .map((d) => d.customerId)
            .get();
    customerIds.addAll(distributionCustomers);

    // Customers with transactions in range
    final transactionCustomers =
        await (_db.select(_db.transactions)..where(
              (tbl) => tbl.transactionDate.isBetweenValues(
                normalizedFrom,
                normalizedTo,
              ),
            ))
            .map((t) => t.customerId)
            .get();
    customerIds.addAll(transactionCustomers);

    // Calculate ledger for each customer
    final ledgers = <CustomerLedgerSummary>[];
    for (final customerId in customerIds) {
      final summary = await calculateCustomerLedger(
        customerId: customerId,
        fromDate: normalizedFrom,
        toDate: normalizedTo,
      );
      ledgers.add(summary);
    }

    // Sort by customer ID for consistent ordering
    ledgers.sort((a, b) => a.customerId.compareTo(b.customerId));

    return ledgers;
  }

  /// Calculate detailed ledger entries for a single customer within a date range.
  ///
  /// Includes confirmed distribution charges and cash movement entries in chronological order.
  Future<List<CustomerLedgerEntry>> calculateCustomerLedgerEntries({
    required int customerId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    if (fromDate.isAfter(toDate)) {
      throw StateError('fromDate must not be after toDate.');
    }

    final normalizedFrom = _normalizeBusinessDate(fromDate);
    final normalizedTo = _normalizeBusinessDate(toDate);

    final customer = await (_db.select(
      _db.customers,
    )..where((tbl) => tbl.id.equals(customerId))).getSingleOrNull();
    if (customer == null) {
      throw StateError('Customer not found.');
    }

    final entries = <CustomerLedgerEntry>[];

    final distributions =
        await (_db.select(_db.dailyDistributions)
              ..where((tbl) => tbl.customerId.equals(customerId))
              ..where(
                (tbl) => tbl.distributionDate.isBetweenValues(
                  normalizedFrom,
                  normalizedTo,
                ),
              )
              ..where((tbl) => tbl.status.equals('confirmed')))
            .get();

    for (final distribution in distributions) {
      final items = await (_db.select(
        _db.dailyDistributionItems,
      )..where((tbl) => tbl.distributionId.equals(distribution.id))).get();

      for (final item in items) {
        final amountPaise = item.lineAmountPaise ?? 0;
        if (amountPaise == 0) {
          continue;
        }

        final product = await (_db.select(
          _db.products,
        )..where((tbl) => tbl.id.equals(item.productId))).getSingleOrNull();

        entries.add(
          CustomerLedgerEntry(
            customerId: customerId,
            entryDate: distribution.distributionDate,
            type: CustomerLedgerEntryType.debit,
            amountPaise: amountPaise,
            title: 'Distribution${product != null ? ' • ${product.name}' : ''}',
            note: 'Confirmed daily distribution',
            referenceId: distribution.id,
          ),
        );
      }
    }

    final transactions =
        await (_db.select(_db.transactions)
              ..where((tbl) => tbl.customerId.equals(customerId))
              ..where(
                (tbl) => tbl.transactionDate.isBetweenValues(
                  normalizedFrom,
                  normalizedTo,
                ),
              )
              ..orderBy([(tbl) => OrderingTerm.asc(tbl.transactionDate)]))
            .get();

    for (final transaction in transactions) {
      final type = transaction.transactionType == TransactionType.received
          ? CustomerLedgerEntryType.credit
          : CustomerLedgerEntryType.debit;
      final title = transaction.transactionType == TransactionType.received
          ? 'Payment received'
          : 'Payment given';

      entries.add(
        CustomerLedgerEntry(
          customerId: customerId,
          entryDate: transaction.transactionDate,
          type: type,
          amountPaise: transaction.amount,
          title: title,
          note: transaction.note,
          referenceId: transaction.id,
        ),
      );
    }

    entries.sort((a, b) {
      final dateCompare = a.entryDate.compareTo(b.entryDate);
      if (dateCompare != 0) {
        return dateCompare;
      }
      final typeOrder = a.type.index.compareTo(b.type.index);
      if (typeOrder != 0) {
        return typeOrder;
      }
      return a.amountPaise.compareTo(b.amountPaise);
    });

    return entries;
  }

  /// Calculate total charges from confirmed daily distributions.
  ///
  /// Uses the snapshot lineAmountPaise stored when distribution was confirmed.
  /// This ensures historical charges never change when current prices change.
  /// Zero quantities produce zero charges (lineAmountPaise = NULL initially).
  /// For confirmed distributions, lineAmountPaise must be populated.
  Future<int> _calculateDistributionCharges(List<int> distributionIds) async {
    if (distributionIds.isEmpty) {
      return 0;
    }

    // Load all items for these distributions
    final items = await (_db.select(
      _db.dailyDistributionItems,
    )..where((tbl) => tbl.distributionId.isIn(distributionIds))).get();

    if (items.isEmpty) {
      return 0;
    }

    // Sum the snapshot line amounts
    int totalCharge = 0;
    for (final item in items) {
      // For confirmed distributions, lineAmountPaise should always be populated
      // (either a real amount or 0 for zero-quantity items).
      // If null, it means the distribution was confirmed but items weren't snapshot properly.
      final lineAmount = item.lineAmountPaise ?? 0;
      totalCharge += lineAmount;
    }

    return totalCharge;
  }

  /// Normalize a date to UTC midnight (calendar day boundary).
  ///
  /// Matches the date normalization strategy used throughout the application.
  DateTime _normalizeBusinessDate(DateTime value) {
    return DateTime.utc(value.year, value.month, value.day);
  }
}
