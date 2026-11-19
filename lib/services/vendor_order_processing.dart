import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/confirmed_order.dart';
import '../models/vendor_queue.dart';
import '../models/queue_progress.dart';
import '../models/public_queue_count.dart';
import '../models/preparation_stats.dart';
import 'auth_repository.dart';

// Separate from the accepted checkout protocol: this service never writes an
// order snapshot, checkout request, item, payment or ticket counter.
class VendorOrderProcessing {
  VendorOrderProcessing(this.db, this.currentUid, this.enabled, {bool Function()? publicQueueCounts})
      : publicQueueCounts = publicQueueCounts ?? _disabled;
  static bool _disabled() => false;
  final bool Function() publicQueueCounts;
  final FirebaseFirestore db;
  final String? Function() currentUid;
  final bool Function() enabled;
  bool _busy = false;
  Future<void> _sampleQueue = Future<void>.value();
  String get _uid => currentUid() ?? (throw const AccountException('Please sign in again.'));
  DocumentReference<Map<String, dynamic>> _queue(String uid) => db.collection('vendorQueues').doc(uid);
  DocumentReference<Map<String, dynamic>> _preparationStats(String uid) =>
      db.collection('vendorPreparationStats').doc(uid);

  void _guard(String uid) {
    if (!enabled() || _uid != uid) {
      throw const AccountException('Order processing requires the local emulator demo and the same Vendor session.');
    }
  }

  Stream<VendorQueue> watch() async* {
    final uid = _uid;
    var published = false;
    await for (final s in _queue(uid).snapshots(includeMetadataChanges: true)) {
      if (_uid != uid) throw const AccountException('Your Vendor session changed.');
      if (s.metadata.hasPendingWrites) continue;
      if (!s.metadata.isFromCache && !published && enabled()) {
        await _publishMissingProgress(uid);
        if (publicQueueCounts()) await initializeQueueCount();
        published = true;
      }
      yield VendorQueue.decode(uid, s.data(), cached: s.metadata.isFromCache);
    }
  }

  /// Owning Vendor only; counts are verified against ticket authority and the
  /// bounded cursor. Legacy one-slot records are read without changing history.
  Future<void> initializeQueueCount() async {
    final uid = _uid;
    _guard(uid);
    if (!publicQueueCounts()) return;
    await db.runTransaction<void>((tx) async {
      final cursor = await tx.get(_queue(uid));
      final counter = await tx.get(db.collection('checkoutCounters').doc(uid));
      final ref = db.collection('stallQueueCounts').doc(uid);
      final summary = await tx.get(ref);
      final queue = VendorQueue.decode(uid, cursor.data());
      var last = 0;
      if (counter.exists) {
        final c = counter.data()!;
        if (c.length != 5 || c['schemaVersion'] != 1 || c['vendorUid'] != uid || c['lastTicket'] is! int ||
            c['lastTicket'] < 1 || c['lastOrderId'] is! String || c['updatedAt'] is! Timestamp) {
          throw const AccountException('Ticket authority is malformed; no automatic repair was attempted.');
        }
        final order = await tx.get(db.collection('orders').doc(c['lastOrderId'] as String));
        if (order.data()?['vendorUid'] != uid || order.data()?['ticket'] != c['lastTicket'] ||
            order.data()?['orderId'] != c['lastOrderId'] || !orderStatuses.contains(order.data()?['status'])) {
          throw const AccountException('The last confirmed ticket could not be verified.');
        }
        last = c['lastTicket'] as int;
      }
      if (cursor.exists && queue.revision != 2 * (queue.nextTicket - 1) - queue.preparingCount) {
        throw const AccountException('Queue revision could not be verified.');
      }
      if (queue.legacyPreparingOrderId case final legacyId?) {
        final preparing = await tx.get(db.collection('orders').doc(legacyId));
        if (preparing.data()?['vendorUid'] != uid || preparing.data()?['status'] != 'Preparing' ||
            preparing.data()?['ticket'] != queue.nextTicket - 1) {
          throw const AccountException('The legacy Preparing ticket could not be verified.');
        }
      }
      _guard(uid);
      final fields = queueCountFields(uid, last, queue.nextTicket, queue.preparingCount);
      PublicQueueCount? existing;
      try {
        existing = PublicQueueCount.decode(uid, summary.data());
      } on FormatException {
        existing = null; // Repair only the public mirror, never its authority.
      }
      if (existing != null && fields.entries.every((e) => summary.data()?[e.key] == e.value)) return;
      tx.set(ref, {...fields, 'updatedAt': FieldValue.serverTimestamp()});
    }, maxAttempts: 8);
    _guard(uid);
  }

  Future<void> _transition(
    Future<void> Function(Transaction, void Function(int?, int)) action,
  ) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      int? observedLastTicket, observedQueueRevision;
      try {
        await db.runTransaction<void>((tx) {
          observedLastTicket = null;
          observedQueueRevision = null;
          return action(tx, (lastTicket, queueRevision) {
            observedLastTicket = lastTicket;
            observedQueueRevision = queueRevision;
          });
        }, maxAttempts: 8);
        return;
      } on FirebaseException catch (error) {
        final observedRevision = observedQueueRevision;
        if (error.code != 'permission-denied' || observedRevision == null || attempt == 4) rethrow;
        final uid = _uid;
        _guard(uid);
        final cursor = await _queue(uid).get(const GetOptions(source: Source.server));
        _guard(uid);
        if (cursor.metadata.hasPendingWrites || !cursor.exists) rethrow;
        final currentQueue = VendorQueue.decode(uid, cursor.data());
        var advanced = currentQueue.revision > observedRevision;
        if (publicQueueCounts() && observedLastTicket != null) {
          final current = await db.collection('stallQueueCounts').doc(uid)
              .get(const GetOptions(source: Source.server));
          _guard(uid);
          final count = PublicQueueCount.decode(uid, current.data());
          advanced = advanced || (!current.metadata.hasPendingWrites && count != null &&
              count.lastTicket > observedLastTicket!);
        }
        if (!advanced) rethrow;
        // The server cursor (or enabled ticket mirror) proves another operation
        // committed since this transaction read it. Retry the full guarded
        // transaction against fresh state; stale orders still fail its checks.
      }
    }
  }

  Future<void> _publishMissingProgress(String uid) async {
    _guard(uid);
    await db.runTransaction<void>((tx) async {
      final cursor = await tx.get(_queue(uid));
      final target = db.collection('queueProgress').doc(uid);
      final progress = await tx.get(target);
      _guard(uid);
      final queue = VendorQueue.decode(uid, cursor.data());
      if (progress.exists) {
        final existing = QueueProgress.decode(uid, progress.data());
        if (existing.nextTicket != queue.nextTicket || existing.preparingCount != queue.preparingCount ||
            existing.revision != queue.revision ||
            (cursor.exists && existing.updatedAt != cursor.data()!['updatedAt'])) {
          throw const AccountException('Queue progress does not match the preparation cursor. Review server data.');
        }
        return;
      }
      tx.set(target, queue.schemaVersion == 1
          ? {'schemaVersion': 1, 'vendorUid': uid, 'nextTicket': queue.nextTicket,
              'preparing': queue.preparingCount == 1, 'revision': queue.revision,
              'updatedAt': cursor.data()?['updatedAt'] ?? FieldValue.serverTimestamp()}
          : {'schemaVersion': 2, 'vendorUid': uid, 'nextTicket': queue.nextTicket,
              'preparingCount': queue.preparingCount, 'revision': queue.revision,
              'updatedAt': cursor.data()?['updatedAt'] ?? FieldValue.serverTimestamp()});
    }, maxAttempts: 8);
    _guard(uid);
  }

  /// Catch-up is serialized and bounded to one document transaction per order.
  /// Its per-order marker makes retries and duplicate snapshots idempotent.
  void recordReadySamples(Iterable<ConfirmedOrder> orders) {
    final uid = _uid;
    if (!enabled()) {
      return;
    }
    final candidates = List<ConfirmedOrder>.of(orders);
    _sampleQueue = _sampleQueue.then((_) async {
      for (final order in candidates) {
        if (order.vendorUid != uid || order.preparationSampleRecorded ||
            (order.status != 'Ready' && order.status != 'Completed')) {
          continue;
        }
        try {
          await recordPreparationSample(order);
        } on Object {
          break;
        }
      }
    });
  }

  Future<void> recordPreparationSample(ConfirmedOrder expected) async {
    final uid = _uid;
    _guard(uid);
    if (expected.vendorUid != uid) {
      throw const AccountException('This order belongs to another Vendor.');
    }
    final orderRef = db.collection('orders').doc(expected.id);
    final statsRef = _preparationStats(uid);
    for (var attempt = 0; attempt < 5; attempt++) {
      int? observedSampleCount;
      try {
        await db.runTransaction<void>((tx) async {
          _guard(uid);
          final saved = await tx.get(orderRef);
          if (!saved.exists) {
            throw const AccountException('Order no longer exists.');
          }
          final order = ConfirmedOrder.decode(saved.id, saved.data()!);
          if (order.vendorUid != uid || (order.status != 'Ready' && order.status != 'Completed')) {
            throw const AccountException('Only a Ready order can contribute a preparation sample.');
          }
          if (order.preparationSampleRecorded) return;
          final started = order.preparingAt?.toDate().millisecondsSinceEpoch;
          final ready = order.readyAt?.toDate().millisecondsSinceEpoch;
          final duration = started == null || ready == null ? -1 : ready - started;
          PreparationStats? stats;
          if (PreparationStats.isValidDuration(duration)) {
            final snapshot = await tx.get(statsRef);
            try {
              stats = snapshot.exists ? PreparationStats.decode(uid, snapshot.data()) : null;
            } on FormatException {
              throw const AccountException('Preparation history is malformed; no sample was changed.');
            }
            observedSampleCount = stats?.sampleCount ?? 0;
          }
          _guard(uid);
          if (PreparationStats.isValidDuration(duration)) {
            tx.set(statsRef, stats == null
                ? PreparationStats.firstSample(uid, order.id, duration)
                : stats.withSample(uid, order.id, duration));
          }
          tx.update(orderRef, {'preparationSampleRecorded': true});
        }, maxAttempts: 8);
        break;
      } on FirebaseException catch (error) {
        final observed = observedSampleCount;
        if (error.code != 'permission-denied' || observed == null || attempt == 4) {
          rethrow;
        }
        // The emulator may report a transaction conflict as permission-denied.
        // Retry only after server reads prove another valid sample advanced the
        // shared aggregate, or the same order was already recorded.
        final currentOrder = await orderRef.get(const GetOptions(source: Source.server));
        _guard(uid);
        if (currentOrder.data()?['preparationSampleRecorded'] == true) break;
        final currentStats = await statsRef.get(const GetOptions(source: Source.server));
        _guard(uid);
        if (!currentStats.exists) rethrow;
        try {
          if (PreparationStats.decode(uid, currentStats.data()).sampleCount <= observed) rethrow;
        } on FormatException {
          throw const AccountException('Preparation history is malformed; no sample was changed.');
        }
      }
    }
    _guard(uid);
    final confirmed = await orderRef.get(const GetOptions(source: Source.server));
    final current = confirmed.data();
    if (_uid != uid || confirmed.metadata.hasPendingWrites || current == null ||
        current['preparationSampleRecorded'] != true) {
      throw const AccountException('Preparation history acknowledgement is unavailable; retry when connected.');
    }
  }

  Future<void> advance(ConfirmedOrder expected) async {
    final uid = _uid;
    _guard(uid);
    if (_busy) throw const AccountException('Wait for the current status update.');
    if (expected.vendorUid != uid || expected.nextStatus == null) {
      throw const AccountException('This order cannot be changed by this Vendor.');
    }
    _busy = true;
    try {
      if (expected.status == 'Ready' && !expected.preparationSampleRecorded) {
        await recordPreparationSample(expected);
      }
      if (publicQueueCounts()) await initializeQueueCount();
      final ref = db.collection('orders').doc(expected.id), queueRef = _queue(uid);
      await _transition((tx, observe) async {
        _guard(uid);
        final saved = await tx.get(ref), cursor = await tx.get(queueRef);
        _guard(uid);
        if (!saved.exists) throw const AccountException('Order no longer exists. Refresh the inbox.');
        final order = ConfirmedOrder.decode(saved.id, saved.data()!);
        final queue = VendorQueue.decode(uid, cursor.data());
        final starting = order.status == 'Pending';
        final statsSnapshot = starting ? await tx.get(_preparationStats(uid)) : null;
        PreparationStats? stats;
        if (statsSnapshot?.exists == true) {
          try {
            stats = PreparationStats.decode(uid, statsSnapshot!.data());
          } on FormatException {
            throw const AccountException('Preparation history is malformed; Pending tickets cannot start safely.');
          }
        }
        final summary = publicQueueCounts() ? await tx.get(db.collection('stallQueueCounts').doc(uid)) : null;
        final count = PublicQueueCount.decode(uid, summary?.data());
        if (publicQueueCounts() && (count == null || count.nextTicket != queue.nextTicket ||
            count.preparingCount != queue.preparingCount)) {
          throw const AccountException('Queue counts could not be verified. Refresh Orders.');
        }
        observe(count?.lastTicket, queue.revision);
        if (order.vendorUid != uid || order.status != expected.status || order.statusRevision != expected.statusRevision) {
          throw const AccountException('This order changed on another device. Review its current status before retrying.');
        }
        if (queue.legacyPreparingOrderId case final legacyId?) {
          final legacy = await tx.get(db.collection('orders').doc(legacyId));
          if (legacy.data()?['vendorUid'] != uid || legacy.data()?['status'] != 'Preparing' ||
              legacy.data()?['ticket'] != queue.nextTicket - 1) {
            throw const AccountException('The legacy Preparing ticket could not be verified. No queue history was changed.');
          }
        }
        if (!queue.permits(order)) {
          throw const AccountException('Start Pending tickets in ticket order. Refresh Orders before retrying.');
        }
        final next = order.nextStatus!;
        final timestampField = switch (next) {
          'Preparing' => 'preparingAt', 'Ready' => 'readyAt', _ => 'completedAt',
        };
        final orderUpdate = <String, dynamic>{'status': next, 'statusRevision': order.statusRevision + 1,
          'statusUpdatedAt': FieldValue.serverTimestamp(), timestampField: FieldValue.serverTimestamp()};
        if (next == 'Preparing') {
          orderUpdate['preparationEstimateMillis'] = PreparationStats.estimateMillis(
            initialPreparationMinutes: order.preparationMinutes, history: stats);
        } else if (next == 'Ready') {
          orderUpdate['preparationSampleRecorded'] = false;
        }
        tx.update(ref, orderUpdate);
        if (next != 'Completed') {
          final starting = next == 'Preparing';
          final nextTicket = queue.nextTicket + (starting ? 1 : 0);
          final preparingCount = queue.preparingCount + (starting ? 1 : -1);
          tx.set(queueRef, {'schemaVersion': 2, 'vendorUid': uid,
            'nextTicket': nextTicket, 'preparingCount': preparingCount,
            'revision': queue.revision + 1, 'lastTransitionOrderId': order.id,
            'updatedAt': FieldValue.serverTimestamp()});
          tx.set(db.collection('queueProgress').doc(uid), {
            'schemaVersion': 2, 'vendorUid': uid, 'nextTicket': nextTicket,
            'preparingCount': preparingCount, 'revision': queue.revision + 1,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          if (count != null) {
            tx.set(db.collection('stallQueueCounts').doc(uid), {
              ...queueCountFields(uid, count.lastTicket, nextTicket, preparingCount),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
      });
      _guard(uid);
      final confirmed = await ref.get(const GetOptions(source: Source.server));
      _guard(uid);
      final current = confirmed.data();
      if (confirmed.metadata.hasPendingWrites || current == null ||
          (current['statusRevision'] as int? ?? 0) < expected.statusRevision + 1) {
        throw const AccountException('Update acknowledgement is unavailable. Refresh and review the server status.');
      }
      if (current['status'] == 'Ready' && current['preparationSampleRecorded'] != true) {
        await recordPreparationSample(ConfirmedOrder.decode(ref.id, current));
      }
    } finally {
      _busy = false;
    }
  }
}
