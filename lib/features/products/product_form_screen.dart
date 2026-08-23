import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/database_providers.dart';

class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.productId});

  final int? productId;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _units = const ['litre', 'kg', 'gram', 'piece', 'packet'];
  String? _selectedUnit;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedUnit = _units.first;
    if (widget.productId != null) {
      _loadProduct();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadProduct() async {
    final repository = ref.read(productRepositoryProvider);
    final product = await repository.getProductById(widget.productId!);
    if (!mounted || product == null) {
      return;
    }

    _nameController.text = product.name;
    _selectedUnit = product.unit;
    if (_selectedUnit == null || !_units.contains(_selectedUnit)) {
      _selectedUnit = _units.first;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.productId != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit Product' : 'Add Product')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isEditing ? 'Update product details' : 'Add a new product',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Product Name',
                    hintText: 'Milk',
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) {
                      return 'Product name is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: _selectedUnit,
                  decoration: const InputDecoration(labelText: 'Unit'),
                  items: _units
                      .map(
                        (unit) =>
                            DropdownMenuItem(value: unit, child: Text(unit)),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _selectedUnit = value),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please select a unit.';
                    }
                    return null;
                  },
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
                  label: Text(isEditing ? 'Update Product' : 'Save Product'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final name = _nameController.text.trim();
    final unit = (_selectedUnit ?? '').trim();

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final repository = ref.read(productRepositoryProvider);

      if (widget.productId != null) {
        await repository.updateProduct(
          id: widget.productId!,
          name: name,
          unit: unit,
        );
      } else {
        await repository.createProduct(name: name, unit: unit);
      }

      ref.invalidate(productListProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.productId != null
                ? 'Product updated successfully.'
                : 'Product added successfully.',
          ),
        ),
      );

      Navigator.of(context).pop();
    } catch (error) {
      final message = error is StateError
          ? (error.message.contains('already exists')
                ? 'A product with this name is already active.'
                : 'Unable to save product. Please try again.')
          : 'Unable to save product. Please try again.';

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
