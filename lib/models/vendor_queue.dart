import 'package:cloud_firestore/cloud_firestore.dart';
import 'confirmed_order.dart';

class VendorQueue {
  const VendorQueue(this.nextTicket, this.preparingOrderId, this.revision, {this.cached = false});
  const VendorQueue.initial({this.cached = false}) : nextTicket = 1, preparingOrderId = null, revision = 0;
  final int nextTicket, revision;
  final String? preparingOrderId;
  final bool cached;
  factory VendorQueue.decode(String uid, Map<String, dynamic>? d, {bool cached = false}) {
    if (d == null) {
      return VendorQueue.initial(cached: cached);
    }
    if (d.length != 6 || d['schemaVersion'] != 1 || d['vendorUid'] != uid ||
        d['nextTicket'] is! int || d['nextTicket'] < 2 || d['nextTicket'] > 2147483648 ||
        d['revision'] is! int || d['revision'] < 1 || d['updatedAt'] is! Timestamp ||
        (d['preparingOrderId'] != null && (d['preparingOrderId'] is! String ||
          !RegExp(r'^[A-Za-z0-9]{20}$').hasMatch(d['preparingOrderId'] as String)))) {
      throw const FormatException('The preparation queue could not be verified.');
    }
    return VendorQueue(d['nextTicket'], d['preparingOrderId'], d['revision'], cached: cached);
  }
  bool permits(ConfirmedOrder order) {
    if (cached) {
      return false;
    }
    return switch (order.status) {
      'Pending' => preparingOrderId == null && order.ticket == nextTicket,
      'Preparing' => preparingOrderId == order.id,
      'Ready' => true,
      _ => false,
    };
  }
}
