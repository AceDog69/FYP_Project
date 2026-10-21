import '../constants/predefined_pictures.dart';
import '../constants/stall_categories.dart';

/// Existing stalls remain readable without a picture ID or data migration.
class VendorStall {
  const VendorStall({
    required this.name,
    required this.category,
    required this.preparationMinutes,
    required this.isOpen,
    this.isCached = false,
    this.pictureId,
  });

  final String name, category;
  final int preparationMinutes;
  final bool isOpen, isCached;
  final String? pictureId;
  String get displayPictureId => resolvedPictureId(pictureId, category);

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
        !['open', 'closed'].contains(data['status']) ||
        (data.containsKey('pictureId') && data['pictureId'] is! String)) {
      throw const FormatException('Invalid stall information.');
    }
    // Existing category text is displayed as stored, including legacy values.
    return VendorStall(
      name: data['name'],
      category: data['category'],
      preparationMinutes: data['preparationMinutes'],
      isOpen: data['status'] == 'open',
      isCached: isCached,
      pictureId: data['pictureId'],
    );
  }
}

class StallSettings {
  StallSettings({
    required String name,
    required this.category,
    required this.preparationMinutes,
    required this.pictureId,
  }) : name = name.trim() {
    if (this.name.isEmpty || this.name.length > 100 ||
        !stallCategories.contains(category) ||
        preparationMinutes < 1 || preparationMinutes > 180 ||
        !predefinedPictures.containsKey(pictureId)) {
      throw const FormatException('Invalid stall settings.');
    }
  }
  final String name, category, pictureId;
  final int preparationMinutes;
}
