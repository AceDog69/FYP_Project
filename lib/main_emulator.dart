// Optional debug entry point for local synthetic-data acceptance only.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'main.dart' show SmartCanteenApp;
import 'services/firebase_auth_repository.dart';
import 'services/emulator_checkout_policy.dart';
import 'services/order_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const host = String.fromEnvironment('EMULATOR_HOST', defaultValue: '10.0.2.2');
  const checkoutFlag = bool.fromEnvironment('EMULATOR_CHECKOUT', defaultValue: false);
  if (!kDebugMode || !['10.0.2.2', '127.0.0.1', 'localhost'].contains(host)) {
    throw StateError('Use a debug build and a local Firebase emulator host.');
  }
  // A separate named app keeps validation services away from the production
  // default app. These are synthetic demo identifiers, not project credentials.
  final app = await Firebase.initializeApp(
    name: checkoutDemoAppName,
    options: const FirebaseOptions(
      apiKey: checkoutDemoApiKey,
      appId: checkoutDemoAppId,
      messagingSenderId: '1234567890', projectId: checkoutDemoProject,
    ),
  );
  final auth = FirebaseAuth.instanceFor(app: app);
  final db = FirebaseFirestore.instanceFor(app: app);
  await auth.useAuthEmulator(host, 9099);
  db.useFirestoreEmulator(host, 8080);
  db.settings = const Settings(persistenceEnabled: false);
  // The private repository is created only here, after both services have been
  // routed to emulators. Ordinary main.dart retains the disabled repository.
  final repository = _DemoAuthRepository(auth, db, flagEnabled: checkoutFlag);
  debugPrint('Local demo checkout: ${repository.orderRepository.canCheckout ? 'enabled' : 'disabled'}');
  runApp(SmartCanteenApp(repository: repository));
}

class _DemoAuthRepository extends FirebaseAuthRepository {
  _DemoAuthRepository(super.auth, super.db, {required this.flagEnabled});
  final bool flagEnabled;
  late final OrderRepository _demoOrders = _DemoCheckoutRepository(db, () => uid,
    flagEnabled: flagEnabled, emulatorsConnected: true);

  @override
  OrderRepository get orderRepository => _demoOrders;
}

class _DemoCheckoutRepository extends FirebaseOrderRepository {
  _DemoCheckoutRepository(super.db, super.currentUid, {
    required this.flagEnabled, required this.emulatorsConnected,
  });
  final bool flagEnabled, emulatorsConnected;

  @override
  bool get canProcessOrders => canCheckout;
  @override
  bool get usesPublicQueueCounts => canCheckout && const bool.fromEnvironment('STAGE4B_QUEUE_COUNTS', defaultValue: false);

  @override
  bool get canCheckout => emulatorCheckoutAllowed(
    debugMode: kDebugMode,
    emulatorEntryPoint: true,
    flagEnabled: flagEnabled,
    emulatorsConnected: emulatorsConnected,
    appName: db.app.name,
    projectId: db.app.options.projectId,
    apiKey: db.app.options.apiKey,
    appId: db.app.options.appId,
    firestoreHost: db.settings.host,
    sslEnabled: db.settings.sslEnabled,
  );
}
