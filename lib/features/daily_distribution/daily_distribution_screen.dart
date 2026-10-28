import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/database_providers.dart';

class CustomerDistributionState {
  const CustomerDistributionState({
    required this.customerId,
    required this.customerName,
    required this.quantities,
    this.status = 'none',
  });

  final int customerId;
  final String customerName;
  final Map<int, int> quantities;
  final String status;
}

class CustomerDraftEntry {
  const CustomerDraftEntry({required this.customerId, required this.items});

  final int customerId;
  final List<({int productId, int quantity})> items;
}

class DailyDistributionScreen extends ConsumerStatefulWidget {
  const DailyDistributionScreen({super.key});

  static List<CustomerDraftEntry> buildDraftPayload(
    List<CustomerDistributionState> customers,
  ) {
    final payload = <CustomerDraftEntry>[];

    for (final customer in customers) {
      final items = <({int productId, int quantity})>[];

      for (final entry in customer.quantities.entries) {
        final productId = entry.key;
        final quantity = entry.value;

        if (quantity >= 0) {
          items.add((productId: productId, quantity: quantity));
        }
      }

      if (items.isNotEmpty) {
        payload.add(
          CustomerDraftEntry(customerId: customer.customerId, items: items),
        );
      }
    }

    return payload;
  }

  static int calculateDailyTotal(List<CustomerDistributionState> customers) {
    return calculateDailyTotals(customers).values
        .fold<int>(0, (sum, value) => sum + value);
  }

  static Map<int, int> calculateDailyTotals(
    List<CustomerDistributionState> customers,
  ) {
    final totals = <int, int>{};
    for (final customer in customers) {
      for (final entry in customer.quantities.entries) {
        if (entry.value >= 0) {
          totals[entry.key] = (totals[entry.key] ?? 0) + entry.value;
        }
      }
    }
    return totals;
  }

  static bool isDateConfirmed(List<CustomerDistributionState> customers) {
    final persisted = customers
        .where((customer) => customer.status != 'none')
        .toList();

    if (persisted.isEmpty) {
      return false;
    }

    return persisted.every((customer) => customer.status == 'confirmed');
  }

  @override
  ConsumerState<DailyDistributionScreen> createState() =>
      _DailyDistributionScreenState();
}

class _DailyDistributionScreenState
    extends ConsumerState<DailyDistributionScreen> {
  final TextEditingController _searchController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isReadOnly = false;
  List<CustomerDistributionState> _customers = const [];

  @override
  void initState() {
    super.initState();
    _loadForSelectedDate();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadForSelectedDate() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final customerRepository = ref.read(customerRepositoryProvider);
      final customerProductRepository = ref.read(
        customerProductRepositoryProvider,
      );
      final productRepository = ref.read(productRepositoryProvider);
      final distributionRepository = ref.read(
        dailyDistributionRepositoryProvider,
      );

      final activeCustomers = await customerRepository.getActiveCustomers();
      final distributions = await distributionRepository.getDistributionsByDate(
        _selectedDate,
      );
      final customersById = {
        for (final customer in activeCustomers) customer.id: customer,
      };
      for (final distribution in distributions) {
        final customer = await customerRepository.getCustomerById(
          distribution.customerId,
        );
        if (customer != null) {
          customersById[customer.id] = customer;
        }
      }
      final loaded = <CustomerDistributionState>[];

      for (final customer in customersById.values) {
        final assignments = await customerProductRepository
            .getProductsForCustomer(customer.id);
        final quantities = <int, int>{};

        for (final assignment in assignments) {
          final product = await productRepository.getProductById(
            assignment.productId,
          );
          if (product == null) {
            continue;
          }
          quantities[product.id] = assignment.defaultQuantity;
        }

        final distribution = distributions
            .where((entry) => entry.customerId == customer.id)
            .firstOrNull;

        if (distribution != null) {
          final items = await distributionRepository.getDistributionItems(
            distribution.id,
          );
          final distributionQuantities = <int, int>{};
          for (final item in items) {
            distributionQuantities[item.productId] = item.quantity;
          }

          final merged = <int, int>{};
          for (final entry in {
            ...quantities,
            ...distributionQuantities,
          }.entries) {
            merged[entry.key] = entry.value;
          }

          loaded.add(
            CustomerDistributionState(
              customerId: customer.id,
              customerName: customer.name,
              quantities: merged,
              status: distribution.status,
            ),
          );
          continue;
        }

        loaded.add(
          CustomerDistributionState(
            customerId: customer.id,
            customerName: customer.name,
            quantities: quantities,
            status: 'none',
          ),
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _customers = loaded;
        _isReadOnly = DailyDistributionScreen.isDateConfirmed(loaded);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to load distribution data.')),
      );
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _selectedDate = picked;
      _isReadOnly = false;
    });
    await _loadForSelectedDate();
  }

  void _updateQuantity(int customerId, int productId, String value) {
    final customer = _customers.firstWhere(
      (entry) => entry.customerId == customerId,
      orElse: () => const CustomerDistributionState(
        customerId: -1,
        customerName: '',
        quantities: {},
      ),
    );

    if (customer.customerId == -1) {
      return;
    }

    final parsed = int.tryParse(value.trim());
    final next = Map<int, int>.from(customer.quantities);
    next[productId] = parsed ?? 0;

    setState(() {
      _customers = _customers.map((entry) {
        if (entry.customerId == customerId) {
          return CustomerDistributionState(
            customerId: entry.customerId,
            customerName: entry.customerName,
            quantities: next,
            status: entry.status,
          );
        }
        return entry;
      }).toList();
    });
  }

  Future<void> _saveDraft() async {
    if (_isSaving) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final repository = ref.read(dailyDistributionRepositoryProvider);
      final payload = DailyDistributionScreen.buildDraftPayload(_customers);
      await repository.saveDailyDistributionBatch(
        distributionDate: _selectedDate,
        entries: [
          for (final draft in payload)
            (customerId: draft.customerId, items: draft.items),
        ],
      );

      await _loadForSelectedDate();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draft saved successfully.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to save draft: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _confirmDistribution() async {
    if (_isSaving) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final repository = ref.read(dailyDistributionRepositoryProvider);
      final payload = DailyDistributionScreen.buildDraftPayload(_customers);
      await repository.confirmDailyDistributionBatch(
        distributionDate: _selectedDate,
        entries: [
          for (final draft in payload)
            (customerId: draft.customerId, items: draft.items),
        ],
      );

      await _loadForSelectedDate();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Distribution confirmed.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Unable to confirm: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final visibleCustomers = query.isEmpty
        ? _customers
        : _customers.where((customer) {
            return customer.customerName.toLowerCase().contains(query);
          }).toList();

    final total = DailyDistributionScreen.calculateDailyTotal(_customers);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Update'),
        actions: [
          IconButton(
            onPressed: _pickDate,
            tooltip: 'Select date',
            icon: const Icon(Icons.calendar_today_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Date: ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Chip(label: Text(_isReadOnly ? 'Confirmed' : 'Draft')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search customers',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total delivered'),
                            Text(
                              '$total units',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: visibleCustomers.isEmpty
                          ? const Center(child: Text('No customers found.'))
                          : ListView.separated(
                              itemCount: visibleCustomers.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final customer = visibleCustomers[index];
                                final entries = customer.quantities.entries
                                    .toList();

                                return Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          customer.customerName,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: 12),
                                        if (entries.isEmpty)
                                          const Text('No assigned products.')
                                        else
                                          ...entries.map((entry) {
                                            final quantity = entry.value;
                                            final textValue = quantity
                                                .toString();
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 10,
                                              ),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      'Product #${entry.key}',
                                                    ),
                                                  ),
                                                  SizedBox(
                                                    width: 120,
                                                    child: TextField(
                                                      enabled:
                                                          !_isReadOnly &&
                                                          customer.status ==
                                                              'draft',
                                                      keyboardType:
                                                          const TextInputType.numberWithOptions(
                                                            decimal: false,
                                                          ),
                                                      controller:
                                                          TextEditingController(
                                                              text: textValue,
                                                            )
                                                            ..selection =
                                                                TextSelection.fromPosition(
                                                                  TextPosition(
                                                                    offset: textValue
                                                                        .length,
                                                                  ),
                                                                ),
                                                      onChanged: (value) =>
                                                          _updateQuantity(
                                                            customer.customerId,
                                                            entry.key,
                                                            value,
                                                          ),
                                                      decoration:
                                                          const InputDecoration(
                                                            isDense: true,
                                                            border:
                                                                OutlineInputBorder(),
                                                          ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isReadOnly || _isSaving
                                ? null
                                : _saveDraft,
                            icon: const Icon(Icons.save_alt_outlined),
                            label: const Text('Save Draft'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isReadOnly || _isSaving
                                ? null
                                : _confirmDistribution,
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Confirm'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
