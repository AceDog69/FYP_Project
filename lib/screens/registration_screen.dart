import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/auth_repository.dart';
import '../services/error_messages.dart';
import '../services/validators.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({
    super.key,
    required this.repository,
    this.completingProfile = false,
  });
  final AuthRepository repository;
  final bool completingProfile;
  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _email = TextEditingController(),
      _phone = TextEditingController(),
      _password = TextEditingController(),
      _confirmation = TextEditingController();
  AccountRole? _role = AccountRole.student;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    if (widget.completingProfile) _email.text = widget.repository.email ?? '';
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.completingProfile) {
        await widget.repository.completeProfile(
          fullName: _name.text,
          phoneNumber: _phone.text,
          role: _role!,
        );
      } else {
        await widget.repository.register(
          fullName: _name.text,
          email: _email.text,
          phoneNumber: _phone.text,
          password: _password.text,
          role: _role!,
        );
      }
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
    for (final c in [_name, _email, _phone, _password, _confirmation]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AuthLayout(
      back: !widget.completingProfile,
      child: Form(
        key: _form,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            FormHeading(
              widget.completingProfile
                  ? 'Complete Your Account'
                  : 'Create Account',
              widget.completingProfile
                  ? 'Finish your Smart Canteen profile'
                  : 'Join Smart Canteen',
            ),
            AppField(
              label: 'Full Name',
              controller: _name,
              validator: Validators.name,
              enabled: !_busy,
              autofillHints: const [AutofillHints.name],
            ),
            AppField(
              label: 'Email Address',
              controller: _email,
              validator: Validators.email,
              keyboardType: TextInputType.emailAddress,
              enabled: !_busy && !widget.completingProfile,
              autofillHints: const [AutofillHints.email],
            ),
            AppField(
              label: 'Phone Number',
              controller: _phone,
              validator: Validators.phone,
              keyboardType: TextInputType.phone,
              enabled: !_busy,
              autofillHints: const [AutofillHints.telephoneNumber],
            ),
            if (!widget.completingProfile) ...[
              AppField(
                label: 'Password',
                controller: _password,
                password: true,
                validator: Validators.password,
                enabled: !_busy,
                autofillHints: const [AutofillHints.newPassword],
              ),
              AppField(
                label: 'Confirm Password',
                controller: _confirmation,
                password: true,
                enabled: !_busy,
                validator: (value) =>
                    Validators.required(value) ??
                    (value != _password.text
                        ? 'Passwords do not match.'
                        : null),
              ),
            ],
            const Text('Select Role', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            FormField<AccountRole>(
              initialValue: _role,
              validator: (role) =>
                  role == null ? 'Please select your role.' : null,
              builder: (field) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: AccountRole.values
                        .map(
                          (role) => Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: role == AccountRole.student ? 6 : 0,
                                left: role == AccountRole.vendor ? 6 : 0,
                              ),
                              child: Semantics(
                                selected: _role == role,
                                button: true,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 56),
                                    foregroundColor: _role == role
                                        ? primaryOrange
                                        : const Color(0xFF505560),
                                    backgroundColor: _role == role
                                        ? lightOrange
                                        : const Color(0xFFFAFAFB),
                                    side: BorderSide(
                                      color: _role == role
                                          ? primaryOrange
                                          : const Color(0xFFDFE1E6),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: _busy
                                      ? null
                                      : () {
                                          setState(() => _role = role);
                                          field.didChange(role);
                                        },
                                  icon: Icon(
                                    role == AccountRole.student
                                        ? Icons.school_outlined
                                        : Icons.storefront_outlined,
                                    size: 20,
                                  ),
                                  label: Text(
                                    role == AccountRole.student
                                        ? 'Student'
                                        : 'Vendor',
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  if (field.hasError)
                    Text(
                      field.errorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ErrorMessage(_error),
            PrimaryButton(
              widget.completingProfile ? 'Complete Account' : 'Create Account',
              onPressed: _submit,
              loading: _busy,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _busy
                  ? null
                  : widget.completingProfile
                  ? _logout
                  : () => Navigator.of(context).pop(),
              child: Text(
                widget.completingProfile
                    ? 'Logout'
                    : 'Already have an account? Login',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
