import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_profile.dart';
import 'auth_repository.dart';

class FirebaseAuthRepository extends AuthRepository {
  FirebaseAuthRepository(this.auth, this.db) {
    _subscription = auth.authStateChanges().listen((user) {
      if (!_registering) _setUser(user);
    });
  }
  final FirebaseAuth auth;
  final FirebaseFirestore db;
  late final StreamSubscription<User?> _subscription;
  User? _user;
  bool _ready = false, _registering = false;
  @override
  bool get authReady => _ready;
  @override
  String? get uid => _user?.uid;
  @override
  String? get email => _user?.email;

  void _setUser(User? user) {
    _user = user;
    _ready = true;
    notifyListeners();
  }

  UserProfile? _decode(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    if (!snapshot.exists) return null;
    return UserProfile.fromMap(snapshot.id, snapshot.data()!);
  }

  @override
  Stream<UserProfile?> watchProfile() async* {
    final currentUid = uid!;
    final ref = db.collection('users').doc(currentUid);
    // A server read avoids routing from an absent/stale cached profile.
    yield await _validatedProfile(
      await ref.get(const GetOptions(source: Source.server)),
    );
    yield* ref.snapshots().asyncMap(_validatedProfile);
  }

  Future<UserProfile?> _validatedProfile(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final profile = _decode(doc);
    if (profile != null && profile.stallSetupComplete) {
      final stall = await db
          .collection('stalls')
          .doc(profile.stallId)
          .get(const GetOptions(source: Source.server));
      if (!stall.exists || stall.data()?['ownerUid'] != profile.uid) {
        throw const AccountException(
          'Your stall could not be verified. Please retry or contact support.',
        );
      }
    }
    return profile;
  }

  @override
  Future<void> login(String email, String password) async {
    await auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> _createProfile(
    User user,
    String name,
    String phone,
    AccountRole role,
  ) async {
    final ref = db.collection('users').doc(user.uid);
    await db.runTransaction((transaction) async {
      final existing = await transaction.get(ref);
      if (existing.exists) {
        // Idempotent recovery never overwrites an existing role or profile.
        _decode(existing);
        return;
      }
      transaction.set(ref, {
        'uid': user.uid,
        'fullName': name.trim(),
        'email': user.email!,
        'phoneNumber': phone.replaceAll(RegExp(r'[\s()\-]'), ''),
        'role': role.name,
        'createdAt': FieldValue.serverTimestamp(),
        'stallSetupComplete': false,
        'stallId': null,
      });
    });
  }

  @override
  Future<void> register({
    required String fullName,
    required String email,
    required String phoneNumber,
    required String password,
    required AccountRole role,
  }) async {
    _registering = true;
    User? created;
    try {
      created = (await auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      )).user!;
      await _createProfile(created, fullName, phoneNumber, role);
    } catch (error) {
      if (created != null) {
        // A failed acknowledgement can still mean the write committed. Keep
        // the Auth identity, sign out and let the next login verify/recover.
        try {
          await auth.signOut();
        } catch (_) {
          _setUser(auth.currentUser);
        }
        throw const AccountException(
          'Your sign-in account was created, but profile setup could not be confirmed. Sign in to finish setup.',
        );
      }
      rethrow;
    } finally {
      _registering = false;
      _setUser(auth.currentUser);
    }
  }

  @override
  Future<void> completeProfile({
    required String fullName,
    required String phoneNumber,
    required AccountRole role,
  }) async {
    final user = auth.currentUser;
    if (user == null) throw const AccountException('Please sign in again.');
    await _createProfile(user, fullName, phoneNumber, role);
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      if (e.code != 'user-not-found') rethrow;
    }
  }

  @override
  Future<void> setupStall(String name, String category, int minutes) async {
    final user = auth.currentUser;
    if (user == null) throw const AccountException('Please sign in again.');
    final profileRef = db.collection('users').doc(user.uid);
    // Firebase Auth UIDs are unique. One stall per vendor has a stable ID;
    // atomic creation and rules protect association and repeated submissions.
    final stallRef = db.collection('stalls').doc(user.uid);
    await db.runTransaction((tx) async {
      final profile = _decode(await tx.get(profileRef));
      final stall = await tx.get(stallRef);
      if (profile == null || profile.role != AccountRole.vendor) {
        throw const AccountException('A valid vendor profile is required.');
      }
      if (profile.stallSetupComplete) {
        if (!stall.exists || stall.data()?['ownerUid'] != user.uid) {
          throw const AccountException('Your stall could not be verified.');
        }
        return;
      }
      if (stall.exists) {
        throw const AccountException(
          'Please contact support to recover your stall.',
        );
      }
      tx.set(stallRef, {
        'ownerUid': user.uid,
        'name': name.trim(),
        'category': category.trim(),
        'preparationMinutes': minutes,
        'status': 'closed',
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.update(profileRef, {'stallId': user.uid, 'stallSetupComplete': true});
    });
  }

  @override
  Future<void> logout() => auth.signOut();
  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
