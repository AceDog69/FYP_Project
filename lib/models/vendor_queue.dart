import 'package:cloud_firestore/cloud_firestore.dart';
import 'confirmed_order.dart';

class VendorQueue {
  const VendorQueue(this.nextTicket, this.preparingCount, this.revision,
      {this.cached = false, this.schemaVersion = 2, this.legacyPreparingOrderId});
  const VendorQueue.initial({this.cached = false})
      : nextTicket = 1, preparingCount = 0, revision = 0,
        schemaVersion = 2, legacyPreparingOrderId = null;

  final int nextTicket, preparingCount, revision, schemaVersion;
  final bool cached;
  /// Present only when decoding a schema 1 cursor. It is used to verify the
  /// legacy active order before the next transaction upgrades the document.
  final String? legacyPreparingOrderId;
  bool get hasPreparingOrders => preparingCount > 0;

  factory VendorQueue.decode(String uid, Map<String, dynamic>? d, {bool cached = false}) {
    if (d == null) return VendorQueue.initial(cached: cached);
    final version = d['schemaVersion'];
    if (version == 1 && d.length == 6 && d['vendorUid'] == uid &&
        d['nextTicket'] is int && d['nextTicket'] >= 2 && d['nextTicket'] <= 2147483648 &&
        d['revision'] is int && d['revision'] >= 1 && d['updatedAt'] is Timestamp &&
        (d['preparingOrderId'] == null || (d['preparingOrderId'] is String &&
          RegExp(r'^[A-Za-z0-9]{20}$').hasMatch(d['preparingOrderId'] as String)))) {
      final legacyId = d['preparingOrderId'] as String?;
      final count = legacyId == null ? 0 : 1;
      if (d['revision'] != 2 * (d['nextTicket'] - 1) - count) {
        throw const FormatException('The preparation queue could not be verified.');
      }
      return VendorQueue(d['nextTicket'], count, d['revision'], cached: cached,
        schemaVersion: 1, legacyPreparingOrderId: legacyId);
    }
    if (version != 2 || d.length != 7 || d['vendorUid'] != uid ||
        d['nextTicket'] is! int || d['nextTicket'] < 2 || d['nextTicket'] > 2147483648 ||
        d['preparingCount'] is! int || d['preparingCount'] < 0 || d['preparingCount'] > d['nextTicket'] - 1 ||
        d['revision'] is! int || d['revision'] < 1 || d['updatedAt'] is! Timestamp ||
        d['lastTransitionOrderId'] is! String ||
        !RegExp(r'^[A-Za-z0-9]{20}$').hasMatch(d['lastTransitionOrderId'] as String) ||
        d['revision'] != 2 * (d['nextTicket'] - 1) - d['preparingCount']) {
      throw const FormatException('The preparation queue could not be verified.');
    }
    return VendorQueue(d['nextTicket'], d['preparingCount'], d['revision'], cached: cached);
  }

  bool permits(ConfirmedOrder order) {
    if (cached) return false;
    return switch (order.status) {
      // Every start must claim exactly the next never-started ticket. Existing
      // Preparing orders do not block this start.
      'Pending' => order.ticket == nextTicket,
      // Preparing -> Ready is independent for every order already started.
      'Preparing' => preparingCount > 0 && order.ticket < nextTicket,
      'Ready' => true,
      _ => false,
    };
  }
}
