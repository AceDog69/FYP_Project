import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fyp_app/models/confirmed_order.dart';
import 'package:my_fyp_app/models/queue_progress.dart';
import 'package:my_fyp_app/screens/student_queue_screen.dart';
import 'package:my_fyp_app/services/auth_repository.dart';
import 'package:my_fyp_app/theme/app_theme.dart';
import 'support/fake_order_repository.dart';

CheckoutRequest queueRequest(String id, {String student = 'student', String vendor = 'alpha'}) => CheckoutRequest(
  id: id.padLeft(20, '0'), studentUid: student, vendorUid: vendor, stallName: '$vendor Kitchen', paymentMethod: 'ewallet',
  items: [const OrderItem(foodId: 'rice', name: 'Rice Bowl', description: 'Fresh rice', categoryId: 'meals',
    pictureId: 'nasi_lemak', priceSen: 850, quantity: 2, foodRevision: 1)]);
QueueProgress progress(String uid, int next, int preparingCount) => QueueProgress(uid, next, preparingCount,
  2 * (next - 1) - preparingCount, Timestamp.fromMillisecondsSinceEpoch(1792634400000));

void main() {
  final first = receiptFor(queueRequest('1'), 1).order;
  final fourth = receiptFor(queueRequest('4'), 4).order;
  final now = first.createdAt.toDate();
  test('missing progress remains unknown and schema rejects IDs, ownership, types and impossible revisions', () {
    expect(QueueProgress.decode('alpha', null).nextTicket, isNull);
    final good = {'schemaVersion': 2, 'vendorUid': 'alpha', 'nextTicket': 2, 'preparingCount': 1,
      'revision': 1, 'updatedAt': Timestamp.now()};
    expect(QueueProgress.decode('alpha', good).preparingCount, 1);
    for (final values in [{'preparingOrderId': 'private'}, {'vendorUid': 'other'}, {'nextTicket': 0},
      {'nextTicket': 2.0}, {'revision': 2}, {'preparingCount': '1'}, {'updatedAt': 'forged'}]) {
      expect(() => QueueProgress.decode('alpha', {...good, ...values}), throwsFormatException);
    }
  });
  test('Pending position is exact but parallel preparation has no defensible numeric ETA', () {
    final one = estimateQueue(first, progress('alpha', 1, 0), now);
    final four = estimateQueue(fourth, progress('alpha', 1, 0), now);
    expect(one.ahead, 0); expect(one.minutes, isNull);
    expect(four.ahead, 3); expect(four.minutes, isNull);
    expect(four.message, contains('unavailable while orders are prepared in parallel'));
  });
  test('Pending position counts earlier tickets that have not started', () {
    final parallel = estimateQueue(fourth, progress('alpha', 3, 2), now);
    final ready = estimateQueue(fourth, progress('alpha', 3, 1), now);
    expect(parallel.ahead, 1); expect(parallel.minutes, isNull);
    expect(ready.ahead, 1); expect(ready.minutes, isNull);
  });
  test('own Preparing uses rounded-up approximate remaining time with no timer', () {
    final preparing = progressed(first);
    final estimate = estimateQueue(preparing, progress('alpha', 2, 1),
      preparing.preparingAt!.toDate().add(const Duration(minutes: 4, seconds: 30)));
    expect(estimate.ahead, 0); expect(estimate.minutes, 11); expect(estimate.overdue, false);
    expect(estimate.message, contains('not a countdown'));
  });
  test('elapsed baseline means unknown Ready time; a backwards device clock never produces a larger baseline', () {
    final preparing = progressed(first), started = preparing.preparingAt!.toDate();
    for (final minutes in [15, 40]) {
      final estimate = estimateQueue(preparing, progress('alpha', 2, 1), started.add(Duration(minutes: minutes)));
      expect(estimate.minutes, isNull); expect(estimate.overdue, true); expect(estimate.ahead, 0);
    }
    expect(estimateQueue(preparing, progress('alpha', 2, 1), started.subtract(const Duration(minutes: 2))).minutes, 15);
    final second = receiptFor(queueRequest('2'), 2).order;
    final secondStart = progressed(second);
    final parallelOwn = estimateQueue(secondStart, progress('alpha', 3, 2),
      secondStart.preparingAt!.toDate().add(const Duration(minutes: 4)));
    expect(parallelOwn.minutes, 11); expect(parallelOwn.ahead, 0);
  });
  test('Ready and Completed have no wait ETA even if progress is absent', () {
    final ready = progressed(progressed(first)), completed = progressed(ready);
    for (final order in [ready, completed]) {
      final estimate = estimateQueue(order, null, now); expect(estimate.ahead, 0); expect(estimate.minutes, isNull);
    }
  });
  test('cross-stall, missing, cached and out-of-order snapshots do not fabricate a current position', () {
    for (final p in <QueueProgress?>[null, const QueueProgress.unavailable('alpha'), progress('other', 1, 0),
      QueueProgress('alpha', 1, 0, 0, Timestamp.now(), cached: true), progress('alpha', 2, 1)]) {
      final estimate = estimateQueue(first, p, now); expect(estimate.ahead, isNull); expect(estimate.minutes, isNull);
    }
    expect(estimateQueue(progressed(first), progress('alpha', 3, 0), now).minutes, isNull);
  });
  test('different stalls and later new tickets never alter another stall’s position', () {
    final beta = receiptFor(queueRequest('b', vendor: 'beta'), 1).order;
    expect(estimateQueue(fourth, progress('alpha', 3, 0), now).ahead, 1);
    expect(estimateQueue(beta, progress('beta', 1, 0), now).ahead, 0);
    final seventh = receiptFor(queueRequest('7'), 7).order;
    expect(estimateQueue(seventh, progress('alpha', 3, 0), now).ahead, 4);
    expect(estimateQueue(fourth, progress('alpha', 3, 0), now).ahead, 1);
  });

  Future<void> mount(WidgetTester tester, FakeOrderRepository repo, {String uid = 'student', DateTime? clock}) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(theme: smartCanteenTheme(), home: Scaffold(body:
      StudentQueueScreen(repository: repo, studentUid: uid, clock: () => clock ?? now))));
    await tester.pump();
  }
  Future<void> press(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target); await tester.tap(target); await tester.pumpAndSettle();
  }
  testWidgets('queue loading, empty Active and empty History states are explicit', (tester) async {
    final repo = FakeOrderRepository(() => 'student')..loading = true; addTearDown(repo.dispose);
    await mount(tester, repo); expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repo.loading = false; repo.emit(); await tester.pumpAndSettle();
    expect(find.text('No active tickets yet'), findsOneWidget);
    await press(tester, find.widgetWithText(ChoiceChip, 'History')); expect(find.text('No completed tickets yet'), findsOneWidget);
  });
  testWidgets('own orders and multiple stalls have independent cards and no status controls', (tester) async {
    final repo = FakeOrderRepository(() => 'student'); addTearDown(repo.dispose);
    final a = receiptFor(queueRequest('1'), 4), b = receiptFor(queueRequest('2', vendor: 'beta'), 1);
    final outsider = receiptFor(queueRequest('3', student: 'someoneElse'), 5);
    for (final r in [a, b, outsider]) { repo.receipts[r.order.id] = r; }
    repo.publicProgress['alpha'] = progress('alpha', 3, 2); repo.publicProgress['beta'] = progress('beta', 1, 0);
    await mount(tester, repo); await tester.pumpAndSettle();
    final alpha = find.byKey(ValueKey('queue-${a.order.id}')), beta = find.byKey(ValueKey('queue-${b.order.id}'));
    expect(find.descendant(of: alpha, matching: find.text('Orders ahead: 1')), findsOneWidget);
    await tester.ensureVisible(beta);
    expect(find.descendant(of: beta, matching: find.text('Orders ahead: 0')), findsOneWidget);
    expect(find.text('Ticket #5'), findsNothing); expect(find.text('Start Preparing'), findsNothing);
    expect(find.text('Mark as Ready'), findsNothing); expect(tester.takeException(), isNull);
  });
  testWidgets('live progress and own statuses move Active to History with correct time-until-Ready', (tester) async {
    final repo = FakeOrderRepository(() => 'student'); addTearDown(repo.dispose);
    final receipt = receiptFor(queueRequest('1'), 1); var order = receipt.order;
    repo.receipts[order.id] = receipt; repo.publicProgress['alpha'] = progress('alpha', 1, 0);
    final clock = progressed(order).preparingAt!.toDate().add(const Duration(minutes: 5));
    await mount(tester, repo, clock: clock); await tester.pumpAndSettle(); expect(find.text('Waiting time unavailable'), findsOneWidget);
    order = progressed(order); repo.receipts[order.id] = OrderReceipt(order, receipt.items);
    repo.publicProgress['alpha'] = progress('alpha', 2, 1); repo.emit(); await tester.pumpAndSettle();
    expect(find.text('Preparing'), findsOneWidget); expect(find.text('Approx. 10 min until Ready'), findsOneWidget);
    order = progressed(order); repo.receipts[order.id] = OrderReceipt(order, receipt.items);
    repo.publicProgress['alpha'] = progress('alpha', 2, 0); repo.emit(); await tester.pumpAndSettle();
    expect(find.text('Ready for pickup'), findsOneWidget); expect(find.text('Approx. 10 min until Ready'), findsNothing);
    order = progressed(order); repo.receipts[order.id] = OrderReceipt(order, receipt.items); repo.emit(); await tester.pumpAndSettle();
    expect(find.text('No active tickets yet'), findsOneWidget);
    await press(tester, find.widgetWithText(ChoiceChip, 'History'));
    expect(find.text('Ticket #1'), findsOneWidget); expect(find.text('Completed'), findsWidgets);
  });
  testWidgets('missing progress and cached own/progress data never assert a zero wait', (tester) async {
    final repo = FakeOrderRepository(() => 'student'); addTearDown(repo.dispose);
    repo.receipts[first.id] = OrderReceipt(first, [first.firstItem]);
    await mount(tester, repo); await tester.pumpAndSettle();
    expect(find.text('Orders ahead: Unavailable'), findsOneWidget); expect(find.text('Waiting time unavailable'), findsOneWidget);
    repo.publicProgress['alpha'] = progress('alpha', 1, 0); repo.progressCached = true; repo.emit(); await tester.pumpAndSettle();
    expect(find.textContaining('Cached queue'), findsOneWidget); expect(find.text('Approx. 15 min until Ready'), findsNothing);
    repo.progressCached = false; repo.cached = true; repo.emit(); await tester.pumpAndSettle();
    expect(find.textContaining('Cached orders'), findsOneWidget); expect(find.text('Orders ahead: Unavailable'), findsOneWidget);
  });
  testWidgets('order and projection errors require explicit Retry or Refresh', (tester) async {
    final repo = FakeOrderRepository(() => 'student'); addTearDown(repo.dispose);
    repo.receipts[first.id] = OrderReceipt(first, [first.firstItem]); repo.publicProgress['alpha'] = progress('alpha', 1, 0);
    await mount(tester, repo); await tester.pumpAndSettle();
    repo.errorTarget = 'progress:alpha'; repo.streamError = const AccountException('offline'); repo.emit(); await tester.pumpAndSettle();
    expect(find.text('Unable to verify this stall’s queue progress.'), findsOneWidget);
    expect(find.text('Orders ahead: Unavailable'), findsOneWidget);
    repo.streamError = null; repo.errorTarget = null; await press(tester, find.text('Refresh Queue'));
    expect(find.text('Orders ahead: 0'), findsOneWidget);
    repo.errorTarget = 'orders'; repo.streamError = StateError('offline'); repo.emit(); await tester.pumpAndSettle();
    expect(find.text('Unable to load your queue. Retry'), findsOneWidget);
    repo.streamError = null; repo.errorTarget = null; await press(tester, find.text('Unable to load your queue. Retry'));
    expect(find.text('Ticket #1'), findsOneWidget);
  });
  testWidgets('changing UID clears old cards while the new session is loading', (tester) async {
    var uid = 'student'; final repo = FakeOrderRepository(() => uid); addTearDown(repo.dispose);
    repo.receipts[first.id] = OrderReceipt(first, [first.firstItem]);
    final other = receiptFor(queueRequest('2', student: 'newStudent', vendor: 'beta'), 2); repo.receipts[other.order.id] = other;
    await mount(tester, repo); await tester.pumpAndSettle(); expect(find.text('alpha Kitchen'), findsOneWidget);
    uid = 'newStudent'; repo.loading = true;
    await tester.pumpWidget(MaterialApp(theme: smartCanteenTheme(), home: Scaffold(body:
      StudentQueueScreen(repository: repo, studentUid: uid)))); await tester.pump();
    expect(find.text('alpha Kitchen'), findsNothing); expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repo.loading = false; repo.emit(); await tester.pumpAndSettle();
    expect(find.text('beta Kitchen'), findsOneWidget); expect(find.text('alpha Kitchen'), findsNothing);
  });
}
