import 'package:drift/drift.dart';

import 'app_database.dart';

class TransactionRepository {
  TransactionRepository(this._db);

  final AppDatabase _db;

  static int parseRupeesToPaise(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Amount is required.');
    }

    final match = RegExp(r'^\d+(?:\.\d{1,2})?$').firstMatch(normalized);
    if (match == null) {
      throw const FormatException(
        'Amount must be a valid rupee value with up to two decimal places.',
      );
    }

    final parts = normalized.split('.');
    if (parts.length == 2 && parts[1].length > 2) {
      throw const FormatException(
        'Amount must not contain more than two decimal places.',
      );
    }

    final amount = double.parse(normalized);
    if (amount <= 0) {
      throw const FormatException('Amount must be greater than zero.');
    }

    return (amount * 100).round();
  }

  Future<TransactionRecord> createTransaction({
    required int customerId,
    required DateTime transactionDate,
    required TransactionType transactionType,
    required PaymentMethod paymentMethod,
    required int amountInPaise,
    String? note,
  }) async {
    final normalizedDate = _normalizeDate(transactionDate);

    if (amountInPaise <= 0) {
      throw StateError('Transaction amount must be greater than zero.');
    }

    final customerExists = await (_db.select(
      _db.customers,
    )..where((tbl) => tbl.id.equals(customerId))).getSingleOrNull();
    if (customerExists == null) {
      throw StateError('Customer not found.');
    }

    final cleanedNote = note?.trim();

    final id = await _db
        .into(_db.transactions)
        .insert(
          TransactionsCompanion(
            customerId: Value(customerId),
            transactionDate: Value(normalizedDate),
            amount: Value(amountInPaise),
            transactionType: Value(transactionType),
            paymentMethod: Value(paymentMethod),
            note: Value(
              cleanedNote != null && cleanedNote.isNotEmpty
                  ? cleanedNote
                  : null,
            ),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );

    final created = await getTransactionById(id);
    if (created == null) {
      throw StateError('Unable to create transaction.');
    }
    return created;
  }

  Future<TransactionRecord?> getTransactionById(int id) async {
    final row = await (_db.select(
      _db.transactions,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
    if (row == null) {
      return null;
    }
    return TransactionRecord.fromDrift(row);
  }

  Future<List<TransactionRecord>> getTransactionsForCustomer(
    int customerId,
  ) async {
    final rows =
        await (_db.select(_db.transactions)
              ..where((tbl) => tbl.customerId.equals(customerId))
              ..orderBy([(tbl) => OrderingTerm.desc(tbl.transactionDate)]))
            .get();
    return rows.map(TransactionRecord.fromDrift).toList();
  }

  Future<List<TransactionRecord>> getTransactionsByDate(DateTime date) async {
    final normalized = _normalizeDate(date);
    final rows =
        await (_db.select(_db.transactions)
              ..where((tbl) => tbl.transactionDate.equals(normalized))
              ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
            .get();
    return rows.map(TransactionRecord.fromDrift).toList();
  }

  Future<List<TransactionRecord>> getTransactionsBetweenDates(
    DateTime start,
    DateTime end,
  ) async {
    final startDate = _normalizeDate(start);
    final endDate = _normalizeDate(end);
    final rows =
        await (_db.select(_db.transactions)
              ..where(
                (tbl) =>
                    tbl.transactionDate.isBetweenValues(startDate, endDate),
              )
              ..orderBy([(tbl) => OrderingTerm.asc(tbl.transactionDate)]))
            .get();
    return rows.map(TransactionRecord.fromDrift).toList();
  }

  Future<TransactionRecord> updateTransaction({
    required int id,
    required int customerId,
    required DateTime transactionDate,
    required TransactionType transactionType,
    required PaymentMethod paymentMethod,
    required int amountInPaise,
    String? note,
  }) async {
    final existing = await getTransactionById(id);
    if (existing == null) {
      throw StateError('Transaction not found.');
    }

    if (amountInPaise <= 0) {
      throw StateError('Transaction amount must be greater than zero.');
    }

    final customerExists = await (_db.select(
      _db.customers,
    )..where((tbl) => tbl.id.equals(customerId))).getSingleOrNull();
    if (customerExists == null) {
      throw StateError('Customer not found.');
    }

    final cleanedNote = note?.trim();

    await (_db.update(
      _db.transactions,
    )..where((tbl) => tbl.id.equals(id))).write(
      TransactionsCompanion(
        customerId: Value(customerId),
        transactionDate: Value(_normalizeDate(transactionDate)),
        amount: Value(amountInPaise),
        transactionType: Value(transactionType),
        paymentMethod: Value(paymentMethod),
        note: Value(
          cleanedNote != null && cleanedNote.isNotEmpty ? cleanedNote : null,
        ),
        updatedAt: Value(DateTime.now()),
      ),
    );

    final updated = await getTransactionById(id);
    if (updated == null) {
      throw StateError('Unable to update transaction.');
    }
    return updated;
  }

  Future<void> deleteTransaction(int id) async {
    final exists = await getTransactionById(id);
    if (exists == null) {
      throw StateError('Transaction not found.');
    }
    await (_db.delete(
      _db.transactions,
    )..where((tbl) => tbl.id.equals(id))).go();
  }

  DateTime _normalizeDate(DateTime value) {
    return DateTime.utc(value.year, value.month, value.day);
  }
}

class TransactionRecord {
  TransactionRecord({
    required this.id,
    required this.customerId,
    required this.transactionDate,
    required this.amountInPaise,
    required this.transactionType,
    required this.paymentMethod,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int customerId;
  final DateTime transactionDate;
  final int amountInPaise;
  final TransactionType transactionType;
  final PaymentMethod paymentMethod;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory TransactionRecord.fromDrift(Transaction row) {
    return TransactionRecord(
      id: row.id,
      customerId: row.customerId,
      transactionDate: row.transactionDate,
      amountInPaise: row.amount,
      transactionType: row.transactionType,
      paymentMethod: row.paymentMethod,
      note: row.note,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }
}
