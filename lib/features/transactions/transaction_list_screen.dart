import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart';
import '../../database/database_providers.dart';
import '../../database/transaction_repository.dart';
import 'transaction_form_screen.dart';

final transactionListProvider = FutureProvider<List<TransactionRecord>>((
  ref,
) async {
  final repository = ref.watch(transactionRepositoryProvider);
  final records = await repository.getTransactionsBetweenDates(
    DateTime(2024, 1, 1),
    DateTime(2100, 12, 31),
  );
  records.sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
  return records;
});

class TransactionListScreen extends ConsumerStatefulWidget {
  const TransactionListScreen({super.key});

  @override
  ConsumerState<TransactionListScreen> createState() =>
      _TransactionListScreenState();
}

class _TransactionListScreenState extends ConsumerState<TransactionListScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(transactionListProvider);
  }

  String _formatAmount(int paise) => '₹${(paise / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final asyncTransactions = ref.watch(transactionListProvider);
    final query = _searchController.text.trim().toLowerCase();

    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const TransactionFormScreen()),
          );
          if (result == true && mounted) {
            ref.invalidate(transactionListProvider);
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Transaction'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search by note or customer',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: asyncTransactions.when(
                  data: (transactions) {
                    final filtered = query.isEmpty
                        ? transactions
                        : transactions.where((transaction) {
                            final customerIdText = transaction.customerId
                                .toString();
                            final note = (transaction.note ?? '').toLowerCase();
                            return customerIdText.contains(query) ||
                                note.contains(query);
                          }).toList();

                    if (filtered.isEmpty) {
                      return const Center(
                        child: Text('No transactions found.'),
                      );
                    }

                    return RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final transaction = filtered[index];
                          final typeColor =
                              transaction.transactionType ==
                                  TransactionType.received
                              ? Colors.green
                              : Colors.orange;

                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: typeColor.withValues(
                                  alpha: 0.12,
                                ),
                                child: Icon(
                                  transaction.transactionType ==
                                          TransactionType.received
                                      ? Icons.arrow_downward
                                      : Icons.arrow_upward,
                                  color: typeColor,
                                ),
                              ),
                              title: Text(
                                '${transaction.transactionType.name.toUpperCase()} • ${transaction.paymentMethod.name.toUpperCase()}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    'Customer #${transaction.customerId}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium,
                                  ),
                                  Text(
                                    '${transaction.transactionDate.day}/${transaction.transactionDate.month}/${transaction.transactionDate.year}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                  if ((transaction.note ?? '').isNotEmpty)
                                    Text(
                                      transaction.note!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                ],
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _formatAmount(transaction.amountInPaise),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: typeColor,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    transaction.transactionType ==
                                            TransactionType.received
                                        ? 'Incoming'
                                        : 'Outgoing',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, stackTrace) => Center(
                    child: Text('Unable to load transactions.\n$error'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
