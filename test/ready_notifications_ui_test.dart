import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fyp_app/models/confirmed_order.dart';
import 'package:my_fyp_app/models/user_profile.dart';
import 'package:my_fyp_app/screens/orders_screen.dart';
import 'package:my_fyp_app/screens/ready_notifications_screen.dart';
import 'package:my_fyp_app/screens/student_stall_menu.dart';
import 'package:my_fyp_app/services/ready_notifications.dart';
import 'package:my_fyp_app/services/student_cart.dart';
import 'package:my_fyp_app/theme/app_theme.dart';
import 'package:my_fyp_app/widgets/stall_menu_header.dart';
import 'stage_one_test.dart' as stage;
import 'support/catalog_fixtures.dart';
import 'support/fake_catalog_repository.dart';
import 'support/fake_order_repository.dart';
import 'support/ready_notification_fixtures.dart';

void main() {
  final pending = notificationReceipt('1', student: 'test-user');
  final ready = notificationReceipt('1', student: 'test-user', status: 'Ready');
  stage.TestRepository app({OrderReceipt? receipt}) {
    final repo = stage.TestRepository()..session(stage.profile(AccountRole.student));
    if (receipt != null) repo.orderRepository.receipts[receipt.order.id] = receipt;
    addTearDown(repo.dispose); return repo;
  }
  Finder vertical() => find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
  Future<void> reveal(WidgetTester tester, Finder target, {double delta = 200}) async {
    if (target.evaluate().isEmpty) { await tester.scrollUntilVisible(target, delta, scrollable: vertical()); }
    await tester.ensureVisible(target); await tester.pumpAndSettle();
  }
  Future<void> press(WidgetTester tester, Finder target, {double delta = 200}) async {
    await reveal(tester, target, delta: delta); await tester.tap(target); await tester.pumpAndSettle();
  }
  Future<void> center(WidgetTester tester) async {
    await press(tester, find.text('Profile'));
    await press(tester, find.byKey(const ValueKey('ready-notifications-button')));
  }
  Badge indicator(WidgetTester tester) => tester.widget<Badge>(find.byKey(const ValueKey('student-notification-indicator')));
  void emit(stage.TestRepository repo, OrderReceipt receipt) {
    repo.orderRepository.receipts[receipt.order.id] = receipt; repo.orderRepository.emit();
  }
  void dismissAlert(WidgetTester tester) {
    final context = tester.element(find.byType(SnackBar).first);
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
  }

  testWidgets('Pixel 6 Stall Menu aligns Back title Cart on one row and live quantity preserves 48px targets', (tester) async {
    final repo = FakeCatalogRepository(); populate(repo); addTearDown(repo.dispose);
    final cart = StudentCart('student', repo); addTearDown(cart.dispose); var visits = 0;
    await tester.binding.setSurfaceSize(const Size(412, 915)); addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(theme: smartCanteenTheme(), home: StudentStallMenu(
      vendorId: 'alpha', repository: repo, cart: cart, onCart: () => visits++)));
    await tester.pumpAndSettle();
    final title = find.text('Stall Menu'), back = find.byType(IconButton).first, action = find.byKey(const ValueKey('stall-menu-cart'));
    expect((tester.getCenter(title).dy - tester.getCenter(action).dy).abs(), lessThan(1));
    expect((tester.getCenter(back).dy - tester.getCenter(action).dy).abs(), lessThan(1));
    expect(tester.getSize(action).height, greaterThanOrEqualTo(48)); expect(tester.getSize(back).width, greaterThanOrEqualTo(48));
    cart.add(await repo.selection('alpha', 'bowl'), 20); await tester.pumpAndSettle(); expect(find.text('Cart (20)'), findsOneWidget);
    await press(tester, action); expect(visits, 1); expect(tester.takeException(), isNull);
  });

  testWidgets('Stall Menu enlarged text uses adaptive fallback without clipping or losing Cart navigation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640)); addTearDown(() => tester.binding.setSurfaceSize(null)); var visits = 0;
    await tester.pumpWidget(MaterialApp(theme: smartCanteenTheme(), home: MediaQuery(
      data: const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(1.8)),
      child: Scaffold(body: SingleChildScrollView(child: StallMenuHeader(itemCount: 40, onCart: () => visits++))))));
    await tester.pumpAndSettle(); final action = find.byKey(const ValueKey('stall-menu-cart'));
    expect(tester.getCenter(action).dy, greaterThan(tester.getCenter(find.text('Stall Menu')).dy));
    expect(tester.getSize(action).height, greaterThanOrEqualTo(48)); await press(tester, action);
    expect(visits, 1); expect(tester.takeException(), isNull);
  });

  testWidgets('confirmed Ready transition alerts correct stall/ticket and exposes unread Profile badge and Details', (tester) async {
    final repo = app(receipt: pending); await stage.launch(tester, repo);
    emit(repo, ready); await tester.pumpAndSettle();
    expect(find.text('alpha Kitchen • Ticket #1: Ready for pickup'), findsOneWidget);
    expect(indicator(tester).isLabelVisible, true);
    expect(tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar)).items.length, 5);
    await center(tester);
    expect(find.text('Unread'), findsOneWidget); expect(find.widgetWithText(OrderStatusBadge, 'Ready'), findsOneWidget);
    await press(tester, find.widgetWithText(OutlinedButton, 'View Order Details'));
    expect(tester.widget<OrderDetails>(find.byType(OrderDetails)).order.id, ready.order.id);
    await tester.pageBack(); await tester.pumpAndSettle(); expect(find.text('Viewed'), findsOneWidget);
    await tester.pageBack(); await tester.pumpAndSettle(); expect(indicator(tester).isLabelVisible, false);
  });

  testWidgets('transient View action opens exact own Order Details directly', (tester) async {
    final repo = app(receipt: pending); await stage.launch(tester, repo); emit(repo, ready); await tester.pumpAndSettle();
    await press(tester, find.widgetWithText(SnackBarAction, 'View'));
    expect(tester.widget<OrderDetails>(find.byType(OrderDetails)).order.id, ready.order.id);
    expect(find.text('Ticket #1'), findsOneWidget);
  });

  testWidgets('initial Ready is discoverable without historical popup and viewing survives refresh', (tester) async {
    final repo = app(receipt: ready); await stage.launch(tester, repo);
    expect(find.byType(SnackBar), findsNothing); expect(indicator(tester).isLabelVisible, true);
    await center(tester); await press(tester, find.widgetWithText(OutlinedButton, 'View Order Details'));
    await tester.pageBack(); await tester.pumpAndSettle();
    await press(tester, find.text('Refresh Notifications')); expect(find.text('Viewed'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('repeated snapshots and tab/center navigation do not replay transient alerts', (tester) async {
    final repo = app(receipt: pending); await stage.launch(tester, repo); emit(repo, ready); await tester.pumpAndSettle();
    dismissAlert(tester); await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) { repo.orderRepository.emit(); await tester.pumpAndSettle(); }
    await press(tester, find.text('Queue')); await press(tester, find.text('Home'));
    await center(tester); await press(tester, find.text('Refresh Notifications'));
    expect(find.byType(SnackBar), findsNothing); expect(find.byKey(ValueKey('notice-${ready.order.id}')), findsOneWidget);
  });

  testWidgets('multiple stalls/tickets alert together and remain separate in center', (tester) async {
    final repo = app(receipt: pending), betaPending = notificationReceipt('2', student: 'test-user', vendor: 'beta', ticket: 4);
    repo.orderRepository.receipts[betaPending.order.id] = betaPending;
    await stage.launch(tester, repo);
    final betaReady = notificationReceipt('2', student: 'test-user', vendor: 'beta', ticket: 4, status: 'Ready');
    repo.orderRepository.receipts[ready.order.id] = ready; emit(repo, betaReady); await tester.pumpAndSettle();
    expect(find.textContaining('alpha Kitchen • Ticket #1: Ready for pickup'), findsOneWidget);
    expect(find.textContaining('beta Kitchen • Ticket #4: Ready for pickup'), findsOneWidget);
    await press(tester, find.widgetWithText(SnackBarAction, 'View'));
    expect(find.byType(ReadyNotificationsScreen), findsOneWidget);
    await reveal(tester, find.byKey(ValueKey('notice-${betaReady.order.id}')));
    expect(find.text('Ticket #4'), findsOneWidget); expect(find.text('Ticket #1'), findsOneWidget);
  });

  testWidgets('cached Ready cannot alert or create badge; center explains offline data until server confirms', (tester) async {
    final repo = app(receipt: pending); await stage.launch(tester, repo);
    repo.orderRepository.cached = true; emit(repo, ready); await tester.pumpAndSettle();
    expect(indicator(tester).isLabelVisible, false); expect(find.byType(SnackBar), findsNothing);
    await center(tester); expect(find.textContaining('Offline or cached orders'), findsOneWidget);
    expect(find.byKey(ValueKey('notice-${ready.order.id}')), findsNothing);
    repo.orderRepository.cached = false; repo.orderRepository.emit(); await tester.pumpAndSettle();
    expect(find.text('Ready for pickup'), findsOneWidget); expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('notification center loading/error/Retry retains safe states and recovers', (tester) async {
    final repo = app(receipt: ready)..orderRepository.loading = true;
    await stage.launch(tester, repo); await press(tester, find.text('Profile'));
    final action = find.byKey(const ValueKey('ready-notifications-button')); await reveal(tester, action);
    await tester.tap(action); await tester.pump(); await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    repo.orderRepository.loading = false; repo.orderRepository.emit(); await tester.pumpAndSettle();
    repo.orderRepository.errorTarget = 'orders'; repo.orderRepository.streamError = StateError('offline');
    repo.orderRepository.emit(); await tester.pumpAndSettle(); expect(find.textContaining('Ready updates could not be verified'), findsOneWidget);
    repo.orderRepository.streamError = null; await press(tester, find.text('Retry Notifications'));
    expect(find.text('Ready for pickup'), findsOneWidget); expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Ready to Completed moves notification to history with current status and preserved read state', (tester) async {
    final repo = app(receipt: ready); await stage.launch(tester, repo); await center(tester);
    emit(repo, notificationReceipt('1', student: 'test-user', status: 'Completed')); await tester.pumpAndSettle();
    expect(find.text('No Ready notifications yet'), findsOneWidget);
    await press(tester, find.widgetWithText(ChoiceChip, 'History'));
    expect(find.text('Completed — this order has been collected.'), findsOneWidget); expect(find.text('Unread'), findsOneWidget);
    expect(find.text('Ready for pickup'), findsNothing); expect(find.byType(SnackBar), findsNothing);
    await press(tester, find.widgetWithText(OutlinedButton, 'View Order Details'));
    expect(tester.widget<OrderDetails>(find.byType(OrderDetails)).order.status, 'Completed');
  });

  testWidgets('account switch disposes notifications, open routes and prior Student transient alerts', (tester) async {
    final repo = app(receipt: pending); await stage.launch(tester, repo); emit(repo, ready); await tester.pumpAndSettle();
    await center(tester);
    repo.session(const UserProfile(uid: 'student-b', fullName: 'Student B', email: 'student-b@example.com',
      phoneNumber: '0123456789', role: AccountRole.student)); await tester.pumpAndSettle();
    expect(find.byType(ReadyNotificationsScreen), findsNothing); expect(find.byType(SnackBar), findsNothing);
    expect(indicator(tester).isLabelVisible, false); await center(tester); expect(find.text('No Ready notifications yet'), findsOneWidget);
    expect(find.text('Ticket #1'), findsNothing);
  });

  testWidgets('Logout clears queued Ready alerts and next login starts fresh without replay', (tester) async {
    final repo = app(receipt: pending); await stage.launch(tester, repo); emit(repo, ready); await tester.pumpAndSettle();
    await press(tester, find.text('Profile')); await press(tester, find.widgetWithText(OutlinedButton, 'Logout'));
    expect(find.text('Welcome Back'), findsOneWidget); expect(find.byType(SnackBar), findsNothing);
    repo.session(stage.profile(AccountRole.student)); await tester.pumpAndSettle();
    expect(indicator(tester).isLabelVisible, true); expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Vendor role has no Student notification center or indicator', (tester) async {
    final repo = stage.TestRepository()..session(stage.profile(AccountRole.vendor, setup: true)); addTearDown(repo.dispose);
    repo.orderRepository.receipts[ready.order.id] = ready;
    await stage.launch(tester, repo); await press(tester, find.text('Profile'));
    expect(find.byKey(const ValueKey('ready-notifications-button')), findsNothing);
    expect(find.byKey(const ValueKey('student-notification-indicator')), findsNothing);
    expect(tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar)).items.length, 4);
  });

  testWidgets('background Ready updates stay in center and resume does not replay an alert', (tester) async {
    addTearDown(() => tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    final repo = app(receipt: pending); await stage.launch(tester, repo);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    emit(repo, ready); await tester.pumpAndSettle(); expect(find.byType(SnackBar), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing); expect(indicator(tester).isLabelVisible, true);
    final next = notificationReceipt('2', student: 'test-user', ticket: 2); emit(repo, next); await tester.pumpAndSettle();
    emit(repo, notificationReceipt('2', student: 'test-user', ticket: 2, status: 'Ready')); await tester.pumpAndSettle();
    expect(find.text('alpha Kitchen • Ticket #2: Ready for pickup'), findsOneWidget);
  });

  testWidgets('small notification center wraps long stall/ticket content with large text and accessible actions', (tester) async {
    final repo = FakeOrderRepository(() => 'student'); addTearDown(repo.dispose);
    final receipt = notificationReceipt('1', status: 'Ready', ticket: 2147483647,
      stallName: 'A long synthetic campus stall name for the notification layout'); repo.receipts[receipt.order.id] = receipt;
    final controller = ReadyNotifications(studentUid: 'student', repository: repo, currentUid: () => 'student'); addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(320, 640)); addTearDown(() => tester.binding.setSurfaceSize(null));
    String? opened;
    await tester.pumpWidget(MaterialApp(theme: smartCanteenTheme(), home: MediaQuery(
      data: const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(1.6)),
      child: ReadyNotificationsScreen(notifications: controller, onOpen: (id) => opened = id))));
    await tester.pumpAndSettle(); final action = find.widgetWithText(OutlinedButton, 'View Order Details');
    await reveal(tester, action); expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
    await press(tester, action); expect(opened, receipt.order.id); expect(tester.takeException(), isNull);
  });
}
