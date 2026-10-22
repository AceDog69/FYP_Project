import 'package:flutter/foundation.dart';
import '../models/user_profile.dart';
import '../models/vendor_stall.dart';
import 'vendor_menu_repository.dart';
import 'catalog_repository.dart';

abstract class AuthRepository extends ChangeNotifier {
  VendorMenuRepository? get menuRepository => null;
  CatalogRepository? get catalogRepository => null;
  bool get authReady;
  String? get uid;
  String? get email;
  Stream<UserProfile?> watchProfile();
  Stream<VendorStall> watchVendorStall();
  Future<void> setStallOpen(bool open);
  Future<void> updateStallSettings(StallSettings settings);
  Future<void> login(String email, String password);
  Future<void> register({
    required String fullName,
    required String email,
    required String phoneNumber,
    required String password,
    required AccountRole role,
  });
  Future<void> completeProfile({
    required String fullName,
    required String phoneNumber,
    required AccountRole role,
  });
  Future<void> sendPasswordReset(String email);
  Future<void> setupStall(String name, String category, int minutes);
  Future<void> logout();
}

class AccountException implements Exception {
  const AccountException(this.message);
  final String message;
}
