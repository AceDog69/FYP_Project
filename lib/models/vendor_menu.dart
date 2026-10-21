import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/predefined_pictures.dart';

String categoryName(String value) => value.trim().replaceAll(RegExp(r'\s+'), ' ');
String? categoryError(String? value) {
  final n = categoryName(value ?? '');
  return n.isEmpty || n.length > 50 || n.contains('/') ||
      n == '.' || n == '..' || RegExp(r'^__.*__$').hasMatch(n)
      ? 'Use 1–50 characters; no slash or reserved document names.' : null;
}

int? parsePriceSen(String input) {
  final v = input.trim();
  if (!RegExp(r'^(0|[1-9][0-9]{0,3})(\.[0-9]{1,2})?$').hasMatch(v)) return null;
  final parts = v.split('.');
  final sen = int.parse(parts[0]) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
  return sen >= 1 && sen <= 100000 ? sen : null;
}
String rm(int sen) => 'RM ${sen ~/ 100}.${(sen % 100).toString().padLeft(2, '0')}';

class MenuData<T> {
  const MenuData(this.items, {this.cached = false});
  final List<T> items;
  final bool cached;
}

class MenuCategory {
  const MenuCategory(this.id, this.name, this.revision);
  final String id, name;
  final int revision;
  factory MenuCategory.decode(String uid, String id, Map<String, dynamic> d) {
    if (d['vendorUid'] != uid || d['name'] is! String || categoryError(d['name']) != null ||
        d['nameKey'] != (d['name'] as String).toLowerCase() ||
        d['revision'] is! int || d['revision'] < 1 ||
        d['createdAt'] is! Timestamp || d['updatedAt'] is! Timestamp) {
      throw const FormatException('Invalid menu category.');
    }
    return MenuCategory(id, d['name'], d['revision']);
  }
}

class FoodDraft {
  FoodDraft({required String name, required String description,
    required this.priceSen, required this.categoryId, required this.pictureId,
    required this.available}) : name = name.trim(), description = description.trim() {
    if (this.name.isEmpty || this.name.length > 100 || this.description.isEmpty ||
        this.description.length > 500 || priceSen < 1 || priceSen > 100000 ||
        categoryId.isEmpty || categoryId.contains('/') ||
        !predefinedPictures.containsKey(pictureId)) {
      throw const FormatException('Check food details, category, price and picture.');
    }
  }
  final String name, description, categoryId, pictureId;
  final int priceSen;
  final bool available;
  Map<String, dynamic> get fields => {'name': name, 'description': description,
    'priceSen': priceSen, 'categoryId': categoryId, 'pictureId': pictureId, 'available': available};
}

class MenuFood {
  const MenuFood(this.id, this.draft, this.revision);
  final String id;
  final FoodDraft draft;
  final int revision;
  factory MenuFood.decode(String uid, String id, Map<String, dynamic> d) {
    if (d['vendorUid'] != uid || d['revision'] is! int || d['revision'] < 1 ||
        d['createdAt'] is! Timestamp || d['updatedAt'] is! Timestamp ||
        d['name'] is! String || d['description'] is! String || d['priceSen'] is! int ||
        d['categoryId'] is! String || d['pictureId'] is! String || d['available'] is! bool) {
      throw const FormatException('Invalid food item.');
    }
    return MenuFood(id, FoodDraft(name: d['name'], description: d['description'],
      priceSen: d['priceSen'], categoryId: d['categoryId'], pictureId: d['pictureId'],
      available: d['available']), d['revision']);
  }
}
