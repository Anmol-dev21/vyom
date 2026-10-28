import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart';
import '../../database/database_providers.dart';
import '../../utils/quantity_converter.dart';

class CustomerFormScreen extends ConsumerStatefulWidget {
  const CustomerFormScreen({super.key, this.customerId});

  final int? customerId;

  @override
  ConsumerState<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _mobileController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;
  List<_AssignedProduct> _assignedProducts = [];
  final Set<int> _productIds = {};

  @override
  void initState() {
    super.initState();
    if (widget.customerId != null) {
      _loadCustomer();
    }
  }

  Future<void> _loadCustomer() async {
    final repository = ref.read(customerRepositoryProvider);
    final customer = await repository.getCustomerById(widget.customerId!);
    if (!mounted || customer == null) {
      return;
    }

    _nameController.text = customer.name;
    _addressController.text = customer.address;
    _mobileController.text = customer.mobile;

    final cpRepository = ref.read(customerProductRepositoryProvider);
    final assignments = await cpRepository.getProductsForCustomer(
      widget.customerId!,
    );

    final productRepository = ref.read(productRepositoryProvider);
    final assignedProds = <_AssignedProduct>[];

    for (final assignment in assignments) {
      final product = await productRepository.getProductById(
        assignment.productId,
      );
      if (product != null) {
        final humanQuantity = QuantityConverter.toHumanQuantity(
          assignment.defaultQuantity,
          product.unit,
        );
        assignedProds.add(
          _AssignedProduct(
            id: assignment.id,
            product: product,
            humanQuantity: humanQuantity,
            intQuantity: assignment.defaultQuantity,
          ),
        );
        _productIds.add(product.id);
      }
    }

    if (mounted) {
      setState(() {
        _assignedProducts = assignedProds;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _mobileController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.customerId != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit Customer' : 'Add Customer')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isEditing ? 'Update customer details' : 'Add a new customer',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Customer Name',
                    hintText: 'John Doe',
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) {
                      return 'Customer name is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    hintText: '123 Main Street',
                  ),
                  textInputAction: TextInputAction.next,
                  maxLines: 3,
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) {
                      return 'Address is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _mobileController,
                  decoration: const InputDecoration(
                    labelText: 'Mobile Number',
                    hintText: '9876543210',
                  ),
                  textInputAction: TextInputAction.done,
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    final digits = value?.replaceAll(RegExp(r'\D'), '') ?? '';
                    if (!RegExp(r'^\d{10}$').hasMatch(digits)) {
                      return 'A valid 10-digit mobile number is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 28),
                Text(
                  'Default Products',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (_assignedProducts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'No products assigned yet.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                else
                  Column(
                    children: _assignedProducts.map((ap) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          ap.product.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Quantity: ${ap.humanQuantity} ${ap.product.unit}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                    ),
                                    if (isEditing)
                                      IconButton(
                                        icon: const Icon(Icons.close, size: 20),
                                        onPressed: () {
                                          setState(() {
                                            _assignedProducts.removeWhere(
                                              (item) =>
                                                  item.product.id ==
                                                  ap.product.id,
                                            );
                                            _productIds.remove(ap.product.id);
                                          });
                                        },
                                      )
                                    else
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 20,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _assignedProducts.removeWhere(
                                              (item) =>
                                                  item.product.id ==
                                                  ap.product.id,
                                            );
                                            _productIds.remove(ap.product.id);
                                          });
                                        },
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _showAddProductDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Product'),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _isSubmitting ? null : _submit,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(isEditing ? 'Update Customer' : 'Save Customer'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAddProductDialog() async {
    final productRepository = ref.read(productRepositoryProvider);
    final products = await productRepository.getActiveProducts();

    final availableProducts = products
        .where((p) => !_productIds.contains(p.id))
        .toList();

    if (!mounted) {
      return;
    }

    if (availableProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No more products available to assign.')),
      );
      return;
    }

    final selectedProduct = await showDialog<Product>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Product'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            itemCount: availableProducts.length,
            itemBuilder: (context, index) {
              final product = availableProducts[index];
              return ListTile(
                title: Text(product.name),
                subtitle: Text(product.unit),
                onTap: () => Navigator.of(context).pop(product),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selectedProduct == null || !mounted) {
      return;
    }

    final quantityText = await showDialog<String>(
      context: context,
      builder: (context) => _QuantityDialog(
        productName: selectedProduct.name,
        unit: selectedProduct.unit,
      ),
    );

    if (quantityText == null || !mounted) {
      return;
    }

    try {
      final intQuantity = QuantityConverter.toIntQuantity(
        quantityText,
        selectedProduct.unit,
      );
      setState(() {
        _assignedProducts.add(
          _AssignedProduct(
            id: null,
            product: selectedProduct,
            humanQuantity: quantityText,
            intQuantity: intQuantity,
          ),
        );
        _productIds.add(selectedProduct.id);
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Invalid quantity: $e')));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final name = _nameController.text.trim();
    final address = _addressController.text.trim();
    final mobile = _mobileController.text.trim();

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final repository = ref.read(customerRepositoryProvider);
      final cpRepository = ref.read(customerProductRepositoryProvider);

      if (widget.customerId != null) {
        await repository.updateCustomer(
          id: widget.customerId!,
          name: name,
          address: address,
          mobile: mobile,
        );

        final existing = await cpRepository.getProductsForCustomer(
          widget.customerId!,
        );
        final existingIds = {for (var e in existing) e.productId};
        final newIds = {for (var ap in _assignedProducts) ap.product.id};

        for (final cp in existing) {
          if (!newIds.contains(cp.productId)) {
            await cpRepository.removeProductFromCustomer(cp.id);
          }
        }

        for (final ap in _assignedProducts) {
          if (ap.id == null) {
            if (!existingIds.contains(ap.product.id)) {
              await cpRepository.addProductToCustomer(
                customerId: widget.customerId!,
                productId: ap.product.id,
                defaultQuantity: ap.intQuantity,
              );
            }
          } else {
            final existingAssignment = existing.firstWhere(
              (e) => e.id == ap.id,
              orElse: () => existing[0],
            );
            if (existingAssignment.defaultQuantity != ap.intQuantity) {
              await cpRepository.updateCustomerProduct(
                id: ap.id!,
                defaultQuantity: ap.intQuantity,
              );
            }
          }
        }
      } else {
        final created = await repository.createCustomer(
          name: name,
          address: address,
          mobile: mobile,
        );

        for (final ap in _assignedProducts) {
          await cpRepository.addProductToCustomer(
            customerId: created.id,
            productId: ap.product.id,
            defaultQuantity: ap.intQuantity,
          );
        }
      }

      ref.invalidate(customerListProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.customerId != null
                ? 'Customer updated successfully.'
                : 'Customer added successfully.',
          ),
        ),
      );

      Navigator.of(context).pop();
    } catch (error) {
      final message = error is StateError
          ? error.message
          : 'Unable to save customer. Please try again.';

      if (mounted) {
        setState(() {
          _errorMessage = message;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }
}

class _AssignedProduct {
  final int? id;
  final Product product;
  final String humanQuantity;
  final int intQuantity;

  _AssignedProduct({
    required this.id,
    required this.product,
    required this.humanQuantity,
    required this.intQuantity,
  });
}

class _QuantityDialog extends StatefulWidget {
  final String productName;
  final String unit;

  const _QuantityDialog({required this.productName, required this.unit});

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter Default Quantity'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Product: ${widget.productName}'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              labelText: 'Quantity',
              hintText: '2',
              suffixText: widget.unit,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final value = _controller.text.trim();
            if (value.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please enter a quantity.')),
              );
              return;
            }

            try {
              QuantityConverter.toIntQuantity(value, widget.unit);
              Navigator.of(context).pop(value);
            } catch (e) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Invalid quantity: $e')));
            }
          },
          child: const Text('OK'),
        ),
      ],
    );
  }
}
