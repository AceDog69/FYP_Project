class Validators {
  static String? required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;
  static String? email(String? value) {
    if (required(value) != null) return 'Please enter your email address.';
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value!.trim())
        ? null
        : 'Please enter a valid email address.';
  }

  static String? name(String? value) =>
      required(value) ??
      (value!.trim().length > 100 ? 'Use 100 characters or fewer.' : null);
  static String? phone(String? value) {
    if (required(value) != null) return 'Please enter your phone number.';
    final normalized = value!.replaceAll(RegExp(r'[\s()\-]'), '');
    return RegExp(r'^\+?[0-9]{8,15}$').hasMatch(normalized)
        ? null
        : 'Enter a valid phone number (8–15 digits).';
  }

  static String? password(String? value) {
    if (required(value) != null) return 'Please enter a password.';
    return value!.length >= 8 &&
            RegExp(r'[a-z]').hasMatch(value) &&
            RegExp(r'[A-Z]').hasMatch(value) &&
            RegExp(r'[0-9]').hasMatch(value)
        ? null
        : 'Use at least 8 characters, uppercase, lowercase and a number.';
  }

  static String? minutes(String? value) {
    final n = int.tryParse(value?.trim() ?? '');
    return n != null && n >= 1 && n <= 180 ? null : 'Enter 1–180 minutes.';
  }
}
