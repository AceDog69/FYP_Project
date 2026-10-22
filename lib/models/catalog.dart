import 'vendor_stall.dart';

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
