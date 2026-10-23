import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/confirmed_order.dart';
import '../models/vendor_queue.dart';
import '../models/queue_progress.dart';
import 'auth_repository.dart';

// Separate from the accepted checkout protocol: this service never writes an
// order snapshot, checkout request, item, payment or ticket counter.
class VendorOrderProcessing {
  VendorOrderProcessing(this.db, this.currentUid, this.enabled);
  final FirebaseFirestore db;
  final String? Function() currentUid;
  final bool Function() enabled;
  bool _busy = false;
  String get _uid => currentUid() ?? (throw const AccountException('Please sign in again.'));
  DocumentReference<Map<String, dynamic>> _queue(String uid) => db.collection('vendorQueues').doc(uid);
  void _guard(String uid) {
    if (!enabled() || _uid != uid) {
      throw const AccountException('Order processing requires the local emulator demo and the same Vendor session.');
    }
  }
  Stream<VendorQueue> watch() async* {
    final uid = _uid;
    var published = false;
    await for (final s in _queue(uid).snapshots(includeMetadataChanges: true)) {
      if (_uid != uid) {
        throw const AccountException('Your Vendor session changed.');
      }
      if (s.metadata.hasPendingWrites) {
        continue;
      }
      if (!s.metadata.isFromCache && !published && enabled()) {
        await _publishMissingProgress(uid);
        published = true;
      }
      yield VendorQueue.decode(uid, s.data(), cached: s.metadata.isFromCache);
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
        if (existing.nextTicket != queue.nextTicket || existing.preparing != (queue.preparingOrderId != null) ||
            existing.revision != queue.revision ||
            (cursor.exists && existing.updatedAt != cursor.data()!['updatedAt'])) {
          throw const AccountException('Queue progress does not match the preparation cursor. Review server data.');
        }
        return;
      }
      tx.set(target, {'schemaVersion': 1, 'vendorUid': uid, 'nextTicket': queue.nextTicket,
        'preparing': queue.preparingOrderId != null, 'revision': queue.revision,
        'updatedAt': cursor.data()?['updatedAt'] ?? FieldValue.serverTimestamp()});
    }, maxAttempts: 8);
    _guard(uid);
  }
  Future<void> advance(ConfirmedOrder expected) async {
    final uid = _uid;
    _guard(uid);
    if (_busy) {
      throw const AccountException('Wait for the current status update.');
    }
    if (expected.vendorUid != uid || expected.nextStatus == null) {
      throw const AccountException('This order cannot be changed by this Vendor.');
    }
    _busy = true;
    try {
      final ref = db.collection('orders').doc(expected.id), queueRef = _queue(uid);
      await db.runTransaction<void>((tx) async {
        _guard(uid);
        final saved = await tx.get(ref), cursor = await tx.get(queueRef);
        _guard(uid);
        if (!saved.exists) {
          throw const AccountException('Order no longer exists. Refresh the inbox.');
        }
        final order = ConfirmedOrder.decode(saved.id, saved.data()!);
        final queue = VendorQueue.decode(uid, cursor.data());
        if (order.vendorUid != uid || order.status != expected.status || order.statusRevision != expected.statusRevision) {
          throw const AccountException('This order changed on another device. Review its current status before retrying.');
        }
        if (!queue.permits(order)) {
          throw const AccountException('Start the next Pending ticket only, after the Preparing order is Ready.');
        }
        final next = order.nextStatus!;
        final timestampField = switch (next) {
          'Preparing' => 'preparingAt', 'Ready' => 'readyAt', _ => 'completedAt',
        };
        tx.update(ref, {'status': next, 'statusRevision': order.statusRevision + 1,
          'statusUpdatedAt': FieldValue.serverTimestamp(),
          timestampField: FieldValue.serverTimestamp()});
        if (next != 'Completed') {
          tx.set(queueRef, {'schemaVersion': 1, 'vendorUid': uid,
            'nextTicket': queue.nextTicket + (next == 'Preparing' ? 1 : 0),
            'preparingOrderId': next == 'Preparing' ? order.id : null,
            'revision': queue.revision + 1, 'updatedAt': FieldValue.serverTimestamp()});
          tx.set(db.collection('queueProgress').doc(uid), {
            'schemaVersion': 1, 'vendorUid': uid,
            'nextTicket': queue.nextTicket + (next == 'Preparing' ? 1 : 0),
            'preparing': next == 'Preparing', 'revision': queue.revision + 1,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }, maxAttempts: 8);
      _guard(uid);
      final confirmed = await ref.get(const GetOptions(source: Source.server));
      _guard(uid);
      final current = confirmed.data();
      if (confirmed.metadata.hasPendingWrites || current == null ||
          (current['statusRevision'] as int? ?? 0) < expected.statusRevision + 1) {
        throw const AccountException('Update acknowledgement is unavailable. Refresh and review the server status.');
      }
    } finally {
      _busy = false;
    }
  }
}
