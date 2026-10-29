import 'package:cloud_firestore/cloud_firestore.dart';

/// Sanitized authority mirror. No order/submission ID or Student identity.
Map<String, dynamic> queueCountFields(String uid, int lastTicket, int nextTicket, bool preparing) {
  final count = lastTicket - nextTicket + 1 + (preparing ? 1 : 0);
  if (uid.isEmpty || lastTicket < 0 || lastTicket > 2147483647 || nextTicket < 1 ||
      nextTicket > lastTicket + 1 || (preparing && nextTicket < 2) || count < 0 || count > lastTicket) {
    throw const FormatException('Queue count authority could not be verified.');
  }
  return {'schemaVersion': 1, 'vendorUid': uid, 'lastTicket': lastTicket,
    'nextTicket': nextTicket, 'preparing': preparing, 'count': count};
}

class PublicQueueCount {
  const PublicQueueCount(this.lastTicket, this.nextTicket, this.preparing, this.count, this.updatedAt, {this.cached = false});
  final int lastTicket, nextTicket, count;
  final bool preparing, cached;
  final Timestamp updatedAt;
  static PublicQueueCount? decode(String uid, Map<String, dynamic>? d, {bool cached = false}) {
    if (d == null) return null;
    if (d.length != 7 || d['schemaVersion'] is! int || d['lastTicket'] is! int || d['nextTicket'] is! int || d['count'] is! int ||
        d['preparing'] is! bool || d['updatedAt'] is! Timestamp) {
      throw const FormatException('Queue count could not be verified.');
    }
    final fields = queueCountFields(uid, d['lastTicket'], d['nextTicket'], d['preparing']);
    if (!fields.entries.every((e) => d[e.key] == e.value)) {
      throw const FormatException('Queue count does not match its public authority fields.');
    }
    return PublicQueueCount(d['lastTicket'], d['nextTicket'], d['preparing'], d['count'], d['updatedAt'], cached: cached);
  }
}
