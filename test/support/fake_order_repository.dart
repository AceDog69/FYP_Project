import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:my_fyp_app/models/confirmed_order.dart';
import 'package:my_fyp_app/models/vendor_menu.dart';
import 'package:my_fyp_app/services/auth_repository.dart';
import 'package:my_fyp_app/services/order_repository.dart';

OrderReceipt receiptFor(CheckoutRequest q, int ticket) {
  final snapshots = q.items.map((i) => OrderItem.decode({...i.draftMap, 'categoryName': 'Rice',
    'subtotalSen': i.subtotalSen}, snapshot: true)).toList();
  return OrderReceipt(ConfirmedOrder(id: q.id, studentUid: q.studentUid, vendorUid: q.vendorUid,
    stallName: q.stallName, ticket: ticket, totalSen: q.totalSen, itemCount: q.items.length,
    preparationMinutes: 15, paymentMethod: q.paymentMethod, createdAt: Timestamp.fromMillisecondsSinceEpoch(1792634400000),
    firstItem: snapshots.first), snapshots);
}
CheckoutRequest withState(CheckoutRequest q, String state) => CheckoutRequest(id: q.id, studentUid: q.studentUid,
  vendorUid: q.vendorUid, stallName: q.stallName, items: q.items, paymentMethod: q.paymentMethod,
  state: state, createdAt: Timestamp.fromMillisecondsSinceEpoch(1792634400000));

class FakeOrderRepository extends OrderRepository {
  FakeOrderRepository(this.currentUid);
  final String? Function() currentUid;
  bool enabled = false, cached = false, loading = false, commitButLoseAck = false;
  Object? submitError, prepareError, streamError;
  String? errorTarget;
  Completer<void>? pending;
  int identities = 0, prepareCalls = 0, submitCalls = 0;
  final receipts = <String, OrderReceipt>{};
  final requests = <String, CheckoutRequest>{};
  final tickets = <String, int>{};
  final submittedIds = <String>[];
  final events = StreamController<int>.broadcast();
  @override
  bool get canCheckout => enabled;
  @override
  String newSubmissionId() => 'order${(identities++).toString().padLeft(15, '0')}';
  @override
  Future<CheckoutRequest> prepare(CheckoutRequest request) async {
    prepareCalls++;
    if (!enabled) throw const AccountException('Confirmation is gated.');
    final saved = requests.putIfAbsent(request.id, () => withState(request, 'pending'));
    if (prepareError != null) throw prepareError!;
    emit(); return saved;
  }
  @override
  Future<OrderReceipt> submit(CheckoutRequest request) async {
    submitCalls++; submittedIds.add(request.id);
    if (pending != null) await pending!.future;
    if (submitError != null) throw submitError!;
    if (requests[request.id]?.state == 'cancelled') throw const AccountException('Discarded.');
    if (receipts.containsKey(request.id)) return receipts[request.id]!;
    final ticket = (tickets[request.vendorUid] ?? 0) + 1;
    final receipt = receiptFor(request, ticket);
    tickets[request.vendorUid] = ticket; receipts[request.id] = receipt;
    requests[request.id] = withState(request, 'confirmed'); emit();
    if (commitButLoseAck) { commitButLoseAck = false; throw const AccountException('Acknowledgement interrupted. Retry the same request.'); }
    return receipt;
  }
  @override
  Future<OrderReceipt?> discard(CheckoutRequest request) async {
    if (receipts.containsKey(request.id)) return receipts[request.id];
    requests[request.id] = withState(request, 'cancelled'); emit(); return null;
  }
  void emit() => events.add(receipts.length);
  Stream<MenuData<T>> _watch<T>(String target, List<T> Function() values) async* {
    if (!loading) yield MenuData(values(), cached: cached);
    await for (final _ in events.stream) {
      if (streamError != null && errorTarget == target) { yield* Stream<MenuData<T>>.error(streamError!); }
      else { yield MenuData(values(), cached: cached); }
    }
  }
  @override
  Stream<MenuData<ConfirmedOrder>> orders({required bool vendor}) => _watch('orders', () => receipts.values
    .map((r) => r.order).where((o) => (vendor ? o.vendorUid : o.studentUid) == currentUid()).toList());
  @override
  Stream<MenuData<OrderItem>> items(ConfirmedOrder order) => _watch('items', () => receipts[order.id]?.items ?? []);
  @override
  Stream<MenuData<CheckoutRequest>> pendingRequests() => _watch('requests', () => requests.values
    .where((q) => q.studentUid == currentUid() && q.state == 'pending').toList());
  void dispose() { events.close(); }
}
