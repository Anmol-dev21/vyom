import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../database/database_providers.dart';

class BusinessSetupScreen extends ConsumerStatefulWidget {
  const BusinessSetupScreen({super.key, this.mode = 'create'});

  final String mode;

  @override
  ConsumerState<BusinessSetupScreen> createState() =>
      _BusinessSetupScreenState();
}

class _BusinessSetupScreenState extends ConsumerState<BusinessSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firmNameController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _mobileController = TextEditingController();

  bool _isSubmitting = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(businessProfileProvider).asData?.value;
    if (profile != null) {
      _firmNameController.text = profile.firmName;
      _ownerNameController.text = profile.ownerName;
      _addressController.text = profile.address;
      _mobileController.text = profile.mobile;
    }
  }

  @override
  void dispose() {
    _firmNameController.dispose();
    _ownerNameController.dispose();
    _addressController.dispose();
    _mobileController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(businessProfileProvider).asData?.value;
    final isEditMode = widget.mode == 'edit' || profile != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditMode ? 'Business Profile' : 'Business Setup'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isEditMode
                      ? 'Update your business details'
                      : 'Set up your business',
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _firmNameController,
                  decoration: const InputDecoration(
                    labelText: 'Firm Name',
                    hintText: 'Vyom Traders',
                  ),
                  validator: _requiredValidator,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _ownerNameController,
                  decoration: const InputDecoration(
                    labelText: 'Owner Name',
                    hintText: 'Rajesh Kumar',
                  ),
                  validator: _requiredValidator,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    hintText: 'Street, city, state',
                  ),
                  maxLines: 3,
                  validator: _requiredValidator,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _mobileController,
                  decoration: const InputDecoration(
                    labelText: 'Mobile Number',
                    hintText: '9876543210',
                  ),
                  keyboardType: TextInputType.phone,
                  validator: _mobileValidator,
                  textInputAction: TextInputAction.done,
                ),
                if (_saveError != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _saveError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _isSubmitting ? null : _saveProfile,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(isEditMode ? 'Update Profile' : 'Save Profile'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }

  String? _mobileValidator(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Mobile number is required.';
    }

    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^\d{10}$').hasMatch(digits)) {
      return 'Enter a valid 10-digit Indian mobile number.';
    }

    return null;
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final firmName = _firmNameController.text.trim();
    final ownerName = _ownerNameController.text.trim();
    final address = _addressController.text.trim();
    final mobile = _mobileController.text.trim().replaceAll(RegExp(r'\D'), '');

    setState(() {
      _isSubmitting = true;
      _saveError = null;
    });

    try {
      final repository = ref.read(businessProfileRepositoryProvider);
      final profile = await repository.getBusinessProfile();

      if (profile == null) {
        await repository.saveBusinessProfile(
          firmName: firmName,
          ownerName: ownerName,
          address: address,
          mobile: mobile,
        );
      } else {
        await repository.updateBusinessProfile(
          firmName: firmName,
          ownerName: ownerName,
          address: address,
          mobile: mobile,
        );
      }

      ref.invalidate(businessProfileProvider);

      if (mounted) {
        context.go('/dashboard');
      }
    } catch (error) {
      setState(() {
        _saveError = 'Unable to save business profile. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }
}
