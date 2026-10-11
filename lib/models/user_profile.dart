enum AccountRole { student, vendor }

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.fullName,
    required this.email,
    required this.phoneNumber,
    required this.role,
    this.stallSetupComplete = false,
    this.stallId,
  });

  final String uid, fullName, email, phoneNumber;
  final AccountRole role;
  final bool stallSetupComplete;
  final String? stallId;

  factory UserProfile.fromMap(String uid, Map<String, dynamic> data) {
    final role = switch (data['role']) {
      'student' => AccountRole.student,
      'vendor' => AccountRole.vendor,
      _ => throw const FormatException('Invalid account role.'),
    };
    if (data['uid'] != uid ||
        ['fullName', 'email', 'phoneNumber'].any(
          (key) => data[key] is! String || (data[key] as String).trim().isEmpty,
        ) ||
        data['stallSetupComplete'] is! bool ||
        (data['stallSetupComplete'] == true &&
            (role != AccountRole.vendor || data['stallId'] != uid)) ||
        (data['stallSetupComplete'] == false && data['stallId'] != null)) {
      throw const FormatException('Account profile is incomplete or invalid.');
    }
    return UserProfile(
      uid: uid,
      fullName: data['fullName'],
      email: data['email'],
      phoneNumber: data['phoneNumber'],
      role: role,
      stallSetupComplete: data['stallSetupComplete'],
      stallId: data['stallId'],
    );
  }
}
