/// Read-only view of existing Stage 1 stall fields. No migration is required.
class VendorStall {
  const VendorStall({
    required this.name,
    required this.category,
    required this.preparationMinutes,
    required this.isOpen,
    this.isCached = false,
  });

  final String name, category;
  final int preparationMinutes;
  final bool isOpen, isCached;

  factory VendorStall.fromMap(
    String vendorUid,
    Map<String, dynamic> data, {
    bool isCached = false,
  }) {
    if (data['ownerUid'] != vendorUid ||
        data['name'] is! String ||
        (data['name'] as String).trim().isEmpty ||
        (data['name'] as String).length > 100 ||
        data['category'] is! String ||
        (data['category'] as String).trim().isEmpty ||
        data['preparationMinutes'] is! int ||
        (data['preparationMinutes'] as int) < 1 ||
        (data['preparationMinutes'] as int) > 180 ||
        !['open', 'closed'].contains(data['status'])) {
      throw const FormatException('Invalid stall information.');
    }
    // Existing category text is displayed as stored, including legacy values.
    return VendorStall(
      name: data['name'],
      category: data['category'],
      preparationMinutes: data['preparationMinutes'],
      isOpen: data['status'] == 'open',
      isCached: isCached,
    );
  }
}
