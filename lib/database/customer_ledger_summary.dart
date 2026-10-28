/// Immutable ledger summary for a single customer.
///
/// All monetary values are stored in paise (integer).
/// Balance = debitPaise - creditPaise
///
/// A negative balance means the customer has paid more than the calculated debit.
class CustomerLedgerSummary {
  /// Create a customer ledger summary.
  const CustomerLedgerSummary({
    required this.customerId,
    required this.customerName,
    required this.fromDate,
    required this.toDate,
    required this.debitPaise,
    required this.creditPaise,
  });

  /// The customer ID.
  final int customerId;

  /// The customer's name for display purposes.
  final String customerName;

  /// Start of the ledger date range (inclusive).
  final DateTime fromDate;

  /// End of the ledger date range (inclusive).
  final DateTime toDate;

  /// Total debit in paise (charges from confirmed distributions + given transactions).
  final int debitPaise;

  /// Total credit in paise (received payments).
  final int creditPaise;

  /// Calculated balance in paise: debitPaise - creditPaise.
  ///
  /// Positive: customer owes the business.
  /// Negative: customer has overpaid.
  /// Zero: settled.
  int get balancePaise => debitPaise - creditPaise;

  /// Balance formatted as rupees string (without ₹ symbol).
  String get balanceRupees => _formatPaiseAsRupees(balancePaise);

  /// Debit formatted as rupees string (without ₹ symbol).
  String get debitRupees => _formatPaiseAsRupees(debitPaise);

  /// Credit formatted as rupees string (without ₹ symbol).
  String get creditRupees => _formatPaiseAsRupees(creditPaise);

  static String _formatPaiseAsRupees(int paise) {
    final rupees = paise ~/ 100;
    final paisePart = paise % 100;
    return '$rupees.${paisePart.toString().padLeft(2, '0')}';
  }

  @override
  String toString() =>
      'CustomerLedgerSummary(customerId: $customerId, customer: $customerName, '
      'debit: ₹$debitRupees, credit: ₹$creditRupees, balance: ₹$balanceRupees)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomerLedgerSummary &&
          runtimeType == other.runtimeType &&
          customerId == other.customerId &&
          customerName == other.customerName &&
          fromDate == other.fromDate &&
          toDate == other.toDate &&
          debitPaise == other.debitPaise &&
          creditPaise == other.creditPaise;

  @override
  int get hashCode =>
      customerId.hashCode ^
      customerName.hashCode ^
      fromDate.hashCode ^
      toDate.hashCode ^
      debitPaise.hashCode ^
      creditPaise.hashCode;
}
