import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'screens/auth_gate.dart';
import 'services/auth_repository.dart';
import 'services/real_ordering_pilot.dart';
import 'theme/app_theme.dart';
import 'widgets/auth_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Android uses the existing google-services.json. No invented options.
    await Firebase.initializeApp();
    final auth = FirebaseAuth.instance;
    final db = FirebaseFirestore.instance;
    // Bind the pilot's transport explicitly before any repository starts reads.
    // Without both intentional defines, normal SDK configuration is untouched.
    if (const bool.fromEnvironment('REAL_ORDERING_PILOT', defaultValue: false) &&
        const String.fromEnvironment('REAL_ORDERING_PROJECT') == orderingPilotProject &&
        db.app.options.projectId == orderingPilotProject) {
      db.settings = const Settings(host: 'firestore.googleapis.com', sslEnabled: true);
    }
    final repository = RealOrderingPilotAuthRepository(auth, db);
    if (const bool.fromEnvironment('REAL_ORDERING_PILOT', defaultValue: false)) {
      debugPrint('Real ordering pilot: ${repository.orderRepository.canCheckout ? 'enabled' : 'disabled'}; project: ${db.app.options.projectId}');
    }
    runApp(
      SmartCanteenApp(
        repository: repository,
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
