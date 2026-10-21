@TestOn('browser')
library;

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_web/firebase_core_web.dart';
import 'package:firebase_auth_web/firebase_auth_web.dart';
import 'package:cloud_firestore_web/cloud_firestore_web.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fyp_app/models/user_profile.dart';
import 'package:my_fyp_app/services/auth_repository.dart';
import 'package:my_fyp_app/services/firebase_auth_repository.dart';

// Only local demo emulators; these are synthetic test values, not app config.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FirebaseAuth auth;
  late FirebaseFirestore db;
  late FirebaseAuthRepository repository;
  setUpAll(() async {
    final registrar = Registrar();
    FirebaseCoreWeb.registerWith(registrar);
    FirebaseAuthWeb.registerWith(registrar);
    FirebaseFirestoreWeb.registerWith(registrar);
    // Serve the matching official npm SDK locally to avoid CDN dependencies.
    for (final service in ['core', 'auth', 'firestore']) {
      await FirebaseCoreWeb().injectSrcScript(
        'http://127.0.0.1:9190/$service.js',
        'firebase_$service',
      );
    }
    final app = await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'demo-emulator-only',
        appId: 'demo-emulator-only',
        messagingSenderId: 'demo-emulator-only',
        projectId: 'demo-smart-canteen',
      ),
    );
    auth = FirebaseAuth.instanceFor(app: app);
    await auth.useAuthEmulator('127.0.0.1', 9099);
    db = FirebaseFirestore.instanceFor(app: app);
    db.useFirestoreEmulator('127.0.0.1', 8080);
    db.settings = const Settings(persistenceEnabled: false);
  });
  setUp(() async {
    await auth.signOut();
    repository = FirebaseAuthRepository(auth, db);
    await waitFor(() => repository.authReady);
  });
  tearDown(() async {
    repository.dispose();
    await auth.signOut();
  });

  test(
    'Dart Firebase service: student registration/login/profile/logout/reset',
    () async {
      final email =
          'dart-student-${DateTime.now().microsecondsSinceEpoch}@example.com';
      await repository.register(
        fullName: 'Student Test',
        email: email,
        phoneNumber: '0123456789',
        password: 'Password123',
        role: AccountRole.student,
      );
      expect(repository.uid, isNotNull);
      final profile = await repository.watchProfile().first;
      expect(profile!.role, AccountRole.student);
      expect(profile.email, email);
      await repository.logout();
      await waitFor(() => repository.uid == null);
      await expectLater(
        repository.login(email, 'WrongPassword123'),
        throwsA(isA<FirebaseAuthException>()),
      );
      await repository.login(email, 'Password123');
      await waitFor(() => repository.uid != null);
      expect(
        (await repository.watchProfile().first)!.role,
        AccountRole.student,
      );
      await repository.sendPasswordReset(email);
    },
  );

  test(
    'Dart Firebase service: vendor transaction is stable and survives session restoration',
    () async {
      final email =
          'dart-vendor-${DateTime.now().microsecondsSinceEpoch}@example.com';
      await repository.register(
        fullName: 'Vendor Test',
        email: email,
        phoneNumber: '0123456789',
        password: 'Password123',
        role: AccountRole.vendor,
      );
      expect(
        (await repository.watchProfile().first)!.stallSetupComplete,
        false,
      );
      final uid = repository.uid!;
      await repository.setupStall('Campus Kitchen', 'Malay', 15);
      await repository.setupStall('Should Not Replace', 'Other', 30);
      final stall = await db.collection('stalls').doc(uid).get();
      expect(stall.data()!['name'], 'Campus Kitchen');
      expect(stall.data()!['category'], 'Malay');
      expect(stall.data()!['preparationMinutes'], 15);
      expect(stall.data()!['ownerUid'], uid);
      expect(stall.data()!['status'], 'closed');
      // The real Dart dashboard listener reads the existing own-stall document
      // under unchanged rules, which deny stall collection queries.
      final dashboard = await repository.watchVendorStall().firstWhere((stall) => !stall.isCached);
      expect(dashboard.name, 'Campus Kitchen');
      expect(dashboard.category, 'Malay');
      expect(dashboard.preparationMinutes, 15);
      expect(dashboard.isOpen, false);
      final afterRead = await db.collection('stalls').doc(uid).get();
      expect(afterRead.data(), stall.data());
      repository.dispose();
      repository = FirebaseAuthRepository(auth, db);
      await waitFor(() => repository.authReady);
      final restored = await repository.watchProfile().first;
      expect(restored!.role, AccountRole.vendor);
      expect(restored.stallSetupComplete, true);
      expect(restored.stallId, uid);
      await repository.logout();
      await waitFor(() => repository.uid == null);
      await repository.login(email, 'Password123');
      await waitFor(() => repository.uid != null);
      expect((await repository.watchProfile().first)!.stallSetupComplete, true);
    },
  );

  test(
    'Dart Firebase service: partial registration is signed out and recoverable',
    () async {
      final email =
          'dart-recovery-${DateTime.now().microsecondsSinceEpoch}@example.com';
      // An invalid profile forces a real Firestore rules rejection after Auth
      // account creation; the service must not grant a role or delete identity.
      await expectLater(
        repository.register(
          fullName: '',
          email: email,
          phoneNumber: '0123456789',
          password: 'Password123',
          role: AccountRole.vendor,
        ),
        throwsA(isA<AccountException>()),
      );
      expect(repository.uid, isNull);
      await repository.login(email, 'Password123');
      await waitFor(() => repository.uid != null);
      expect(await repository.watchProfile().first, isNull);
      await repository.completeProfile(
        fullName: 'Recovered Vendor',
        phoneNumber: '0123456789',
        role: AccountRole.vendor,
      );
      expect(
        (await repository.watchProfile().first)!.stallSetupComplete,
        false,
      );
    },
  );
}

Future<void> waitFor(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw TimeoutException('Auth state did not arrive.');
}
