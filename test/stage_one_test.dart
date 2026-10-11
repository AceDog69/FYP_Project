import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fyp_app/main.dart';
import 'package:my_fyp_app/models/user_profile.dart';
import 'package:my_fyp_app/services/auth_repository.dart';
import 'package:my_fyp_app/services/validators.dart';
import 'package:my_fyp_app/widgets/auth_widgets.dart';

UserProfile profile(AccountRole role, {bool setup = false}) => UserProfile(
  uid: 'test-user',
  fullName: 'Alex Lee',
  email: 'alex@example.com',
  phoneNumber: '0123456789',
  role: role,
  stallSetupComplete: setup,
  stallId: setup ? 'test-user' : null,
);

// UI tests use an explicit test double. Firebase/rules are tested separately
// against local emulators, never against the production project.
class TestRepository extends AuthRepository {
  bool ready = true;
  String? currentUid;
  UserProfile? currentProfile, nextProfile;
  Object? loginError, profileError, stallError;
  Completer<void>? pendingLogin, pendingRegistration;
  int loginCalls = 0, registerCalls = 0, resetCalls = 0, setupCalls = 0;
  AccountRole? registeredRole;
  final profiles = StreamController<UserProfile?>.broadcast();
  @override
  bool get authReady => ready;
  @override
  String? get uid => currentUid;
  @override
  String? get email => 'alex@example.com';
  @override
  Stream<UserProfile?> watchProfile() async* {
    if (profileError != null) throw profileError!;
    yield currentProfile;
    yield* profiles.stream;
  }

  void session(UserProfile? value) {
    currentProfile = value;
    currentUid = 'test-user';
    notifyListeners();
  }

  @override
  Future<void> login(String email, String password) async {
    loginCalls++;
    if (pendingLogin != null) await pendingLogin!.future;
    if (loginError != null) throw loginError!;
    session(nextProfile ?? profile(AccountRole.student));
  }

  @override
  Future<void> register({
    required String fullName,
    required String email,
    required String phoneNumber,
    required String password,
    required AccountRole role,
  }) async {
    registerCalls++;
    registeredRole = role;
    if (pendingRegistration != null) await pendingRegistration!.future;
    session(profile(role));
  }

  @override
  Future<void> completeProfile({
    required String fullName,
    required String phoneNumber,
    required AccountRole role,
  }) async {
    currentProfile = profile(role);
    profiles.add(currentProfile);
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    resetCalls++;
  }

  @override
  Future<void> setupStall(String name, String category, int minutes) async {
    setupCalls++;
    if (stallError != null) throw stallError!;
    currentProfile = profile(AccountRole.vendor, setup: true);
    profiles.add(currentProfile);
  }

  @override
  Future<void> logout() async {
    currentUid = null;
    notifyListeners();
  }

  @override
  void dispose() {
    profiles.close();
    super.dispose();
  }
}

Finder field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is AppField && w.label == label),
  matching: find.byType(TextFormField),
);
Future<void> fill(WidgetTester tester, String label, String value) async {
  await tester.ensureVisible(field(label));
  await tester.enterText(field(label), value);
}

Future<void> tap(WidgetTester tester, String label) async {
  final target = find.text(label).last;
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> launch(WidgetTester tester, TestRepository repo) async {
  tester.view.reset();
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(SmartCanteenApp(repository: repo));
  await tester.pumpAndSettle();
}

void main() {
  test('validation rejects invalid email, phone, password and prep time', () {
    expect(Validators.email('bad'), isNotNull);
    expect(Validators.email('a@example.com'), isNull);
    expect(Validators.phone('abc123'), isNotNull);
    expect(Validators.phone('+65 9123 4567'), isNull);
    expect(Validators.password('password'), isNotNull);
    expect(Validators.password('Password123'), isNull);
    for (final value in ['0', '181', 'abc']) {
      expect(Validators.minutes(value), isNotNull);
    }
  });

  test('invalid roles and mismatched UID/stall associations are rejected', () {
    final data = {
      'uid': 'u',
      'fullName': 'Alex',
      'email': 'a@example.com',
      'phoneNumber': '12345678',
      'role': 'student',
      'stallSetupComplete': false,
      'stallId': null,
    };
    expect(UserProfile.fromMap('u', data).role, AccountRole.student);
    expect(() => UserProfile.fromMap('other', data), throwsFormatException);
    expect(
      () => UserProfile.fromMap('u', {...data, 'role': 'admin'}),
      throwsFormatException,
    );
    expect(
      () => UserProfile.fromMap('u', {
        ...data,
        'role': 'vendor',
        'stallSetupComplete': true,
        'stallId': 'someone-else',
      }),
      throwsFormatException,
    );
  });

  testWidgets('Login shows larger branding, validates and toggles visibility', (
    tester,
  ) async {
    final repo = TestRepository();
    addTearDown(repo.dispose);
    await launch(tester, repo);
    expect(tester.widget<Brand>(find.byType(Brand)).prominent, isTrue);
    expect(find.text('Select Role'), findsNothing);
    await tap(tester, 'Login');
    expect(repo.loginCalls, 0);
    expect(find.text('Please enter your email address.'), findsOneWidget);
    await fill(tester, 'Password', 'Password123');
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: field('Password'),
              matching: find.byType(TextField),
            ),
          )
          .obscureText,
      isTrue,
    );
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: field('Password'),
              matching: find.byType(TextField),
            ),
          )
          .obscureText,
      isFalse,
    );
  });

  testWidgets('incorrect credentials show a friendly error without login', (
    tester,
  ) async {
    final repo = TestRepository()
      ..loginError = FirebaseAuthException(code: 'invalid-credential');
    addTearDown(repo.dispose);
    await launch(tester, repo);
    await fill(tester, 'Email Address', 'alex@example.com');
    await fill(tester, 'Password', 'wrong');
    await tap(tester, 'Login');
    expect(find.text('The email or password is incorrect.'), findsOneWidget);
    expect(find.text('Welcome, Student'), findsNothing);
  });

  testWidgets('Login disables repeated requests while pending', (tester) async {
    final repo = TestRepository()..pendingLogin = Completer<void>();
    addTearDown(repo.dispose);
    await launch(tester, repo);
    await fill(tester, 'Email Address', 'alex@example.com');
    await fill(tester, 'Password', 'Password123');
    await tester.tap(find.text('Login'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(repo.loginCalls, 1);
    repo.pendingLogin!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Welcome, Student'), findsOneWidget);
  });

  testWidgets(
    'student registers, switches five tabs, logs out and cannot go back',
    (tester) async {
      final repo = TestRepository();
      addTearDown(repo.dispose);
      await launch(tester, repo);
      await tester.tap(find.textContaining("Don't have an account?"));
      await tester.pumpAndSettle();
      await fill(tester, 'Full Name', 'Alex Lee');
      await fill(tester, 'Email Address', 'alex@example.com');
      await fill(tester, 'Phone Number', '0123456789');
      await fill(tester, 'Password', 'Password123');
      await fill(tester, 'Confirm Password', 'Password123');
      await tap(tester, 'Create Account');
      expect(repo.registeredRole, AccountRole.student);
      expect(find.text('Welcome, Student'), findsOneWidget);
      expect(
        tester
            .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
            .items
            .length,
        5,
      );
      for (final label in ['Orders', 'Cart', 'Queue']) {
        await tap(tester, label);
        expect(find.text('Coming soon'), findsOneWidget);
      }
      await tap(tester, 'Profile');
      expect(find.text('alex@example.com'), findsOneWidget);
      await tap(tester, 'Logout');
      expect(find.text('Welcome Back'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Welcome, Student'), findsNothing);
    },
  );

  testWidgets(
    'vendor registration requires setup and then has only four tabs',
    (tester) async {
      final repo = TestRepository();
      addTearDown(repo.dispose);
      await launch(tester, repo);
      await tester.tap(find.textContaining("Don't have an account?"));
      await tester.pumpAndSettle();
      await fill(tester, 'Full Name', 'Alex Lee');
      await fill(tester, 'Email Address', 'alex@example.com');
      await fill(tester, 'Phone Number', '0123456789');
      await fill(tester, 'Password', 'Password123');
      await fill(tester, 'Confirm Password', 'Password123');
      await tap(tester, 'Vendor');
      await tap(tester, 'Create Account');
      expect(repo.registeredRole, AccountRole.vendor);
      expect(find.text('Set Up Your Stall'), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
      await fill(tester, 'Stall Name', 'Campus Kitchen');
      await fill(tester, 'Food Category', 'Rice');
      await tap(tester, 'Complete Stall Setup');
      expect(find.text('Welcome, Vendor'), findsOneWidget);
      expect(
        tester
            .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
            .items
            .length,
        4,
      );
      expect(find.text('Cart'), findsNothing);
      expect(find.text('Queue'), findsNothing);
      await tap(tester, 'Menu');
      expect(find.text('Coming soon'), findsOneWidget);
      await tap(tester, 'Profile');
      await tap(tester, 'Logout');
      repo.nextProfile = repo.currentProfile;
      await fill(tester, 'Email Address', 'alex@example.com');
      await fill(tester, 'Password', 'Password123');
      await tap(tester, 'Login');
      expect(find.text('Welcome, Vendor'), findsOneWidget);
      expect(find.text('Set Up Your Stall'), findsNothing);
    },
  );

  testWidgets('stall failures keep an unconfigured vendor on setup', (
    tester,
  ) async {
    final repo = TestRepository()
      ..stallError = const AccountException('Could not save stall.');
    repo.session(profile(AccountRole.vendor));
    addTearDown(repo.dispose);
    await launch(tester, repo);
    await fill(tester, 'Stall Name', 'Campus Kitchen');
    await fill(tester, 'Food Category', 'Rice');
    await tap(tester, 'Complete Stall Setup');
    expect(find.text('Could not save stall.'), findsOneWidget);
    expect(find.text('Welcome, Vendor'), findsNothing);
  });

  testWidgets(
    'password reset validates and retains separate confirmation screen',
    (tester) async {
      final repo = TestRepository();
      addTearDown(repo.dispose);
      await launch(tester, repo);
      await tap(tester, 'Forgot Password?');
      await tap(tester, 'Send Reset Link');
      expect(repo.resetCalls, 0);
      await fill(tester, 'Email Address', 'alex@example.com');
      await tap(tester, 'Send Reset Link');
      expect(repo.resetCalls, 1);
      expect(find.text('Check Your Email'), findsOneWidget);
      expect(find.textContaining('If an account exists'), findsOneWidget);
      await tap(tester, 'Back to Login');
      expect(find.text('Welcome Back'), findsOneWidget);
    },
  );

  testWidgets('restored vendor session routes directly to its dashboard', (
    tester,
  ) async {
    final repo = TestRepository();
    repo.session(profile(AccountRole.vendor, setup: true));
    addTearDown(repo.dispose);
    await launch(tester, repo);
    expect(find.text('Welcome, Vendor'), findsOneWidget);
    expect(find.text('Welcome Back'), findsNothing);
    expect(find.text('Welcome, Student'), findsNothing);
  });

  testWidgets(
    'missing profiles require completion; errors never grant a role',
    (tester) async {
      final repo = TestRepository();
      repo.session(null);
      addTearDown(repo.dispose);
      await launch(tester, repo);
      expect(find.text('Complete Your Account'), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
      await fill(tester, 'Full Name', 'Alex Lee');
      await fill(tester, 'Phone Number', '0123456789');
      await tap(tester, 'Complete Account');
      expect(find.text('Welcome, Student'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      repo.profileError = const FormatException('Invalid role');
      await launch(tester, repo);
      expect(find.text('Unable to Load Account'), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
    },
  );

  testWidgets(
    'Login and registration remain scrollable on small keyboard-open phones',
    (tester) async {
      final repo = TestRepository();
      addTearDown(repo.dispose);
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(SmartCanteenApp(repository: repo));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.textContaining("Don't have an account?"));
      await tester.tap(find.textContaining("Don't have an account?"));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Create Account').last);
      expect(tester.takeException(), isNull);
    },
  );
}
