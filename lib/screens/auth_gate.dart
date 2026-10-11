import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/auth_repository.dart';
import '../services/error_messages.dart';
import '../widgets/auth_widgets.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'registration_screen.dart';
import 'stall_setup_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.repository});
  final AuthRepository repository;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: repository,
    builder: (context, _) {
      if (!repository.authReady) return const LoadingScreen();
      if (repository.uid == null) {
        // Removing the entire tree on session changes prevents back navigation
        // into another session or into authenticated screens after logout.
        return Navigator(
          key: const ValueKey('signed-out'),
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => LoginScreen(repository: repository),
          ),
        );
      }
      return ProfileGate(key: ValueKey(repository.uid), repository: repository);
    },
  );
}

class ProfileGate extends StatefulWidget {
  const ProfileGate({super.key, required this.repository});
  final AuthRepository repository;
  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  late Stream<UserProfile?> _profiles;
  bool _signingOut = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _profiles = widget.repository.watchProfile();
  }

  Future<void> _logout() async {
    if (_signingOut) return;
    setState(() {
      _signingOut = true;
      _error = null;
    });
    try {
      await widget.repository.logout();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<UserProfile?>(
    stream: _profiles,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const LoadingScreen();
      }
      if (snapshot.hasError) {
        return AuthLayout(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 80),
              const FormHeading(
                'Unable to Load Account',
                'Please retry or contact support.',
              ),
              ErrorMessage(_error ?? friendlyError(snapshot.error!)),
              PrimaryButton(
                'Retry',
                onPressed: _signingOut
                    ? null
                    : () => setState(() {
                        _profiles = widget.repository.watchProfile();
                        _error = null;
                      }),
              ),
              TextButton(
                onPressed: _signingOut ? null : _logout,
                child: const Text('Logout'),
              ),
            ],
          ),
        );
      }
      final profile = snapshot.data;
      if (profile == null) {
        return RegistrationScreen(
          repository: widget.repository,
          completingProfile: true,
        );
      }
      if (profile.role == AccountRole.vendor && !profile.stallSetupComplete) {
        return StallSetupScreen(repository: widget.repository);
      }
      return HomeScreen(profile: profile, repository: widget.repository);
    },
  );
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: SafeArea(child: Center(child: CircularProgressIndicator())),
  );
}
