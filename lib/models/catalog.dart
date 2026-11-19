import 'vendor_stall.dart';
import 'vendor_menu.dart';
import 'preparation_stats.dart';

/// Minimal public listing. Private source stall fields are never copied here.
class CatalogStall {
  const CatalogStall(
    this.id,
    this.stall, {
    this.estimatedPreparationMillis,
    this.preparationStatsRevision,
    this.preparationEstimateProjectionValid = false,
  });
  final String id;
  final VendorStall stall;
  final int? estimatedPreparationMillis, preparationStatsRevision;
  final bool preparationEstimateProjectionValid;

  bool get hasVerifiedPreparationEstimate =>
      preparationEstimateProjectionValid && !stall.isCached;

  factory CatalogStall.decode(
    String id,
    Map<String, dynamic> data, {
    bool cached = false,
  }) {
    if (data['vendorUid'] != id) {
      throw const FormatException('Invalid listing owner.');
    }
    final stall = VendorStall.fromMap(id, {
      ...data,
      'ownerUid': id,
    }, isCached: cached);
    final estimate = data['estimatedPreparationMillis'];
    final revision = data['preparationStatsRevision'];
    final validProjection =
        estimate is int &&
        revision is int &&
        revision >= 0 &&
        revision <= maximumPreparationSamples &&
        (revision == 0
            ? estimate == stall.preparationMinutes * 60000
            : PreparationStats.isValidDuration(estimate));
    return CatalogStall(
      id,
      stall,
      estimatedPreparationMillis: validProjection ? estimate : null,
      preparationStatsRevision: validProjection ? revision : null,
      preparationEstimateProjectionValid: validProjection,
    );
  }
}

class CatalogSelection {
  const CatalogSelection(this.stall, this.food, this.category);
  final CatalogStall stall;
  final MenuFood food;
  final MenuCategory category;
}
