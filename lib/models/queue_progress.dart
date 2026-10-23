import 'package:cloud_firestore/cloud_firestore.dart';
import 'confirmed_order.dart';

/// Sanitized per-stall progress. An absent document is UNKNOWN, never zero.
class QueueProgress {
  const QueueProgress(this.vendorUid, this.nextTicket, this.preparing, this.revision, this.updatedAt,
    {this.cached = false});
  const QueueProgress.unavailable(this.vendorUid, {this.cached = false})
    : nextTicket = null, preparing = false, revision = 0, updatedAt = null;
  final String vendorUid;
  final int? nextTicket;
  final bool preparing, cached;
  final int revision;
  final Timestamp? updatedAt;
  factory QueueProgress.decode(String uid, Map<String, dynamic>? d, {bool cached = false}) {
    if (d == null) return QueueProgress.unavailable(uid, cached: cached);
    if (d.length != 6 || d['schemaVersion'] != 1 || d['vendorUid'] != uid ||
        d['nextTicket'] is! int || d['nextTicket'] < 1 || d['nextTicket'] > 2147483648 ||
        d['preparing'] is! bool || d['revision'] is! int || d['revision'] < 0 ||
        d['revision'] != 2 * (d['nextTicket'] - 1) - (d['preparing'] == true ? 1 : 0) ||
        d['updatedAt'] is! Timestamp) {
      throw const FormatException('Queue progress could not be verified.');
    }
    return QueueProgress(uid, d['nextTicket'], d['preparing'], d['revision'], d['updatedAt'], cached: cached);
  }
}

class QueueEstimate {
  const QueueEstimate({this.ahead, this.minutes, this.message = '', this.overdue = false});
  final int? ahead, minutes;
  final String message;
  final bool overdue;
}

/// Time UNTIL READY. No timer, historical average or checkout/security input.
/// Uses the canonical preparation-time snapshot captured at confirmation.
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
    final ahead = order.ticket - next + (progress.preparing ? 1 : 0);
    return QueueEstimate(ahead: ahead, minutes: (ahead + 1) * order.preparationMinutes,
      message: 'Approximate time until Ready. Uses the full preparation allowance for each waiting order; elapsed time on another order is not deducted.');
  }
  if (order.status != 'Preparing' || !progress.preparing || next != order.ticket + 1 || order.preparingAt == null) {
    return const QueueEstimate(message: 'Synchronizing order status and queue progress…');
  }
  final elapsed = asOf.difference(order.preparingAt!.toDate()).inMilliseconds;
  final remaining = order.preparationMinutes * 60000 - (elapsed < 0 ? 0 : elapsed);
  if (remaining <= 0) {
    return const QueueEstimate(ahead: 0, overdue: true,
      message: 'Preparation is taking longer than the initial estimate. Ready time is currently unknown.');
  }
  return QueueEstimate(ahead: 0, minutes: (remaining + 59999) ~/ 60000,
    message: 'Approximate time until Ready, checked on this update using the device clock. It is not a countdown or guaranteed completion time.');
}
