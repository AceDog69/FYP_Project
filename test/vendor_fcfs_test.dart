import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fyp_app/models/confirmed_order.dart';
import 'package:my_fyp_app/models/vendor_queue.dart';
import 'package:my_fyp_app/screens/orders_screen.dart';
import 'package:my_fyp_app/services/auth_repository.dart';
import 'package:my_fyp_app/services/vendor_order_processing.dart';
import 'package:my_fyp_app/theme/app_theme.dart';
import 'support/fake_order_repository.dart';

class _NoNetworkFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected Firebase access');
}
CheckoutRequest request(String suffix, {String student = 'student', String vendor = 'vendor'}) => CheckoutRequest(
  id: suffix.padLeft(20, '0'), studentUid: student, vendorUid: vendor, stallName: 'Demo Kitchen',
  paymentMethod: 'ewallet', items: [const OrderItem(foodId: 'rice', name: 'Rice Bowl', description: 'Fresh rice',
    categoryId: 'meals', pictureId: 'nasi_lemak', priceSen: 850, quantity: 2, foodRevision: 1)]);
Map<String, dynamic> header(ConfirmedOrder order) => {
  'schemaVersion': 1, 'orderId': order.id, 'submissionId': order.id,
  'studentUid': order.studentUid, 'vendorUid': order.vendorUid, 'stallName': order.stallName,
  'ticket': order.ticket, 'totalSen': order.totalSen, 'itemCount': order.itemCount,
  'preparationMinutes': order.preparationMinutes, 'paymentMethod': order.paymentMethod,
  'paymentStatus': 'simulated', 'createdAt': order.createdAt, 'firstItem': order.firstItem.snapshotMap,
  'status': order.status,
  if (order.statusRevision > 0) ...{
    'statusRevision': order.statusRevision, 'statusUpdatedAt': order.statusUpdatedAt, 'preparingAt': order.preparingAt,
  },
  if (order.readyAt != null) 'readyAt': order.readyAt,
  if (order.completedAt != null) 'completedAt': order.completedAt,
};

void main() {
  test('legacy Pending and all confirmed progress statuses decode for both roles without changing snapshots', () {
    var order = receiptFor(request('1'), 1).order;
    for (final status in orderStatuses) {
      final decoded = ConfirmedOrder.decode(order.id, header(order));
      expect(decoded.status, status); expect(decoded.statusRevision, orderStatuses.indexOf(status));
      expect(decoded.firstItem.snapshotMap, order.firstItem.snapshotMap); expect(decoded.totalSen, 1700);
      expect(decoded.createdAt, order.createdAt);
      if (status != 'Completed') order = progressed(order);
    }
    expect(order.nextStatus, isNull);
  });
  test('invalid statuses, revisions and missing transition timestamps fail closed', () {
    final pending = receiptFor(request('1'), 1).order;
    final preparing = progressed(pending);
    for (final values in [<String, dynamic>{'status': 'Forged'}, {'status': 'Ready'},
      {'statusRevision': 2}, {'statusRevision': 1.0}, {'preparingAt': null}, {'statusUpdatedAt': null}]) {
      expect(() => ConfirmedOrder.decode(pending.id, {...header(preparing), ...values}), throwsFormatException);
    }
  });
  test('queue decoder, exact ticket eligibility, one slot and cache restrictions', () {
    final first = receiptFor(request('1'), 1).order, second = receiptFor(request('2'), 2).order;
    final initial = VendorQueue.decode('vendor', null);
    expect(initial.permits(first), true); expect(initial.permits(second), false);
    final claimed = VendorQueue(2, first.id, 1);
    expect(claimed.permits(second), false); expect(claimed.permits(progressed(first)), true);
    expect(const VendorQueue(2, null, 2).permits(second), true);
    expect(const VendorQueue.initial(cached: true).permits(first), false);
    expect(VendorQueue(2, first.id, 1, cached: true).permits(progressed(first)), false);
    expect(() => VendorQueue.decode('vendor', {'nextTicket': 3}), throwsFormatException);
    expect(() => VendorQueue.decode('vendor', {'schemaVersion': 1, 'vendorUid': 'other',
      'nextTicket': 2, 'preparingOrderId': null, 'revision': 1, 'updatedAt': Timestamp.now()}), throwsFormatException);
  });
  test('disabled real processing service rejects without accessing Firebase', () async {
    final service = VendorOrderProcessing(_NoNetworkFirestore(), () => 'vendor', () => false);
    await expectLater(service.advance(receiptFor(request('1'), 1).order), throwsA(isA<AccountException>()));
  });
  test('processing refuses wrong owner and terminal orders before Firebase access', () async {
    final service = VendorOrderProcessing(_NoNetworkFirestore(), () => 'vendor', () => true);
    final other = receiptFor(request('1', vendor: 'other'), 1).order;
    await expectLater(service.advance(other), throwsA(isA<AccountException>()));
    final completed = progressed(progressed(progressed(receiptFor(request('2'), 1).order)));
    await expectLater(service.advance(completed), throwsA(isA<AccountException>()));
  });

  Future<void> mount(WidgetTester tester, FakeOrderRepository repo, {bool vendor = true}) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(theme: smartCanteenTheme(), home: Scaffold(
      body: OrdersScreen(repository: repo, vendor: vendor))));
    await tester.pumpAndSettle();
  }
  Finder action(ConfirmedOrder order) => find.byKey(ValueKey('advance-${order.id}'));
  Future<void> press(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder); await tester.tap(finder); await tester.pumpAndSettle();
  }
  FakeOrderRepository fixture({bool enabled = true}) {
    final repo = FakeOrderRepository(() => 'vendor')..processingEnabled = enabled;
    final first = receiptFor(request('1'), 1), second = receiptFor(request('2'), 2);
    repo.receipts[second.order.id] = second; repo.receipts[first.order.id] = first;
    addTearDown(repo.dispose); return repo;
  }

  testWidgets('Pixel 6 shows ascending tickets, clear status badges, items and totals', (tester) async {
    final repo = fixture(); await mount(tester, repo);
    final first = repo.receipts[request('1').id]!.order, second = repo.receipts[request('2').id]!.order;
    expect(tester.getTopLeft(find.text('Ticket #1')).dy, lessThan(tester.getTopLeft(find.text('Ticket #2')).dy));
    expect(find.byType(OrderStatusBadge), findsNWidgets(2));
    expect(find.textContaining('2 × Rice Bowl'), findsWidgets); expect(find.text('Confirmed total: RM 17.00'), findsWidgets);
    expect(tester.widget<FilledButton>(action(first)).onPressed, isNotNull);
    expect(tester.widget<FilledButton>(action(second)).onPressed, isNull); expect(tester.takeException(), isNull);
  });
  testWidgets('confirmed progress releases slot, retains Ready and completes after collection', (tester) async {
    final repo = fixture(); await mount(tester, repo);
    final first = repo.receipts[request('1').id]!.order, second = repo.receipts[request('2').id]!.order;
    await press(tester, action(first)); expect(repo.receipts[first.id]!.order.status, 'Preparing');
    expect(tester.widget<FilledButton>(action(second)).onPressed, isNull);
    await press(tester, action(first)); expect(repo.receipts[first.id]!.order.status, 'Ready');
    expect(tester.widget<FilledButton>(action(second)).onPressed, isNotNull);
    await press(tester, action(second)); expect(repo.receipts[second.id]!.order.status, 'Preparing');
    await press(tester, action(first)); expect(repo.receipts[first.id]!.order.status, 'Completed');
    expect(action(first), findsNothing); expect(repo.advanceCalls, 4);
  });
  testWidgets('duplicate taps remain disabled and status is unchanged until acknowledged', (tester) async {
    final repo = fixture()..pendingAdvance = Completer<void>(); await mount(tester, repo);
    final first = repo.receipts[request('1').id]!.order;
    await press(tester, action(first)); expect(repo.advanceCalls, 1);
    expect(repo.receipts[first.id]!.order.status, 'Pending');
    expect(find.text('Confirming with server…'), findsOneWidget);
    expect(tester.widget<FilledButton>(action(first)).onPressed, isNull);
    await tester.tap(action(first)); expect(repo.advanceCalls, 1);
    repo.pendingAdvance!.complete(); await tester.pumpAndSettle();
    expect(repo.receipts[first.id]!.order.status, 'Preparing');
  });
  testWidgets('error requires refresh and a reviewed retry; no false status update', (tester) async {
    final repo = fixture()..advanceError = const AccountException('Connection interrupted. Review the order.');
    await mount(tester, repo); final first = repo.receipts[request('1').id]!.order;
    await press(tester, action(first)); expect(repo.receipts[first.id]!.order.status, 'Pending');
    expect(find.textContaining('Connection interrupted'), findsOneWidget);
    expect(tester.widget<FilledButton>(action(first)).onPressed, isNull);
    repo.advanceError = null; await press(tester, find.text('Refresh orders before retrying'));
    await press(tester, action(first)); expect(repo.receipts[first.id]!.order.status, 'Preparing');
  });
  testWidgets('cached orders or cached cursor block mutations and queue errors offer Retry', (tester) async {
    final repo = fixture()..cached = true; await mount(tester, repo);
    final first = repo.receipts[request('1').id]!.order;
    expect(tester.widget<FilledButton>(action(first)).onPressed, isNull);
    repo.cached = false; repo.queueCached = true; repo.emit(); await tester.pumpAndSettle();
    expect(find.textContaining('Cached queue'), findsOneWidget); expect(tester.widget<FilledButton>(action(first)).onPressed, isNull);
    repo.queueCached = false; repo.errorTarget = 'queue'; repo.streamError = StateError('offline');
    repo.emit(); await tester.pumpAndSettle();
    expect(find.text('Unable to verify preparation queue. Retry'), findsOneWidget);
    expect(tester.widget<FilledButton>(action(first)).onPressed, isNull);
    repo.streamError = null; repo.errorTarget = null;
    await press(tester, find.text('Unable to verify preparation queue. Retry'));
    expect(tester.widget<FilledButton>(action(first)).onPressed, isNotNull); expect(repo.advanceCalls, 0);
  });
  testWidgets('normal environment remains read-only with visible explanation', (tester) async {
    final repo = fixture(enabled: false); await mount(tester, repo);
    expect(find.textContaining('disabled outside the local emulator'), findsOneWidget);
    expect(find.text('Start Preparing'), findsNothing); expect(repo.advanceCalls, 0);
  });
  testWidgets('status filters stay within Orders and Completed records remain in History', (tester) async {
    final repo = fixture(); final first = repo.receipts[request('1').id]!;
    repo.receipts[first.order.id] = OrderReceipt(progressed(progressed(progressed(first.order))), first.items);
    await mount(tester, repo);
    await press(tester, find.widgetWithText(ChoiceChip, 'Pending')); expect(find.text('Ticket #1'), findsNothing);
    await press(tester, find.widgetWithText(ChoiceChip, 'History')); expect(find.text('Ticket #1'), findsOneWidget);
    expect(find.text('Ticket #2'), findsNothing); expect(find.text('Start Preparing'), findsNothing);
  });
  testWidgets('Student inbox and open details receive live statuses without Vendor actions', (tester) async {
    final repo = FakeOrderRepository(() => 'student'); addTearDown(repo.dispose);
    final receipt = receiptFor(request('1'), 1); repo.receipts[receipt.order.id] = receipt;
    await mount(tester, repo, vendor: false);
    await press(tester, find.text('View Details'));
    var order = receipt.order;
    for (var i = 0; i < 3; i++) {
      order = progressed(order); repo.receipts[order.id] = OrderReceipt(order, receipt.items); repo.emit();
      await tester.pumpAndSettle();
      final badge = find.widgetWithText(OrderStatusBadge, order.status);
      await tester.scrollUntilVisible(badge, -200, scrollable: find.byType(Scrollable).first);
      expect(badge, findsOneWidget);
      final total = find.text('Confirmed total: RM 17.00');
      await tester.scrollUntilVisible(total, 200, scrollable: find.byType(Scrollable).first);
      expect(total, findsOneWidget);
    }
    expect(find.text('Start Preparing'), findsNothing); expect(find.text('Mark as Ready'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
