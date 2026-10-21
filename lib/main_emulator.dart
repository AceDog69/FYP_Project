// Optional debug entry point for local synthetic-data acceptance only.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'main.dart' show SmartCanteenApp;
import 'services/firebase_auth_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const host = String.fromEnvironment('EMULATOR_HOST', defaultValue: '10.0.2.2');
  if (kReleaseMode || !['10.0.2.2', '127.0.0.1', 'localhost'].contains(host)) {
    throw StateError('Use a debug build and a local Firebase emulator host.');
  }
  // A separate named app keeps validation services away from the production
  // default app. These are synthetic demo identifiers, not project credentials.
  final app = await Firebase.initializeApp(
    name: 'stage2a02-emulator',
    options: const FirebaseOptions(
      apiKey: 'demo-emulator-only',
      appId: '1:1234567890:android:0000000000000000',
      messagingSenderId: '1234567890', projectId: 'demo-smart-canteen',
    ),
  );
  final auth = FirebaseAuth.instanceFor(app: app);
  final db = FirebaseFirestore.instanceFor(app: app);
  await auth.useAuthEmulator(host, 9099);
  db.useFirestoreEmulator(host, 8080);
  db.settings = const Settings(persistenceEnabled: false);
  runApp(SmartCanteenApp(repository: FirebaseAuthRepository(auth, db)));
}
