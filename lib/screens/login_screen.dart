import 'package:flutter/material.dart';
import '../services/auth_repository.dart';
import '../services/error_messages.dart';
import '../services/validators.dart';
import '../widgets/auth_widgets.dart';
import 'registration_screen.dart';
import 'password_screens.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.repository});
  final AuthRepository repository;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController(), _password = TextEditingController();
  bool _busy = false;
  String? _error;
  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.login(_email.text, _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    footer: TextButton(
      onPressed: _busy
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    RegistrationScreen(repository: widget.repository),
              ),
            ),
      child: const Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: "Don't have an account? ",
              style: TextStyle(color: Color(0xFF778295)),
            ),
            TextSpan(
              text: 'Register',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ),
    child: AutofillGroup(
      child: Form(
        key: _form,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Brand(prominent: true),
            const SizedBox(height: 64),
            const FormHeading('Welcome Back', 'Sign in to your account'),
            AppField(
              label: 'Email Address',
              controller: _email,
              enabled: !_busy,
              validator: Validators.email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.username],
            ),
            AppField(
              label: 'Password',
              controller: _password,
              password: true,
              enabled: !_busy,
              validator: Validators.required,
              onSubmitted: _submit,
              autofillHints: const [AutofillHints.password],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ForgotPasswordScreen(
                            repository: widget.repository,
                          ),
                        ),
                      ),
                child: const Text('Forgot Password?'),
              ),
            ),
            const SizedBox(height: 12),
            ErrorMessage(_error),
            PrimaryButton('Login', onPressed: _submit, loading: _busy),
          ],
        ),
      ),
    ),
  );
}
