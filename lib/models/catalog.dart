import 'vendor_stall.dart';
import 'vendor_menu.dart';

/// Minimal public listing. Private source stall fields are never copied here.
class CatalogStall {
  const CatalogStall(this.id, this.stall);
  final String id;
  final VendorStall stall;

  factory CatalogStall.decode(String id, Map<String, dynamic> data, {bool cached = false}) {
    if (data['vendorUid'] != id) throw const FormatException('Invalid listing owner.');
    return CatalogStall(id, VendorStall.fromMap(id, {...data, 'ownerUid': id}, isCached: cached));
  }
}

class CatalogSelection {
  const CatalogSelection(this.stall, this.food, this.category);
  final CatalogStall stall;
  final MenuFood food;
  final MenuCategory category;
}
