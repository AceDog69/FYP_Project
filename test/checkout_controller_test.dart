import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fyp_app/models/confirmed_order.dart';
import 'package:my_fyp_app/services/auth_repository.dart';
import 'package:my_fyp_app/services/checkout_controller.dart';
import 'package:my_fyp_app/services/student_cart.dart';
import 'support/catalog_fixtures.dart';
import 'support/fake_catalog_repository.dart';
import 'support/fake_order_repository.dart';

Future<void> flush() => Future<void>.delayed(Duration.zero);
void main() {
  late FakeCatalogRepository catalog;
  late FakeOrderRepository orders;
  late StudentCart cart;
  late CheckoutController checkout;
  setUp(() async {
    catalog = FakeCatalogRepository(); populate(catalog);
    orders = FakeOrderRepository(() => 'student')..enabled = true;
    cart = StudentCart('student', catalog);
    cart.add(await catalog.selection('alpha', 'bowl'), 2); await flush();
    checkout = CheckoutController(cart, orders);
  });
  tearDown(() { checkout.dispose(); cart.dispose(); orders.dispose(); catalog.dispose(); });

  test('eligibility and proof gates block submission without discarding the Cart', () async {
    expect(cart.checkoutEligible, true); orders.enabled = false;
    expect(await checkout.confirm('ewallet'), isNull); expect(orders.prepareCalls, 0); expect(cart.itemCount, 2);
    orders.enabled = true; catalog.cached = true; catalog.emit(); await flush();
    expect(cart.checkoutEligible, false); expect(await checkout.confirm('ewallet'), isNull);
    expect(orders.submitCalls, 0); expect(cart.itemCount, 2);
  });

  test('pending/repeated confirmation is one submission; only acknowledgement clears Cart', () async {
    orders.pending = Completer<void>(); final result = checkout.confirm('ewallet'); await flush();
    expect(checkout.busy, true); expect(cart.itemCount, 2); expect(cart.checkoutLocked, true);
    expect(await checkout.confirm('card'), isNull); expect(orders.submitCalls, 1); expect(orders.identities, 1);
    expect(() => cart.remove('bowl'), throwsA(isA<AccountException>()));
    orders.pending!.complete(); final receipt = await result;
    expect(receipt!.order.totalSen, 1700); expect(cart.lines, isEmpty); expect(cart.checkoutLocked, false);
  });

  test('failure/retry retains one identity, original payment and all unpaid content', () async {
    orders.submitError = const AccountException('Offline.');
    expect(await checkout.confirm('ewallet'), isNull); final id = checkout.request!.id;
    expect(cart.itemCount, 2); expect(cart.totalSen, 1700); expect(cart.checkoutLocked, true);
    orders.submitError = null;
    final receipt = await checkout.confirm('card');
    expect(receipt!.order.id, id); expect(receipt.order.paymentMethod, 'ewallet');
    expect(orders.submittedIds.toSet(), {id}); expect(orders.tickets['alpha'], 1); expect(cart.lines, isEmpty);
  });

  test('committed but unacknowledged checkout recovers one receipt without a second ticket', () async {
    orders.commitButLoseAck = true;
    expect(await checkout.confirm('card'), isNull); expect(orders.receipts.length, 1); expect(cart.itemCount, 2);
    final id = checkout.request!.id;
    final receipt = await checkout.confirm('card');
    expect(receipt!.order.id, id); expect(orders.receipts.length, 1); expect(orders.tickets['alpha'], 1);
    expect(cart.lines, isEmpty);
  });

  test('safe discard preserves Cart on failure and recovers an already confirmed order', () async {
    orders.submitError = const AccountException('Menu changed.');
    await checkout.confirm('ewallet'); final id = checkout.request!.id;
    expect(await checkout.discard(), isNull); expect(checkout.request, isNull); expect(cart.itemCount, 2);
    expect(cart.checkoutLocked, false); expect(orders.requests[id]!.state, 'cancelled');
    orders.submitError = null; orders.commitButLoseAck = true;
    await checkout.confirm('ewallet');
    final recovered = await checkout.discard();
    expect(recovered, isNotNull); expect(cart.lines, isEmpty); expect(orders.receipts.length, 1);
  });

  test('resuming a persisted request preserves an unrelated current Cart on success', () async {
    final saved = CheckoutRequest(id: orders.newSubmissionId(), studentUid: 'student', vendorUid: 'beta',
      stallName: 'Beta Kitchen', paymentMethod: 'ewallet', items: [const OrderItem(foodId: 'bowl', name: 'Rice Bowl',
        description: 'Fresh rice', categoryId: 'rice', pictureId: 'nasi_lemak', priceSen: 905, quantity: 1, foodRevision: 1)]);
    await orders.prepare(saved); checkout.resume(saved);
    final receipt = await checkout.confirm('card');
    expect(receipt!.order.vendorUid, 'beta'); expect(cart.vendorId, 'alpha'); expect(cart.itemCount, 2);
    expect(cart.checkoutLocked, false);
  });

  test('disposed checkout cannot clear another session after an interrupted response', () async {
    final otherCart = StudentCart('student', catalog); otherCart.add(await catalog.selection('alpha','bowl'), 1); await flush();
    final other = CheckoutController(otherCart, orders); orders.pending = Completer<void>();
    final result = other.confirm('ewallet'); await flush(); other.dispose(); otherCart.dispose();
    orders.pending!.complete(); expect(await result, isNull);
    expect(cart.itemCount, 2); expect(cart.ownerUid, 'student');
  });

  test('request/snapshot bounds, immutable item lists and precise totals are explicit', () {
    const item = OrderItem(foodId: 'food', name: 'Rice', description: 'Fresh rice', categoryId: 'rice',
      pictureId: 'nasi_lemak', priceSen: 905, quantity: 20, foodRevision: 1);
    final q = CheckoutRequest(id: 'A' * 20, studentUid: 'student', vendorUid: 'vendor', stallName: 'Kitchen',
      items: [item], paymentMethod: 'ewallet');
    expect(q.totalSen, 18100); expect(() => q.items.clear(), throwsUnsupportedError);
    expect(() => CheckoutRequest(id: 'B' * 20, studentUid: 'student', vendorUid: 'vendor', stallName: 'Kitchen',
      items: [item,item], paymentMethod: 'card'), throwsFormatException);
  });

  test('two-food checkout preserves twenty units each and integer totals through acknowledgement', () async {
    catalog.foodItems['alpha']!.add(food('drink', price: 905, category: 'drinks'));
    catalog.emit(); await flush(); cart.quantity('bowl', 20);
    cart.add(await catalog.selection('alpha', 'drink'), 20); await flush();
    expect(cart.checkoutEligible, true);
    final receipt = await checkout.confirm('card');
    expect(receipt!.items.length, 2); expect(receipt.items.map((i) => i.quantity), [20,20]);
    expect(receipt.order.totalSen, 35100); expect(orders.tickets['alpha'], 1);
    expect(cart.lines, isEmpty);
  });

  test('models reject three, four and five foods in drafts, decoded requests and order headers', () {
    List<OrderItem> items(int count) => List.generate(count, (index) => OrderItem(
      foodId: 'food$index', name: 'Food $index', description: 'Fresh rice', categoryId: 'rice',
      pictureId: 'nasi_lemak', priceSen: 905, quantity: 20, foodRevision: 1));
    final two = CheckoutRequest(id: 'A' * 20, studentUid: 'student', vendorUid: 'vendor',
      stallName: 'Kitchen', items: items(2), paymentMethod: 'ewallet');
    final time = Timestamp.fromMillisecondsSinceEpoch(1792634400000);
    final record = {...two.createMap(), 'createdAt': time, 'updatedAt': time};
    expect(CheckoutRequest.decode(two.id, record).totalSen, 36200);
    for (final count in [3,4,5]) {
      expect(() => CheckoutRequest(id: 'B' * 20, studentUid: 'student', vendorUid: 'vendor',
        stallName: 'Kitchen', items: items(count), paymentMethod: 'card'), throwsFormatException);
      expect(() => CheckoutRequest.decode(two.id, {...record,
        'items': items(count).map((i) => i.draftMap).toList(), 'totalSen': 18100 * count}), throwsFormatException);
      expect(() => ConfirmedOrder(id: two.id, studentUid: 'student', vendorUid: 'vendor',
        stallName: 'Kitchen', ticket: 1, totalSen: 18100 * count, itemCount: count,
        preparationMinutes: 15, paymentMethod: 'ewallet', createdAt: time,
        firstItem: two.items.first), throwsFormatException);
      expect(() => ConfirmedOrder.decode(two.id, {'schemaVersion': 1, 'orderId': two.id, 'submissionId': two.id,
        'studentUid': 'student', 'vendorUid': 'vendor', 'stallName': 'Kitchen', 'status': 'Pending',
        'paymentStatus': 'simulated', 'paymentMethod': 'ewallet', 'ticket': 1, 'createdAt': time,
        'preparationMinutes': 15, 'itemCount': count, 'totalSen': 18100 * count,
        'firstItem': {...two.items.first.snapshotMap, 'categoryName': 'Rice'}}), throwsFormatException);
    }
  });
}
