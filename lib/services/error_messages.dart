import 'package:firebase_auth/firebase_auth.dart';
import 'auth_repository.dart';

String friendlyError(Object error) {
  if (error is AccountException) return error.message;
  if (error is FormatException) {
    return 'Your account profile needs attention. Please contact support.';
  }
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' ||
      'invalid-login-credentials' => 'The email or password is incorrect.',
      'email-already-in-use' =>
        'This email already has an account. Please sign in.',
      'weak-password' => 'Please choose a stronger password.',
      'invalid-email' => 'Please enter a valid email address.',
      'too-many-requests' => 'Too many attempts. Please try again later.',
      'network-request-failed' => 'Check your connection and try again.',
      'user-disabled' => 'This account is unavailable. Please contact support.',
      _ => 'Unable to complete this request. Please try again.',
    };
  }
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' =>
        'Your account setup could not be saved or accessed. Please contact support.',
      'unavailable' ||
      'deadline-exceeded' => 'Check your connection and try again.',
      _ => 'Unable to load or save your account. Please try again.',
    };
  }
  return 'Something went wrong. Please try again.';
}
