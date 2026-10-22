import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/checkout_limits.dart';
import '../models/confirmed_order.dart';
import '../models/vendor_menu.dart';
import '../models/vendor_queue.dart';
import 'auth_repository.dart';
import 'vendor_order_processing.dart';

abstract class OrderRepository {
  // Requires executed Rules proof and review before enabling the real client.
  bool get canCheckout => false;
  // Candidate operations are enabled only by the isolated debug demo entry.
  bool get canProcessOrders => false;
  Stream<VendorQueue> queue() => Stream.value(const VendorQueue.initial());
  Future<void> advance(ConfirmedOrder order) => Future.error(
    const AccountException('Order processing is available only in the local emulator demo.'));
  String newSubmissionId();
  Future<CheckoutRequest> prepare(CheckoutRequest request);
  Future<OrderReceipt> submit(CheckoutRequest request);
  Future<OrderReceipt?> discard(CheckoutRequest request);
  Stream<MenuData<ConfirmedOrder>> orders({required bool vendor});
  Stream<MenuData<OrderItem>> items(ConfirmedOrder order);
  Stream<MenuData<CheckoutRequest>> pendingRequests();
}

String orderError(Object error) {
  if (error is AccountException) return error.message;
  return 'The order could not be confirmed. Keep this checkout and retry, or safely discard the unconfirmed request.';
}

class _CheckoutObservation {
  String? state;
  int? ticket;
}

class FirebaseOrderRepository extends OrderRepository {
  FirebaseOrderRepository(this.db, this.currentUid);
  final FirebaseFirestore db;
  final String? Function() currentUid;
  String get _uid => currentUid() ?? (throw const AccountException('Please sign in again.'));
  DocumentReference<Map<String, dynamic>> _request(String uid, String id) =>
    db.collection('users').doc(uid).collection('checkoutRequests').doc(id);
  DocumentReference<Map<String, dynamic>> _order(String id) => db.collection('orders').doc(id);
  void _guard(CheckoutRequest request) {
    if (!canCheckout) throw const AccountException('Order confirmation awaits executed security verification.');
    if (request.studentUid != _uid) throw const AccountException('Your checkout session changed.');
    if (request.items.isEmpty || request.items.length > maxCheckoutProducts) {
      throw const AccountException('Checkout supports one or two distinct foods.');
    }
  }
  late final _processing = VendorOrderProcessing(db, currentUid, () => canProcessOrders);
  @override
  Stream<VendorQueue> queue() => _processing.watch();
  @override
  Future<void> advance(ConfirmedOrder order) => _processing.advance(order);
  @override
  String newSubmissionId() => db.collection('orders').doc().id;

  // The emulator can authorize a stale optimistic attempt before reporting its
  // read-version conflict. Never blindly retry permission-denied: require a
  // server-observed change to this attempt's request state or counter first.
  Future<T> _transaction<T>(CheckoutRequest request,
      Future<T> Function(Transaction, _CheckoutObservation) action) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      final observed = _CheckoutObservation();
      try {
        return await db.runTransaction<T>((tx) {
          observed.state = null;
          observed.ticket = null;
          return action(tx, observed);
        }, maxAttempts: 8);
      } on FirebaseException catch (error) {
        if (error.code != 'permission-denied' || attempt == 4) {
          rethrow;
        }
        _guard(request);
        final saved = await _request(request.studentUid, request.id).get(const GetOptions(source: Source.server));
        _guard(request);
        if (saved.metadata.hasPendingWrites) {
          rethrow;
        }
        final state = saved.exists ? saved.data()!['state'] : 'absent';
        if (observed.state != null && state != observed.state &&
            (state == 'confirmed' || state == 'cancelled' || state == 'pending')) {
          continue;
        }
        if (state == 'pending' && observed.ticket != null) {
          final counter = await db.collection('checkoutCounters').doc(request.vendorUid)
              .get(const GetOptions(source: Source.server));
          _guard(request);
          if (counter.metadata.hasPendingWrites) {
            rethrow;
          }
          final ticket = counter.data()?['lastTicket'] ?? 0;
          if (ticket is int && ticket > observed.ticket!) {
            continue;
          }
        }
        rethrow; // A stable-input authorization failure remains a failure.
      }
    }
    throw const AccountException('Checkout contention remains unresolved. Retry the same checkout.');
  }

  @override
  Future<CheckoutRequest> prepare(CheckoutRequest request) async {
    _guard(request); final uid = _uid;
    await _transaction<void>(request, (tx, observed) async {
      final ref = _request(uid, request.id), existing = await tx.get(_request(uid, request.id));
      observed.state = existing.exists
        ? (existing.data()!['state'] as String?)
        : 'absent';
      _guard(request);
      if (!existing.exists) tx.set(ref, request.createMap());
    });
    final snapshot = await _request(uid, request.id).get(const GetOptions(source: Source.server));
    _guard(request);
    if (snapshot.metadata.hasPendingWrites) {
      throw const AccountException('Checkout preparation is still awaiting server confirmation.');
    }
    return CheckoutRequest.decode(request.id, snapshot.data()!);
  }

  @override
  Future<OrderReceipt> submit(CheckoutRequest request) async {
    _guard(request); final uid = _uid;
    await _transaction<void>(request, (tx, observed) async {
      final requestRef = _request(uid, request.id);
      final saved = await tx.get(requestRef);
      _guard(request);
      if (!saved.exists) throw const AccountException('Prepare this checkout before confirming.');
      final intent = CheckoutRequest.decode(request.id, saved.data()!);
      observed.state = intent.state;
      if (intent.state == 'confirmed') return; // Same identity recovers an earlier commit.
      if (intent.state != 'pending') throw const AccountException('This unconfirmed checkout was discarded.');
      final listing = await tx.get(db.collection('publicStalls').doc(intent.vendorUid));
      if (listing.data()?['status'] != 'open' || listing.data()?['name'] != intent.stallName) {
        throw const AccountException('Stall details changed or the stall is Closed. Discard this request and review your cart.');
      }
      final counterRef = db.collection('checkoutCounters').doc(intent.vendorUid);
      final counter = await tx.get(counterRef);
      final previousTicket = counter.data()?['lastTicket'] ?? 0;
      if (previousTicket is int) {
        observed.ticket = previousTicket;
      }
      if (counter.exists && (counter.data()?['schemaVersion'] != 1 || counter.data()?['vendorUid'] != intent.vendorUid ||
          counter.data()!.length != 5 || counter.data()?['lastOrderId'] is! String || counter.data()?['updatedAt'] is! Timestamp ||
          previousTicket is! int || previousTicket < 1 || previousTicket >= 2147483647)) {
        throw const AccountException('The ticket counter could not be verified.');
      }
      final snapshots = <OrderItem>[];
      for (final draft in intent.items) {
        final root = db.collection('stalls').doc(intent.vendorUid);
        final food = await tx.get(root.collection('menuFoods').doc(draft.foodId));
        if (!food.exists) throw const AccountException('Food is no longer available. Discard and review your cart.');
        final current = MenuFood.decode(intent.vendorUid, draft.foodId, food.data()!);
        final category = await tx.get(root.collection('menuCategories').doc(current.draft.categoryId));
        final categoryData = category.data();
        if (!current.draft.available || current.revision != draft.foodRevision || current.draft.name != draft.name ||
            current.draft.description != draft.description || current.draft.categoryId != draft.categoryId ||
            current.draft.pictureId != draft.pictureId || current.draft.priceSen != draft.priceSen ||
            categoryData?['vendorUid'] != intent.vendorUid || categoryData?['name'] is! String) {
          throw const AccountException('Food details changed. Discard this request and refresh/review your cart.');
        }
        snapshots.add(OrderItem(foodId: draft.foodId, name: draft.name, description: draft.description,
          categoryId: draft.categoryId, pictureId: draft.pictureId, priceSen: draft.priceSen,
          quantity: draft.quantity, foodRevision: draft.foodRevision, categoryName: categoryData!['name']));
      }
      _guard(request);
      final ticket = (previousTicket as int) + 1;
      // Source stall and private membership are independently checked by Rules.
      // Students cannot read those private documents. Canonical stall changes
      // also update the public listing, which this transaction reads.
      tx.set(_order(intent.id), {'schemaVersion': 1, 'orderId': intent.id, 'submissionId': intent.id,
        'studentUid': uid, 'vendorUid': intent.vendorUid, 'stallName': intent.stallName,
        'preparationMinutes': listing.data()!['preparationMinutes'], 'ticket': ticket,
        'itemCount': snapshots.length, 'totalSen': intent.totalSen, 'status': 'Pending',
        'paymentMethod': intent.paymentMethod, 'paymentStatus': 'simulated',
        'createdAt': FieldValue.serverTimestamp(), 'firstItem': snapshots.first.snapshotMap});
      if (snapshots.length == maxCheckoutProducts) {
        tx.set(_order(intent.id).collection('items').doc('1'), snapshots[1].snapshotMap);
      }
      tx.set(counterRef, {'schemaVersion': 1, 'vendorUid': intent.vendorUid, 'lastTicket': ticket,
        'lastOrderId': intent.id, 'updatedAt': FieldValue.serverTimestamp()});
      tx.update(requestRef, {'state': 'confirmed', 'updatedAt': FieldValue.serverTimestamp()});
    });
    // Server-only reads after commit, never a locally pending success snapshot.
    return _receipt(uid, request.id);
  }

  Future<OrderReceipt> _receipt(String uid, String id) async {
    final header = await _order(id).get(const GetOptions(source: Source.server));
    if (_uid != uid) throw const AccountException('Your checkout session changed.');
    if (header.metadata.hasPendingWrites) {
      throw const AccountException('The order is still awaiting server confirmation.');
    }
    final order = ConfirmedOrder.decode(id, header.data()!);
    if (order.studentUid != uid) throw const AccountException('Order ownership could not be verified.');
    final children = await _order(id).collection('items').get(const GetOptions(source: Source.server));
    if (_uid != uid) throw const AccountException('Your checkout session changed.');
    if (children.metadata.hasPendingWrites) {
      throw const AccountException('Order items are still awaiting server confirmation.');
    }
    final docs = children.docs.toList()..sort((a, b) => a.id.compareTo(b.id));
    return OrderReceipt(order, [order.firstItem, ...docs.map((d) => OrderItem.decode(d.data(), snapshot: true))]);
  }

  @override
  Future<OrderReceipt?> discard(CheckoutRequest request) async {
    _guard(request); final uid = _uid;
    final confirmed = await _transaction<bool>(request, (tx, observed) async {
      final ref = _request(uid, request.id), saved = await tx.get(_request(uid, request.id));
      observed.state = saved.exists
        ? (saved.data()!['state'] as String?)
        : 'absent';
      _guard(request);
      if (!saved.exists) {
        // A terminal tombstone serializes with an interrupted prepare/submit.
        tx.set(ref, request.createMap(state: 'cancelled')); return false;
      }
      final intent = CheckoutRequest.decode(request.id, saved.data()!);
      if (intent.state == 'confirmed') return true;
      if (intent.state == 'pending') tx.update(ref, {'state': 'cancelled', 'updatedAt': FieldValue.serverTimestamp()});
      return false;
    });
    if (confirmed) return _receipt(uid, request.id);
    return null;
  }

  Stream<MenuData<T>> _watch<T>(Query<Map<String, dynamic>> query, T Function(String, Map<String, dynamic>) decode) async* {
    final uid = _uid;
    await for (final snapshot in query.snapshots(includeMetadataChanges: true)) {
      if (_uid != uid) throw const AccountException('Your session changed.');
      if (snapshot.metadata.hasPendingWrites) continue;
      yield MenuData(snapshot.docs.map((d) => decode(d.id, d.data())).toList(), cached: snapshot.metadata.isFromCache);
    }
  }
  @override
  Stream<MenuData<ConfirmedOrder>> orders({required bool vendor}) => _watch(
    db.collection('orders').where(vendor ? 'vendorUid' : 'studentUid', isEqualTo: _uid), ConfirmedOrder.decode);
  @override
  Stream<MenuData<CheckoutRequest>> pendingRequests() => _watch(
    db.collection('users').doc(_uid).collection('checkoutRequests').where('state', isEqualTo: 'pending'), CheckoutRequest.decode);
  @override
  Stream<MenuData<OrderItem>> items(ConfirmedOrder order) async* {
    await for (final data in _watch(_order(order.id).collection('items'),
        (_, d) => OrderItem.decode(d, snapshot: true))) {
      final all = [order.firstItem, ...data.items];
      if (!data.cached) OrderReceipt(order, all);
      yield MenuData(all, cached: data.cached);
    }
  }
}
