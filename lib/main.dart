import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'screens/auth_gate.dart';
import 'services/auth_repository.dart';
import 'services/firebase_auth_repository.dart';
import 'theme/app_theme.dart';
import 'widgets/auth_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Android uses the existing google-services.json. No invented options.
    await Firebase.initializeApp();
    runApp(
      SmartCanteenApp(
        repository: FirebaseAuthRepository(
          FirebaseAuth.instance,
          FirebaseFirestore.instance,
        ),
      ),
    );
  } catch (_) {
    runApp(
      MaterialApp(
        theme: smartCanteenTheme(),
        home: const AuthLayout(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Brand(prominent: true),
              SizedBox(height: 64),
              FormHeading(
                'Unable to Start',
                'Please close the app and try again.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SmartCanteenApp extends StatelessWidget {
  const SmartCanteenApp({super.key, required this.repository});
  final AuthRepository repository;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Smart Canteen',
    debugShowCheckedModeBanner: false,
    theme: smartCanteenTheme(),
    home: AuthGate(repository: repository),
  );
}
