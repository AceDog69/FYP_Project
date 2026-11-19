import 'package:cloud_firestore/cloud_firestore.dart';
import 'confirmed_order.dart';
import 'preparation_stats.dart';

/// Sanitized per-stall progress. An absent document is UNKNOWN, never zero.
class QueueProgress {
  const QueueProgress(this.vendorUid, this.nextTicket, this.preparingCount, this.revision, this.updatedAt,
      {this.cached = false, this.schemaVersion = 2})
      : assert(preparingCount >= 0);
  const QueueProgress.unavailable(this.vendorUid, {this.cached = false})
      : nextTicket = null, preparingCount = 0, revision = 0, updatedAt = null, schemaVersion = 2;

  final String vendorUid;
  final int? nextTicket;
  final int preparingCount, revision, schemaVersion;
  final bool cached;
  final Timestamp? updatedAt;
  bool get hasPreparingOrders => preparingCount > 0;

  factory QueueProgress.decode(String uid, Map<String, dynamic>? d, {bool cached = false}) {
    if (d == null) return QueueProgress.unavailable(uid, cached: cached);
    final version = d['schemaVersion'];
    final old = version == 1 && d.length == 6 && d['preparing'] is bool;
    final preparingCount = old ? (d['preparing'] == true ? 1 : 0) : d['preparingCount'];
    if ((!old && (version != 2 || d.length != 6 || preparingCount is! int || preparingCount < 0)) ||
        d['vendorUid'] != uid || d['nextTicket'] is! int || d['nextTicket'] < 1 ||
        d['nextTicket'] > 2147483648 || preparingCount > d['nextTicket'] - 1 ||
        d['revision'] is! int || d['revision'] < 0 ||
        d['revision'] != 2 * (d['nextTicket'] - 1) - preparingCount || d['updatedAt'] is! Timestamp) {
      throw const FormatException('Queue progress could not be verified.');
    }
    return QueueProgress(uid, d['nextTicket'], preparingCount as int, d['revision'], d['updatedAt'],
      cached: cached, schemaVersion: old ? 1 : 2);
  }
}

class QueueEstimate {
  const QueueEstimate({this.ahead, this.minutes, this.message = '', this.overdue = false});
  final int? ahead, minutes;
  final String message;
  final bool overdue;
}

/// Pending has an exact sequence position but no numerical ETA while earlier
/// work may be prepared in parallel. Preparing uses its frozen order estimate.
QueueEstimate estimateQueue(ConfirmedOrder order, QueueProgress? progress, DateTime asOf) {
  if (order.status == 'Ready' || order.status == 'Completed') {
    return QueueEstimate(ahead: 0, message: order.status == 'Ready'
      ? 'Ready for pickup. Collect your order at the stall.' : 'Collected and completed. This ticket is no longer waiting.');
  }
  if (progress == null || progress.nextTicket == null || progress.vendorUid != order.vendorUid) {
    return const QueueEstimate(message: 'Queue progress is unavailable until the Vendor connects. No position or ETA is assumed.');
  }
  if (progress.cached) {
    return const QueueEstimate(message: 'Queue progress is cached. Reconnect to verify position and ETA.');
  }
  final next = progress.nextTicket!;
  if (order.status == 'Pending') {
    if (order.ticket < next) {
      return const QueueEstimate(message: 'Synchronizing order status and queue progress…');
    }
    return QueueEstimate(ahead: order.ticket - next,
      message: 'Waiting for preparation to begin.');
  }
  if (order.status != 'Preparing' || progress.preparingCount == 0 || next <= order.ticket || order.preparingAt == null) {
    return const QueueEstimate(message: 'Synchronizing order status and queue progress…');
  }
  final elapsed = asOf.difference(order.preparingAt!.toDate()).inMilliseconds;
  final baseline = order.preparationEstimateMillis ??
      PreparationStats.estimateMillis(initialPreparationMinutes: order.preparationMinutes);
  final remaining = baseline - (elapsed < 0 ? 0 : elapsed);
  if (remaining <= 0) {
    return const QueueEstimate(ahead: 0, overdue: true,
      message: 'The preparation estimate has elapsed. Ready time is currently unknown.');
  }
  return QueueEstimate(ahead: 0, minutes: (remaining + 59999) ~/ 60000,
    message: 'Approximate time until Ready, checked on this update using the device clock. It is not a countdown or guaranteed completion time.');
}
