import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/customer_ledger_service.dart';
import '../../database/database_providers.dart';

typedef CustomerLedgerEntryArgs = ({
  int customerId,
  DateTime from,
  DateTime to,
});

final customerLedgerEntriesProvider =
    FutureProvider.family<List<CustomerLedgerEntry>, CustomerLedgerEntryArgs>((
      ref,
      args,
    ) async {
      final service = CustomerLedgerService(ref.watch(appDatabaseProvider));
      return service.calculateCustomerLedgerEntries(
        customerId: args.customerId,
        fromDate: args.from,
        toDate: args.to,
      );
    });

class CustomerLedgerDetailScreen extends ConsumerWidget {
  const CustomerLedgerDetailScreen({
    super.key,
    required this.customerId,
    required this.customerName,
    required this.fromDate,
    required this.toDate,
  });

  final int customerId;
  final String customerName;
  final DateTime fromDate;
  final DateTime toDate;

  String _formatPaise(int paise) => '₹${(paise / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(
      customerLedgerEntriesProvider((
        customerId: customerId,
        from: fromDate,
        to: toDate,
      )),
    );

    return Scaffold(
      appBar: AppBar(title: Text('$customerName ledger')),
      body: entriesAsync.when(
        data: (entries) {
          final totalDebit = entries
              .where((entry) => entry.type == CustomerLedgerEntryType.debit)
              .fold<int>(0, (sum, entry) => sum + entry.amountPaise);
          final totalCredit = entries
              .where((entry) => entry.type == CustomerLedgerEntryType.credit)
              .fold<int>(0, (sum, entry) => sum + entry.amountPaise);
          final currentBalance = totalDebit - totalCredit;

          var runningBalance = 0;
          final rows = entries.map((entry) {
            final delta = entry.type == CustomerLedgerEntryType.debit
                ? entry.amountPaise
                : -entry.amountPaise;
            runningBalance += delta;
            return (entry: entry, runningBalance: runningBalance);
          }).toList();

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${fromDate.day}/${fromDate.month}/${fromDate.year} - ${toDate.day}/${toDate.month}/${toDate.year}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryCard(
                          label: 'Debit',
                          value: _formatPaise(totalDebit),
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SummaryCard(
                          label: 'Credit',
                          value: _formatPaise(totalCredit),
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SummaryCard(
                          label: 'Balance',
                          value: _formatPaise(currentBalance),
                          color: currentBalance >= 0
                              ? Colors.orange
                              : Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Ledger entries',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  if (entries.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text('No ledger entries in this date range.'),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          final entry = row.entry;
                          final isDebit =
                              entry.type == CustomerLedgerEntryType.debit;
                          final color = isDebit ? Colors.orange : Colors.green;
                          final sign = isDebit ? 'DR' : 'CR';

                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: color.withAlpha(28),
                                child: Icon(
                                  isDebit
                                      ? Icons.arrow_upward_rounded
                                      : Icons.arrow_downward_rounded,
                                  color: color,
                                ),
                              ),
                              title: Text(
                                entry.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    '$sign • ${entry.entryDate.day}/${entry.entryDate.month}/${entry.entryDate.year}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                  if ((entry.note ?? '').isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      entry.note!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ],
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    isDebit
                                        ? '+${_formatPaise(entry.amountPaise)}'
                                        : '-${_formatPaise(entry.amountPaise)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: color,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Bal: ${_formatPaise(row.runningBalance)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text('Unable to load ledger details.\n$error'),
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withAlpha(24),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
