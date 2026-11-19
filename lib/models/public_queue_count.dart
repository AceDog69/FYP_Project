import 'package:cloud_firestore/cloud_firestore.dart';

/// Sanitized authority mirror. It contains counts and a cursor, never order IDs
/// or Student identities.
Map<String, dynamic> queueCountFields(String uid, int lastTicket, int nextTicket, int preparingCount) {
  final pendingCount = lastTicket - nextTicket + 1;
  final count = pendingCount + preparingCount;
  if (uid.isEmpty || lastTicket < 0 || lastTicket > 2147483647 || nextTicket < 1 ||
      nextTicket > lastTicket + 1 || preparingCount < 0 || preparingCount > nextTicket - 1 ||
      pendingCount < 0 || count < 0 || count > lastTicket) {
    throw const FormatException('Queue count authority could not be verified.');
  }
  return {'schemaVersion': 2, 'vendorUid': uid, 'lastTicket': lastTicket,
    'nextTicket': nextTicket, 'pendingCount': pendingCount,
    'preparingCount': preparingCount, 'count': count};
}

class PublicQueueCount {
  const PublicQueueCount(this.lastTicket, this.nextTicket, this.pendingCount,
      this.preparingCount, this.count, this.updatedAt,
      {this.cached = false, this.schemaVersion = 2});
  final int lastTicket, nextTicket, pendingCount, preparingCount, count, schemaVersion;
  final bool cached;
  final Timestamp updatedAt;
  bool get hasPreparingOrders => preparingCount > 0;

  static PublicQueueCount? decode(String uid, Map<String, dynamic>? d, {bool cached = false}) {
    if (d == null) return null;
    if (d['schemaVersion'] == 1 && d.length == 7 && d['preparing'] is bool &&
        d['lastTicket'] is int && d['nextTicket'] is int && d['count'] is int &&
        d['updatedAt'] is Timestamp) {
      final oldPreparing = d['preparing'] == true ? 1 : 0;
      final fields = _legacyFields(uid, d['lastTicket'], d['nextTicket'], oldPreparing);
      if (d['vendorUid'] != uid || d['lastTicket'] != fields['lastTicket'] ||
          d['nextTicket'] != fields['nextTicket'] || d['count'] != fields['count']) {
        throw const FormatException('Queue count does not match its legacy authority fields.');
      }
      return PublicQueueCount(d['lastTicket'], d['nextTicket'], fields['pendingCount']!,
        oldPreparing, d['count'], d['updatedAt'], cached: cached, schemaVersion: 1);
    }
    if (d['schemaVersion'] != 2 || d.length != 8 || d['vendorUid'] != uid ||
        d['lastTicket'] is! int || d['nextTicket'] is! int || d['pendingCount'] is! int ||
        d['preparingCount'] is! int || d['count'] is! int || d['updatedAt'] is! Timestamp) {
      throw const FormatException('Queue count could not be verified.');
    }
    final fields = queueCountFields(uid, d['lastTicket'], d['nextTicket'], d['preparingCount']);
    if (!fields.entries.every((e) => d[e.key] == e.value)) {
      throw const FormatException('Queue count does not match its public authority fields.');
    }
    return PublicQueueCount(d['lastTicket'], d['nextTicket'], d['pendingCount'],
      d['preparingCount'], d['count'], d['updatedAt'], cached: cached);
  }

  static Map<String, dynamic> _legacyFields(String uid, int last, int next, int preparing) {
    final pending = last - next + 1;
    final count = pending + preparing;
    if (uid.isEmpty || last < 0 || next < 1 || next > last + 1 || preparing < 0 ||
        preparing > 1 || count < 0 || count > last) {
      throw const FormatException('Queue count authority could not be verified.');
    }
    return {'vendorUid': uid, 'lastTicket': last, 'nextTicket': next,
      'pendingCount': pending, 'preparingCount': preparing, 'count': count};
  }
}
