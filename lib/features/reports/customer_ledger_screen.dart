import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../database/customer_ledger_service.dart';
import '../../database/customer_ledger_summary.dart';
import '../../database/database_providers.dart';

typedef CustomerLedgerRange = ({DateTime from, DateTime to});

final customerLedgerProvider =
    FutureProvider.family<List<CustomerLedgerSummary>, CustomerLedgerRange>((
      ref,
      range,
    ) async {
      final service = CustomerLedgerService(ref.watch(appDatabaseProvider));
      return service.calculateAllCustomerLedgers(
        fromDate: range.from,
        toDate: range.to,
      );
    });

class CustomerLedgerScreen extends ConsumerStatefulWidget {
  const CustomerLedgerScreen({super.key});

  @override
  ConsumerState<CustomerLedgerScreen> createState() =>
      _CustomerLedgerScreenState();
}

class _CustomerLedgerScreenState extends ConsumerState<CustomerLedgerScreen> {
  late DateTime _fromDate;
  late DateTime _toDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fromDate = DateTime.utc(now.year, now.month, 1);
    _toDate = DateTime.utc(now.year, now.month + 1, 0);
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
      firstDate: DateTime.utc(2024, 1, 1),
      lastDate: DateTime.utc(2100, 12, 31),
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _fromDate = DateTime.utc(
        picked.start.year,
        picked.start.month,
        picked.start.day,
      );
      _toDate = DateTime.utc(picked.end.year, picked.end.month, picked.end.day);
    });
  }

  String _formatPaise(int paise) {
    final rupees = paise / 100;
    return '₹${rupees.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final ledgerAsync = ref.watch(
      customerLedgerProvider((from: _fromDate, to: _toDate)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Ledger'),
        actions: [
          IconButton(
            tooltip: 'Pick date range',
            onPressed: _pickDateRange,
            icon: const Icon(Icons.date_range_outlined),
          ),
        ],
      ),
      body: ledgerAsync.when(
        data: (ledgers) {
          final totalDebit = ledgers.fold<int>(
            0,
            (sum, ledger) => sum + ledger.debitPaise,
          );
          final totalCredit = ledgers.fold<int>(
            0,
            (sum, ledger) => sum + ledger.creditPaise,
          );
          final balance = totalDebit - totalCredit;

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_fromDate.day}/${_fromDate.month}/${_fromDate.year} - ${_toDate.day}/${_toDate.month}/${_toDate.year}',
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
                          value: _formatPaise(balance),
                          color: balance >= 0 ? Colors.orange : Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Customer balances',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  if (ledgers.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text('No customer activity in this date range.'),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        itemCount: ledgers.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final ledger = ledgers[index];
                          final balancePaise = ledger.balancePaise;

                          return Card(
                            child: ListTile(
                              onTap: () {
                                context.push(
                                  '/reports/customer/${ledger.customerId}'
                                  '?name=${Uri.encodeComponent(ledger.customerName)}'
                                  '&fromDate=${Uri.encodeComponent(_fromDate.toIso8601String())}'
                                  '&toDate=${Uri.encodeComponent(_toDate.toIso8601String())}',
                                );
                              },
                              title: Text(
                                ledger.customerName,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              subtitle: Text('Customer #${ledger.customerId}'),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _formatPaise(ledger.debitPaise),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'Bal: ${_formatPaise(balancePaise)}',
                                    style: TextStyle(
                                      color: balancePaise >= 0
                                          ? Colors.orange
                                          : Colors.green,
                                      fontWeight: FontWeight.w600,
                                    ),
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
            child: Text('Unable to load ledger data.\n$error'),
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
