import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart';
import '../../database/database_providers.dart';
import '../../database/transaction_repository.dart';

class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({super.key});

  @override
  ConsumerState<TransactionFormScreen> createState() =>
      _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  final _formKey = GlobalKey<FormState>();

  List<Customer> _customers = const [];
  bool _isLoading = true;
  bool _isSubmitting = false;

  int? _customerId;
  DateTime _transactionDate = DateTime.now();
  TransactionType _transactionType = TransactionType.received;
  PaymentMethod _paymentMethod = PaymentMethod.cash;
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    try {
      final repository = ref.read(customerRepositoryProvider);
      final customers = await repository.getActiveCustomers();

      if (!mounted) {
        return;
      }

      setState(() {
        _customers = customers;
        _customerId = customers.isNotEmpty ? customers.first.id : null;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to load customers.')),
      );
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _transactionDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() => _transactionDate = picked);
  }

  Future<void> _submit() async {
    if (_customerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a customer before creating a transaction.'),
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final amountText = _amountController.text.trim();
      final amountInPaise = TransactionRepository.parseRupeesToPaise(
        amountText,
      );
      final repository = ref.read(transactionRepositoryProvider);

      await repository.createTransaction(
        customerId: _customerId!,
        transactionDate: _transactionDate,
        transactionType: _transactionType,
        paymentMethod: _paymentMethod,
        amountInPaise: amountInPaise,
        note: _noteController.text.trim(),
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save transaction: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Transaction')),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Record money received or given',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 24),
                      DropdownButtonFormField<int>(
                        initialValue: _customerId,
                        items: _customers
                            .map(
                              (customer) => DropdownMenuItem<int>(
                                value: customer.id,
                                child: Text(customer.name),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _customerId = value),
                        decoration: const InputDecoration(
                          labelText: 'Customer',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (value) {
                          if (value == null) {
                            return 'Please select a customer.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      InkWell(
                        onTap: _pickDate,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Date',
                            prefixIcon: Icon(Icons.calendar_today_outlined),
                          ),
                          child: Text(
                            '${_transactionDate.day}/${_transactionDate.month}/${_transactionDate.year}',
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SegmentedButton<TransactionType>(
                        segments: const [
                          ButtonSegment(
                            value: TransactionType.received,
                            label: Text('Received'),
                            icon: Icon(Icons.arrow_downward),
                          ),
                          ButtonSegment(
                            value: TransactionType.given,
                            label: Text('Given'),
                            icon: Icon(Icons.arrow_upward),
                          ),
                        ],
                        selected: {_transactionType},
                        onSelectionChanged: (selection) {
                          setState(() => _transactionType = selection.first);
                        },
                      ),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<PaymentMethod>(
                        initialValue: _paymentMethod,
                        items: PaymentMethod.values
                            .map(
                              (method) => DropdownMenuItem<PaymentMethod>(
                                value: method,
                                child: Text(method.name.toUpperCase()),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(
                          () => _paymentMethod = value ?? PaymentMethod.cash,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Payment Method',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Amount (₹)',
                          hintText: '2500.50',
                          prefixIcon: Icon(Icons.currency_rupee_outlined),
                        ),
                        validator: (value) {
                          final trimmed = value?.trim() ?? '';
                          if (trimmed.isEmpty) {
                            return 'Amount is required.';
                          }
                          try {
                            TransactionRepository.parseRupeesToPaise(trimmed);
                            return null;
                          } catch (_) {
                            return 'Use up to 2 decimal places and a value greater than zero.';
                          }
                        },
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _noteController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Note (optional)',
                          prefixIcon: Icon(Icons.edit_note_outlined),
                        ),
                      ),
                      const SizedBox(height: 28),
                      FilledButton.icon(
                        onPressed: _isSubmitting ? null : _submit,
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          _isSubmitting ? 'Saving...' : 'Save Transaction',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
