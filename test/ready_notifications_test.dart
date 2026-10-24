import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fyp_app/models/confirmed_order.dart';
import 'package:my_fyp_app/models/vendor_menu.dart';
import 'package:my_fyp_app/services/ready_notifications.dart';
import 'support/fake_order_repository.dart';
import 'support/ready_notification_fixtures.dart';

class _Feed extends FakeOrderRepository {
  _Feed() : super(() => 'student') {
    eventsForReady = StreamController<MenuData<ConfirmedOrder>>.broadcast(sync: true,
      onListen: () => listeners++, onCancel: () => listeners--);
  }
  late final StreamController<MenuData<ConfirmedOrder>> eventsForReady;
  int listeners = 0;
  final vendorArguments = <bool>[];
  @override
  Stream<MenuData<ConfirmedOrder>> orders({required bool vendor}) {
    vendorArguments.add(vendor); return eventsForReady.stream;
  }
  void send(List<ConfirmedOrder> orders, {bool cached = false}) => eventsForReady.add(MenuData(orders, cached: cached));
  @override
  void dispose() { eventsForReady.close(); super.dispose(); }
}

void main() {
  final pending = notificationReceipt('1').order;
  final preparing = progressed(pending), ready = progressed(preparing), completed = progressed(ready);
  Future<void> turn() => Future<void>.delayed(Duration.zero);
  Future<(ReadyNotifications, _Feed)> setup({String? Function()? uid, bool foreground = true}) async {
    final feed = _Feed();
    final controller = ReadyNotifications(studentUid: 'student', repository: feed,
      currentUid: uid ?? () => 'student', foreground: foreground);
    addTearDown(() { controller.dispose(); feed.dispose(); });
    await turn(); return (controller, feed);
  }

  test('observed confirmed Ready transition creates one deterministic owner-scoped event', () async {
    final (controller, feed) = await setup();
    feed.send([pending]); feed.send([preparing]); feed.send([ready]);
    expect(controller.takeAlerts(), [ready.id]); expect(controller.unreadCount, 1);
    expect(controller.notices.single.eventId, 'student/${ready.id}/${ready.readyAt!.seconds}:${ready.readyAt!.nanoseconds}');
    expect(controller.takeAlerts(), isEmpty); expect(feed.vendorArguments, [false]);
  });

  test('initial Ready and Completed snapshots populate center without replaying history', () async {
    final (controller, feed) = await setup();
    final oldCompleted = notificationReceipt('2', ticket: 2, status: 'Completed').order;
    feed.send([ready, oldCompleted]);
    expect(controller.takeAlerts(), isEmpty); expect(controller.notices.length, 2);
    expect(controller.notice(ready.id)!.viewed, false); expect(controller.notice(oldCompleted.id)!.viewed, true);
    expect(controller.unreadCount, 1);
  });

  test('wrong Student records are ignored even if a repository test double leaks them', () async {
    final (controller, feed) = await setup();
    final outsider = notificationReceipt('2', student: 'other', status: 'Ready').order;
    feed.send([pending, outsider]); feed.send([ready, outsider]);
    expect(controller.notices.map((n) => n.order.studentUid), ['student']);
    expect(controller.takeAlerts(), [ready.id]); expect(controller.notice(outsider.id), isNull);
  });

  test('multiple tickets from different stalls retain separate event identities', () async {
    final (controller, feed) = await setup();
    final beta = notificationReceipt('2', vendor: 'beta', ticket: 1).order;
    feed.send([pending, beta]); feed.send([ready, progressed(progressed(beta))]);
    expect(controller.takeAlerts().toSet(), {ready.id, beta.id}); expect(controller.unreadCount, 2);
    expect(controller.notices.map((n) => n.order.vendorUid).toSet(), {'alpha', 'beta'});
  });

  test('repeated snapshots, refresh and reconnection cannot repeat an announced Ready event', () async {
    final (controller, feed) = await setup();
    feed.send([pending]); feed.send([ready]); expect(controller.takeAlerts(), [ready.id]);
    for (var i = 0; i < 4; i++) { feed.send([ready]); }
    feed.send([ready], cached: true); feed.send([ready]);
    await controller.refresh(); feed.send([ready]);
    expect(controller.takeAlerts(), isEmpty); expect(controller.notices.length, 1);
    expect(feed.listeners, 1);
  });

  test('initial cached Ready is not a notification or baseline; first server Ready is existing information', () async {
    final (controller, feed) = await setup();
    feed.send([ready], cached: true);
    expect(controller.connection, ReadyConnection.cached); expect(controller.notices, isEmpty); expect(controller.unreadCount, 0);
    feed.send([ready]); expect(controller.takeAlerts(), isEmpty); expect(controller.notices.single.order.id, ready.id);
  });

  test('cached Ready cannot promote an observed Pending; a later confirmed transition can', () async {
    final (controller, feed) = await setup();
    feed.send([pending]); feed.send([ready], cached: true);
    expect(controller.notices, isEmpty); expect(controller.takeAlerts(), isEmpty);
    feed.send([ready]); expect(controller.takeAlerts(), [ready.id]);
  });

  test('an order first observed Ready after baseline is listed without inventing a transition', () async {
    final (controller, feed) = await setup();
    feed.send([]); feed.send([ready]);
    expect(controller.unreadCount, 1); expect(controller.takeAlerts(), isEmpty);
  });

  test('malformed Ready without authoritative timestamp/revision cannot create an event', () async {
    final (controller, feed) = await setup(); feed.send([pending]);
    final malformed = ConfirmedOrder(id: pending.id, studentUid: pending.studentUid, vendorUid: pending.vendorUid,
      stallName: pending.stallName, ticket: 1, totalSen: pending.totalSen, itemCount: 1,
      preparationMinutes: 15, paymentMethod: 'ewallet', createdAt: pending.createdAt,
      firstItem: pending.firstItem, status: 'Ready');
    feed.send([malformed]); expect(controller.notices, isEmpty); expect(controller.takeAlerts(), isEmpty);
  });

  test('markViewed is session-local, order-specific and stable across refresh', () async {
    final (controller, feed) = await setup();
    final other = notificationReceipt('2', status: 'Ready').order;
    feed.send([ready, other]); controller.markViewed(ready.id);
    expect(controller.unreadCount, 1); expect(controller.notice(ready.id)!.viewed, true);
    await controller.refresh(); feed.send([ready, other]); expect(controller.unreadCount, 1);
    controller.markViewed('unknown'); expect(controller.unreadCount, 1);
  });

  test('new app session reconstructs existing Ready information without durable viewed receipts', () async {
    final (controller, feed) = await setup(); feed.send([ready]); controller.markViewed(ready.id); controller.dispose();
    final again = ReadyNotifications(studentUid: 'student', repository: feed, currentUid: () => 'student'); addTearDown(again.dispose);
    await turn(); feed.send([ready]); expect(again.unreadCount, 1); expect(again.takeAlerts(), isEmpty);
  });

  test('Ready to Completed preserves event, read state and actual history status without another alert', () async {
    final (controller, feed) = await setup(); feed.send([pending]); feed.send([ready]); controller.takeAlerts();
    final identity = controller.notices.single.eventId; controller.markViewed(ready.id); feed.send([completed]);
    expect(controller.notices.single.eventId, identity); expect(controller.notices.single.order.status, 'Completed');
    expect(controller.notices.single.viewed, true); expect(controller.takeAlerts(), isEmpty);
  });

  test('coalesced Pending to Completed update is history and never announces Ready for pickup', () async {
    final (controller, feed) = await setup(); feed.send([pending]); feed.send([completed]);
    expect(controller.notices.single.order.status, 'Completed'); expect(controller.unreadCount, 0);
    expect(controller.takeAlerts(), isEmpty);
  });

  test('cached/error data preserves last confirmed records and read state with a connection warning', () async {
    final (controller, feed) = await setup(); feed.send([ready]); controller.markViewed(ready.id);
    feed.send([completed], cached: true);
    expect(controller.connection, ReadyConnection.cached); expect(controller.notices.single.order.status, 'Ready');
    feed.eventsForReady.addError(StateError('offline')); expect(controller.connection, ReadyConnection.error);
    expect(controller.unreadCount, 0); expect(controller.takeAlerts(), isEmpty);
    await controller.refresh(); feed.send([completed]); expect(controller.connection, ReadyConnection.server);
    expect(controller.notices.single.order.status, 'Completed');
  });

  test('background updates do not alert and resume rebaselines without historical replay', () async {
    final (controller, feed) = await setup(); feed.send([pending]); controller.setForeground(false); feed.send([ready]);
    expect(controller.unreadCount, 1); expect(controller.takeAlerts(), isEmpty);
    controller.setForeground(true); await turn(); feed.send([ready]);
    expect(controller.takeAlerts(), isEmpty);
    final later = notificationReceipt('2', ticket: 2).order;
    feed.send([ready, later]); feed.send([ready, progressed(progressed(later))]);
    expect(controller.takeAlerts(), [later.id]);
  });

  test('UID change expires subscription, records, badge and queued alerts before next account', () async {
    String? uid = 'student'; final (controller, feed) = await setup(uid: () => uid);
    feed.send([pending]); feed.send([ready]); uid = 'other';
    expect(controller.notices, isEmpty); expect(controller.takeAlerts(), isEmpty);
    feed.send([ready]); await turn(); expect(feed.listeners, 0);
    expect(controller.unreadCount, 0); expect(controller.connection, ReadyConnection.unavailable);
  });

  test('disposal cancels listener and ignores late stream events', () async {
    final (controller, feed) = await setup(); feed.send([pending]); controller.dispose(); await turn();
    expect(feed.listeners, 0); feed.send([ready]); expect(controller.takeAlerts(), isEmpty);
  });

  test('server removal and reappearance cannot expose a stale record or replay an event', () async {
    final (controller, feed) = await setup(); feed.send([pending]); feed.send([ready]); controller.takeAlerts();
    feed.send([]); expect(controller.notices, isEmpty);
    feed.send([ready]); expect(controller.notices.length, 1); expect(controller.takeAlerts(), isEmpty);
  });

  test('missing repository fails closed with no records or notifications', () async {
    final controller = ReadyNotifications(studentUid: 'student', repository: null, currentUid: () => 'student');
    addTearDown(controller.dispose); await turn();
    expect(controller.connection, ReadyConnection.unavailable); expect(controller.unreadCount, 0); expect(controller.takeAlerts(), isEmpty);
  });

  test('a closed update stream is not presented as a live notification connection', () async {
    final (controller, feed) = await setup(); feed.send([ready]);
    await feed.eventsForReady.close();
    expect(controller.connection, ReadyConnection.error); expect(controller.notices.single.order.id, ready.id);
    expect(controller.takeAlerts(), isEmpty);
  });
}
