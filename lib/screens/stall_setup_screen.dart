import 'package:flutter/material.dart';
import '../services/auth_repository.dart';
import '../services/error_messages.dart';
import '../services/validators.dart';
import '../widgets/auth_widgets.dart';

class StallSetupScreen extends StatefulWidget {
  const StallSetupScreen({super.key, required this.repository});
  final AuthRepository repository;
  @override
  State<StallSetupScreen> createState() => _StallSetupScreenState();
}

class _StallSetupScreenState extends State<StallSetupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _category = TextEditingController(),
      _minutes = TextEditingController(text: '15');
  bool _busy = false;
  String? _error;
  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    FocusScope.of(context).unfocus();
    try {
      await widget.repository.setupStall(
        _name.text,
        _category.text,
        int.parse(_minutes.text.trim()),
      );
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.repository.logout();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    child: Form(
      key: _form,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Brand(),
          const SizedBox(height: 48),
          const FormHeading(
            'Set Up Your Stall',
            'A few details to get started',
          ),
          AppField(
            label: 'Stall Name',
            controller: _name,
            validator: Validators.name,
            enabled: !_busy,
          ),
          AppField(
            label: 'Food Category',
            controller: _category,
            validator: Validators.name,
            enabled: !_busy,
          ),
          AppField(
            label: 'Initial Preparation Time (minutes)',
            controller: _minutes,
            keyboardType: TextInputType.number,
            validator: Validators.minutes,
            enabled: !_busy,
          ),
          ErrorMessage(_error),
          PrimaryButton(
            'Complete Stall Setup',
            onPressed: _submit,
            loading: _busy,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _busy ? null : _logout,
            child: const Text('Logout'),
          ),
        ],
      ),
    ),
  );
}
